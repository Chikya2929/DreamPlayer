import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A DLNA/UPnP MediaRenderer discovered on the LAN (typically a smart TV).
@immutable
class DlnaTarget {
  const DlnaTarget({
    required this.name,
    required this.model,
    required this.controlUrl,
    required this.usn,
  });

  final String name;
  final String model;

  /// The absolute AVTransport control URL SOAP posts go to.
  final String controlUrl;
  final String usn;
}

const String dlnaServiceType = 'urn:schemas-upnp-org:service:AVTransport:1';

/// Resolves the description's relative `controlURL` against its location.
String resolveControlUrl(String locationUrl, String controlUrl) {
  final trimmed = controlUrl.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final rootStart = locationUrl.indexOf('://');
  if (rootStart < 0) return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  final slash = locationUrl.indexOf('/', rootStart + 3);
  final root = slash < 0 ? locationUrl : locationUrl.substring(0, slash);
  if (trimmed.startsWith('/')) return '$root$trimmed';
  final dir = locationUrl.substring(0, locationUrl.lastIndexOf('/') + 1);
  return '$dir$trimmed';
}

/// A tag's text value inside a UPnP device description document.
String descriptionTagValue(String xml, String tag) {
  final match = RegExp(
    '(?:[\\w-]+:)?$tag(?:\\s[^>]*)?>([^<]*)<',
  ).firstMatch(xml);
  return match?.group(1)?.trim() ?? '';
}

/// The AVTransport service's control URL from a description document, or ''
/// when the device does not expose one (then it is not a real renderer).
String controlUrlFromDescription(String xml) {
  for (final service
      in RegExp('<service>([\\s\\S]*?)</service>').allMatches(xml)) {
    final body = service.group(1) ?? '';
    final serviceType = descriptionTagValue(body, 'serviceType');
    if (serviceType.startsWith('urn:schemas-upnp-org:service:AVTransport')) {
      return descriptionTagValue(body, 'controlURL');
    }
  }
  return '';
}

/// Builds the SOAP envelope for an AVTransport action.
String dlnaSoapEnvelope(String action, String arguments) {
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope '
      'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body><u:$action xmlns:u="$dlnaServiceType">'
      '$arguments</u:$action></s:Body></s:Envelope>';
}

/// DIDL-Lite metadata so the TV shows the title instead of "Unknown".
String buildDidlLite(String title) {
  final escaped = xmlEscape(title);
  return '<DIDL-Lite '
      'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="0" restricted="1">'
      '<dc:title>$escaped</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '</item></DIDL-Lite>';
}

String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Parses an UPnP `h:mm:ss[.mmm]` value into milliseconds.
int parseUpnpTime(String value) {
  final match = RegExp(
    r'^\s*(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\s*$',
  ).firstMatch(value);
  if (match == null) return 0;
  final h = int.tryParse(match.group(1) ?? '') ?? 0;
  final m = int.tryParse(match.group(2) ?? '') ?? 0;
  final s = int.tryParse(match.group(3) ?? '') ?? 0;
  var ms = int.tryParse((match.group(4) ?? '0').padRight(3, '0')) ?? 0;
  if (ms > 999) ms = 999;
  return h * 3600000 + m * 60000 + s * 1000 + ms;
}

/// Formats milliseconds back into the UPnP `h:mm:ss.mmm` string.
String formatUpnpTime(int ms) {
  final positive = ms < 0 ? 0 : ms;
  final h = positive ~/ 3600000;
  final m = (positive ~/ 60000) % 60;
  final s = (positive ~/ 1000) % 60;
  final frac = positive % 1000;
  final fracText = frac.toString().padLeft(3, '0');
  return '$h:'
      '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$fracText';
}

/// Elapsed / duration out of a GetPositionInfo SOAP response.
DlnaPosition? parsePositionInfo(String responseXml) {
  final elapsed = descriptionTagValue(responseXml, 'TrackElapsedTime');
  final duration = descriptionTagValue(responseXml, 'TrackDuration');
  if (elapsed.isEmpty && duration.isEmpty) return null;
  return DlnaPosition(
    positionMs: parseUpnpTime(elapsed),
    durationMs: parseUpnpTime(duration),
  );
}

class DlnaPosition {
  const DlnaPosition({required this.positionMs, required this.durationMs});
  final int positionMs;
  final int durationMs;
}

/// DLNA AVTransport cast client.
///
/// The SSDP search itself needs the native multicast lock (`discoverDlna` on
/// `dreamplayer/multicast`); the SOAP control is plain HTTP from Dart, so it
/// works for every source the receiver can reach (direct http(s), and any
/// proxy URL the sender passes in).
class DlnaClient extends ChangeNotifier {
  static const _methodChannel = MethodChannel('dreamplayer/multicast');

  /// Devices from the last discovery, deduped by USN prefix (a MediaRenderer
  /// and its AVTransport service both answer with the same uuid).
  final Map<String, DlnaTarget> targets = {};

  /// The live session, if any.
  DlnaCastSession? session;

  Future<List<DlnaTarget>> discover() async {
    targets.clear();
    try {
      final raw =
          await _methodChannel.invokeMethod<List<dynamic>>('discoverDlna');
      final futures = <Future<void>>[];
      for (final item in raw ?? []) {
        if (item is! Map || item['location'] is! String) continue;
        final usn = ((item['usn'] as String? ?? '')).split('::').first;
        if (usn.isEmpty || targets.containsKey(usn)) continue;
        futures.add(_resolveTarget(item['location'] as String, usn));
      }
      await Future.wait(futures);
    } on PlatformException {
      // Multicast lock unavailable — no devices.
    }
    notifyListeners();
    return targets.values.toList();
  }

  Future<void> _resolveTarget(String location, String usn) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(Uri.parse(location));
      final response = await request.close();
      final xml = await utf8.decodeStream(response);
      final friendly = descriptionTagValue(xml, 'friendlyName');
      final model = descriptionTagValue(xml, 'modelName');
      final control = controlUrlFromDescription(xml);
      if (control.isEmpty) return;
      targets[usn] = DlnaTarget(
        name: friendly.isEmpty ? 'DLNA device' : friendly,
        model: model.isEmpty ? '' : model,
        controlUrl: resolveControlUrl(location, control),
        usn: usn,
      );
    } catch (_) {
      // Unreachable description — skip the device silently.
    }
  }

  /// Starts casting [uri] on [target]; the returned session polls position.
  Future<bool> cast(
    DlnaTarget target, {
    required String uri,
    required String title,
    required int positionMs,
  }) async {
    try {
      final setUri = await post(target, 'SetAVTransportURI',
          '<InstanceID>0</InstanceID>'
          '<CurrentURI>${xmlEscape(uri)}</CurrentURI>'
          '<CurrentURIMetaData>${buildDidlLite(title)}</CurrentURIMetaData>');
      if (!ok(setUri)) return false;
      if (positionMs > 30000) {
        final seek = await post(
          target,
          'Seek',
          '<InstanceID>0</InstanceID>'
          '<Unit>REL_TIME</Unit>'
          '<Target>${formatUpnpTime(positionMs)}</Target>',
        );
        // Best-effort: a renderer that refuses resume still plays from 0.
        ok(seek);
      }
      final play = await post(target, 'Play',
          '<InstanceID>0</InstanceID><Speed>1</Speed>');
      if (!ok(play)) return false;
      session?.stopTimer();
      session = DlnaCastSession(target, paused: false)..startPolling();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> pause() => transportCommand('Pause');
  Future<void> play() => transportCommand('Play');

  Future<void> transportCommand(String action) async {
    final current = session;
    if (current == null) return;
    if (action != 'Stop') {
      try {
        await post(current.target, action,
            '<InstanceID>0</InstanceID><Speed>1</Speed>');
      } catch (_) {}
    }
    current.paused = action == 'Pause';
    notifyListeners();
  }

  /// Stops the session and tells the TV to stop the transport.
  Future<void> stop() async {
    final current = session;
    session = null;
    current?.stopTimer();
    notifyListeners();
    if (current == null) return;
    try {
      await post(current.target, 'Stop', '<InstanceID>0</InstanceID>');
    } catch (_) {}
  }

  /// One AVTransport SOAP POST.
  static Future<(int, String)> post(
    DlnaTarget target,
    String action,
    String arguments,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.postUrl(Uri.parse(target.controlUrl));
    request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
    request.headers.set('SOAPACTION', '"$dlnaServiceType#$action"');
    request.add(utf8.encode(dlnaSoapEnvelope(action, arguments)));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final code = response.statusCode;
    client.close(force: true);
    return (code, body);
  }

  static bool ok((int, String) response) => response.$1 == 200;
}

/// A live DLNA cast: polls GetPositionInfo every 2 s while playing so the
/// sender shows where the TV actually is.
class DlnaCastSession extends ChangeNotifier {
  DlnaCastSession(this.target, {required this.paused});

  final DlnaTarget target;

  int positionMs = 0;
  int durationMs = 0;
  bool paused;
  Timer? _timer;

  void startPolling() {
    stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (paused) return;
    try {
      final (_, body) = await DlnaClient.post(
        target,
        'GetPositionInfo',
        '<InstanceID>0</InstanceID>',
      );
      final position = parsePositionInfo(body);
      if (position == null) return;
      positionMs = position.positionMs;
      durationMs = position.durationMs;
      notifyListeners();
    } catch (_) {
      // Transient failures keep the last known position.
    }
  }

  @override
  void dispose() {
    stopTimer();
    super.dispose();
  }
}
