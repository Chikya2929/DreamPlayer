import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/video_item.dart';
import 'cast_manager.dart';
import 'dlna_client.dart';
import 'dream_cast_client.dart';

/// Which transport a live send-to-TV session rides on.
enum CastTransport { googleCast, dlna, dreamCast }

/// One snapshotted "what is playing where", used both when the session
/// starts (the local playback hands it over) and to report its progress.
class CastRequest {
  const CastRequest({
    required this.video,
    required this.positionMs,
    required this.title,
  });

  final VideoItem video;
  final int positionMs;
  final String title;
}

/// Unified cast coordinator over the three transports a phone can hand off
/// playback with:
/// - **googleCast**: the system Cast session (a real Chromecast / Google TV).
/// - **dlna**: any AVTransport MediaRenderer (the Hisense VIDAA TV).
/// - **dreamCast**: another DreamPlayer install on the LAN (the Fire TV Stick
///   receiver service).
///
/// Casting PAUSES local playback — the receiver owns the transport after
/// `castTo*` returns true. `stop()` ends the remote transport and does NOT
/// auto-resume locally (tapping the video title row is the deliberate
/// resume path) except for Google Cast, whose expanded controller handles
/// its own handoff back.
class CastCoordinator extends ChangeNotifier {
  CastCoordinator._();

  static final CastCoordinator instance = CastCoordinator._();

  final DlnaClient dlna = DlnaClient();
  final DreamCastClient dream = DreamCastClient();

  CastTransport? active;
  String? deviceName;

  /// The request the session was started from.
  CastRequest? request;

  /// Poll the receiver's position so the sheet/Info can show it and the
  /// player can resume there on stop.
  int remotePositionMs = 0;
  int remoteDurationMs = 0;
  bool remotePaused = false;

  Timer? _pollTimer;

  bool get isCasting => active != null;

  /// Google Cast eligibility of the request (network source with a clean
  /// http(s) URL). DreamCast/DLNA have no such constraint: the receiver
  /// opens whatever URL it receives, so a loopback-served file needs the
  /// LAN server while a direct LAN URL (WebDAV/Jellyfin/DLNA transcoding
  /// proxy on the same subnet) is fine.
  static CastEligibility googleEligibility(CastRequest request) =>
      castEligibility(request.video);

  Future<bool> castToGoogleCast(
    CastRequest request,
    CastEligibility eligibility,
  ) async {
    if (eligibility != CastEligibility.directPlayable) return false;
    final manager = CastManager.instance;
    final ok = await manager.loadCurrent(
      request.video,
      positionMs: request.positionMs,
      title: request.title,
    );
    if (!ok) return false;
    active = CastTransport.googleCast;
    deviceName = manager.deviceName;
    this.request = request;
    notifyListeners();
    return true;
  }

  Future<bool> castToDlna(
    DlnaTarget target,
    CastRequest request,
  ) async {
    final uri = request.video.uri ?? request.video.path ?? '';
    if (uri.startsWith('smb:') ||
        uri.startsWith('ftp:') ||
        uri.startsWith('file:') ||
        uri.startsWith('content:') ||
        uri.startsWith('127.0.0.1')) {
      // Native/Dart loopback transports know nothing the TV can play.
      return false;
    }
    final ok = await dlna.cast(
      target,
      uri: _resolveRemoteUri(uri),
      title: request.title,
      positionMs: request.positionMs,
    );
    if (!ok) return false;
    active = CastTransport.dlna;
    deviceName = target.name;
    this.request = request;
    remotePaused = false;
    _startPolling();
    notifyListeners();
    return true;
  }

  Future<bool> castToDreamCast(
    DreamCastTarget target,
    CastRequest request,
  ) async {
    final uri = request.video.uri ?? request.video.path ?? '';
    final ok = await dream.send(
      target,
      uri: _resolveRemoteUri(uri),
      title: request.title,
    );
    if (!ok) return false;
    active = CastTransport.dreamCast;
    deviceName = target.name;
    this.request = request;
    // The receiver drives itself; poll nothing — DreamPlayer there reports
    // nothing over the wire yet.
    notifyListeners();
    return true;
  }

  /// WebDAV/Jellyfin headers cannot ride a DLNA/Dream request today (the
  /// receiver plays the URL bare), so the URL is passed through only when
  /// plain http(s) works; everything else keeps playing locally.
  String _resolveRemoteUri(String uri) => uri;

  /// Local-control bridge: mirrors gesture/backdrop transport control onto
  /// the live session.
  Future<void> setRemotePaused(bool paused) async {
    switch (active) {
      case CastTransport.googleCast:
        return;
      case CastTransport.dlna:
        if (paused) {
          await dlna.pause();
        } else {
          await dlna.play();
        }
        return;
      case CastTransport.dreamCast:
        return;
      case null:
        return;
    }
  }

  /// Ends the current session (Google Cast via the session manager, DLNA
  /// via AVTransport `Stop`, DreamCast best-effort).
  Future<void> stop() async {
    final transport = active;
    active = null;
    deviceName = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();
    switch (transport) {
      case CastTransport.googleCast:
        await CastManager.instance.stopCasting();
      case CastTransport.dlna:
        await dlna.stop();
      case CastTransport.dreamCast:
        break;
      case null:
        break;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (active != CastTransport.dlna) return;
      final session = dlna.session;
      if (session == null) {
        _pollTimer?.cancel();
        return;
      }
      remotePositionMs = session.positionMs;
      remoteDurationMs = session.durationMs;
      remotePaused = session.paused;
      notifyListeners();
    });
  }

  /// Called when the local player stops (screen disposed): nothing keeps
  /// polling forever if the session already died.
  void detachViewer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    detachViewer();
    super.dispose();
  }
}
