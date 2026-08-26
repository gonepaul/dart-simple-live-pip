import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/pip_route.dart';

void main() {
  group('resolvePipRoute', () {
    const cases = <(PipPlatform, PipPlayerBackend, PipRoute)>[
      (
        PipPlatform.android,
        PipPlayerBackend.mpv,
        PipRoute.androidFloating,
      ),
      (
        PipPlatform.android,
        PipPlayerBackend.mdk,
        PipRoute.androidFloating,
      ),
      (PipPlatform.ios, PipPlayerBackend.mpv, PipRoute.iosNative),
      (PipPlatform.ios, PipPlayerBackend.mdk, PipRoute.unsupportedPlayer),
      (
        PipPlatform.desktop,
        PipPlayerBackend.mpv,
        PipRoute.unsupportedPlatform,
      ),
      (
        PipPlatform.desktop,
        PipPlayerBackend.mdk,
        PipRoute.unsupportedPlatform,
      ),
    ];

    for (final (platform, playerBackend, expectedRoute) in cases) {
      test('${platform.name}/${playerBackend.name} -> ${expectedRoute.name}', () {
        expect(
          resolvePipRoute(
            platform: platform,
            playerBackend: playerBackend,
          ),
          expectedRoute,
        );
      });
    }
  });
}
