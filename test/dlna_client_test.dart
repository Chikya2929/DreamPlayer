import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/services/dlna_client.dart';

void main() {
  group('resolveControlUrl', () {
    test('absolute URL is kept', () {
      expect(
        resolveControlUrl('http://192.168.1.5:49152/desc.xml', 'http://x/y'),
        'http://x/y',
      );
    });

    test('root-relative path attaches to the host root', () {
      expect(
        resolveControlUrl('http://192.168.1.5:49152/desc/device.xml', '/ctl'),
        'http://192.168.1.5:49152/ctl',
      );
    });

    test('relative path resolves against the description directory', () {
      expect(
        resolveControlUrl('http://192.168.1.5:49152/desc/device.xml', 'ctl.xml'),
        'http://192.168.1.5:49152/desc/ctl.xml',
      );
    });
  });

  group('description parsing', () {
    const xml = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
<device>
<deviceType>urn:schemas-upnp-org:device:MediaRenderer:3</deviceType>
<friendlyName>Living Room TV</friendlyName>
<modelName>VIDAA U6</modelName>
<serviceList>
<service>
<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
<controlURL>/rc/control</controlURL>
</service>
<service>
<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>/dev/uuid-1/AVTransport/control</controlURL>
</service>
</serviceList>
</device>
</root>''';

    test('reads friendlyName/modelName', () {
      expect(descriptionTagValue(xml, 'friendlyName'), 'Living Room TV');
      expect(descriptionTagValue(xml, 'modelName'), 'VIDAA U6');
    });

    test('finds the AVTransport control URL, skipping other services', () {
      expect(
        controlUrlFromDescription(xml),
        '/dev/uuid-1/AVTransport/control',
      );
    });

    test('empty when no AVTransport service exists', () {
      expect(
        controlUrlFromDescription('<serviceList></serviceList>'),
        '',
      );
    });
  });

  group('SOAP envelope', () {
    test('carries the action namespaced to AVTransport', () {
      final envelope = dlnaSoapEnvelope(
        'SetAVTransportURI',
        '<InstanceID>0</InstanceID><CurrentURI>x</CurrentURI>',
      );
      expect(envelope, contains('u:SetAVTransportURI'));
      expect(envelope, contains('urn:schemas-upnp-org:service:AVTransport:1'));
      expect(envelope, contains('<CurrentURI>x</CurrentURI>'));
    });
  });

  group('DIDL-Lite', () {
    test('escapes the title', () {
      final didl = buildDidlLite('House <S02> & Units');
      expect(didl, contains('<dc:title>House &lt;S02&gt; &amp; Units</dc:title>'));
      expect(didl, contains('object.item.videoItem'));
    });
  });

  group('UPnP rel time', () {
    test('parses h:mm:ss.mmm', () {
      expect(parseUpnpTime('1:02:03.456'), 3723456);
    });

    test('parses h:mm:ss with no fraction', () {
      expect(parseUpnpTime('0:05:07'), 307000);
    });

    test('empty/unknown parses to 0', () {
      expect(parseUpnpTime('NOT_IMPLEMENTED'), 0);
      expect(parseUpnpTime(''), 0);
    });

    test('round-trips through formatUpnpTime', () {
      const ms = 3723456;
      expect(formatUpnpTime(ms), '1:02:03.456');
      expect(parseUpnpTime(formatUpnpTime(ms)), ms);
      expect(parseUpnpTime(formatUpnpTime(307000)), 307000);
    });
  });

  group('GetPositionInfo response', () {
    test('extracts elapsed and duration', () {
      const response = '''
<u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
<Track>1</Track>
<TrackElapsedTime>0:12:34.500</TrackElapsedTime>
<TrackDuration>1:38:11.000</TrackDuration>
</u:GetPositionInfoResponse>''';
      final position = parsePositionInfo(response);
      expect(position, isNotNull);
      expect(position!.positionMs, 754500);
      expect(position.durationMs, 5891000);
    });

    test('null when the renderer answers empty', () {
      expect(parsePositionInfo('<nope/>'), isNull);
    });
  });
}
