import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/auto_pip_policy.dart';

void main() {
  group('AutoPipBackgroundPolicy', () {
    test('requires setting, iOS, a valid live, and native capability', () {
      const eligible = AutoPipEligibility(
        settingEnabled: true,
        isIos: true,
        hasValidLive: true,
        supportsNativePip: true,
      );

      expect(eligible.canRequest, isTrue);
      expect(eligible.copyWith(settingEnabled: false).canRequest, isFalse);
      expect(eligible.copyWith(isIos: false).canRequest, isFalse);
      expect(eligible.copyWith(hasValidLive: false).canRequest, isFalse);
      expect(eligible.copyWith(supportsNativePip: false).canRequest, isFalse);
    });

    test('coalesces inactive and paused until resumed', () {
      final policy = AutoPipBackgroundPolicy();
      const eligible = AutoPipEligibility(
        settingEnabled: true,
        isIos: true,
        hasValidLive: true,
        supportsNativePip: true,
      );

      final inactiveRequest = policy.tryLatchRequest(eligible);
      final pausedRequest = policy.tryLatchRequest(eligible);

      expect(inactiveRequest, isTrue);
      expect(pausedRequest, isFalse);

      policy.resetOnResumed();

      expect(policy.tryLatchRequest(eligible), isTrue);
    });

    test('does not latch an ineligible background event', () {
      final policy = AutoPipBackgroundPolicy();
      const ineligible = AutoPipEligibility(
        settingEnabled: false,
        isIos: true,
        hasValidLive: true,
        supportsNativePip: true,
      );
      const eligible = AutoPipEligibility(
        settingEnabled: true,
        isIos: true,
        hasValidLive: true,
        supportsNativePip: true,
      );

      expect(policy.tryLatchRequest(ineligible), isFalse);
      expect(policy.tryLatchRequest(eligible), isTrue);
    });
  });
}
