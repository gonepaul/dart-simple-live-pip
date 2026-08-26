import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/auto_pip_policy.dart';

void main() {
  const eligible = AutoPipEligibility(
    settingEnabled: true,
    isIos: true,
    hasValidLive: true,
    supportsNativePip: true,
  );

  group('AutoPipBackgroundPolicy', () {
    test('requires setting, iOS, a valid live, and native capability', () {
      expect(eligible.canRequest, isTrue);
      expect(eligible.copyWith(settingEnabled: false).canRequest, isFalse);
      expect(eligible.copyWith(isIos: false).canRequest, isFalse);
      expect(eligible.copyWith(hasValidLive: false).canRequest, isFalse);
      expect(eligible.copyWith(supportsNativePip: false).canRequest, isFalse);
    });

    test('queues paused retry while inactive readiness check is in flight', () {
      final policy = AutoPipBackgroundPolicy();
      final request = policy.tryBeginRequest(eligible);

      expect(request, isNotNull);
      expect(policy.tryBeginRequest(eligible), isNull);
      expect(
        policy.completeRequest(request!, succeeded: false),
        isTrue,
      );
      expect(
        policy.completeRequest(request, succeeded: true),
        isFalse,
      );
      expect(policy.tryBeginRequest(eligible), isNull);
    });

    test('failed readiness without queued event releases a later request', () {
      final policy = AutoPipBackgroundPolicy();
      final request = policy.tryBeginRequest(eligible)!;

      expect(policy.completeRequest(request, succeeded: false), isFalse);
      expect(policy.tryBeginRequest(eligible), isNotNull);
    });

    test('resumed or room change invalidates stale asynchronous completion', () {
      final policy = AutoPipBackgroundPolicy();
      final staleRequest = policy.tryBeginRequest(eligible)!;
      expect(policy.isCurrent(staleRequest), isTrue);

      policy.resetOnResumed();

      expect(policy.isCurrent(staleRequest), isFalse);
      expect(
        policy.completeRequest(staleRequest, succeeded: true),
        isFalse,
      );
      expect(policy.tryBeginRequest(eligible), isNotNull);
    });

    test('does not latch an ineligible background event', () {
      final policy = AutoPipBackgroundPolicy();
      const ineligible = AutoPipEligibility(
        settingEnabled: false,
        isIos: true,
        hasValidLive: true,
        supportsNativePip: true,
      );

      expect(policy.tryBeginRequest(ineligible), isNull);
      expect(policy.tryBeginRequest(eligible), isNotNull);
    });
  });
}
