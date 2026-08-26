import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/ios_media_kit_pip_source_route.dart';

void main() {
  group('classifyIosMediaKitPipSource', () {
    test('recognizes an HLS path before query parameters', () {
      expect(
        classifyIosMediaKitPipSource(
          'https://example.com/live/channel.m3u8?token=abc&format=flv',
        ),
        IosMediaKitPipSourceRoute.hls,
      );
    });

    test('recognizes uppercase HLS extensions', () {
      expect(
        classifyIosMediaKitPipSource('https://example.com/live/MASTER.M3U8'),
        IosMediaKitPipSourceRoute.hls,
      );
    });

    test('recognizes HLS markers contained within the URL path', () {
      expect(
        classifyIosMediaKitPipSource(
          'https://example.com/live/channel.m3u8/variant',
        ),
        IosMediaKitPipSourceRoute.hls,
      );
    });

    test('does not route FLV or query-only HLS markers to HLS', () {
      expect(
        classifyIosMediaKitPipSource('https://example.com/live/channel.flv'),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
      expect(
        classifyIosMediaKitPipSource(
          'https://example.com/live/channel.flv?fallback=other.m3u8',
        ),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
      expect(
        classifyIosMediaKitPipSource(
          'https://example.com/live/channel.flv#fallback.m3u8',
        ),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
    });

    test('requires an absolute HTTP or HTTPS URL', () {
      expect(
        classifyIosMediaKitPipSource('file:///tmp/channel.m3u8'),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
      expect(
        classifyIosMediaKitPipSource('channel.m3u8'),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
      expect(
        classifyIosMediaKitPipSource('not a url.m3u8'),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
    });

    test('falls back safely for malformed URLs', () {
      expect(
        classifyIosMediaKitPipSource('https://example.com/live/%zz.flv'),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
      expect(
        classifyIosMediaKitPipSource('https://example.com/live/%zz.M3U8?x=1'),
        IosMediaKitPipSourceRoute.sampleBuffer,
      );
    });
  });
}
