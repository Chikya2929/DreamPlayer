import 'package:flutter_test/flutter_test.dart';

import 'package:dream_player/models/video_item.dart';
import 'package:dream_player/services/cast_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('googleEligibility gates Cast, not the local transports', () {
    test('direct http(s) URL is directPlayable', () {
      const video = VideoItem(id: '1', title: 'x', duration: Duration(minutes: 5), uri: 'http://192.168.1.6/v.mp4');
      expect(castEligibility(video), CastEligibility.directPlayable);
    });

    test('loopback URL needs the LAN server', () {
      const video = VideoItem(id: '1', title: 'x', duration: Duration(minutes: 5), uri: 'http://127.0.0.1:8123/v');
      expect(castEligibility(video), CastEligibility.needsLocalServer);
    });

    test('SMB is never castable to Google', () {
      const video = VideoItem(id: '1', title: 'x', duration: Duration(minutes: 5), uri: 'smb://nas/share/v.mkv');
      expect(castEligibility(video), CastEligibility.needsLocalServer);
    });
  });
}
