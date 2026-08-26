final class AutoPipEligibility {
  const AutoPipEligibility({
    required this.settingEnabled,
    required this.isIos,
    required this.hasValidLive,
    required this.supportsNativePip,
  });

  final bool settingEnabled;
  final bool isIos;
  final bool hasValidLive;
  final bool supportsNativePip;

  bool get canRequest =>
      settingEnabled && isIos && hasValidLive && supportsNativePip;

  AutoPipEligibility copyWith({
    bool? settingEnabled,
    bool? isIos,
    bool? hasValidLive,
    bool? supportsNativePip,
  }) {
    return AutoPipEligibility(
      settingEnabled: settingEnabled ?? this.settingEnabled,
      isIos: isIos ?? this.isIos,
      hasValidLive: hasValidLive ?? this.hasValidLive,
      supportsNativePip: supportsNativePip ?? this.supportsNativePip,
    );
  }
}

final class AutoPipBackgroundPolicy {
  bool _requestLatched = false;

  bool tryLatchRequest(AutoPipEligibility eligibility) {
    if (_requestLatched || !eligibility.canRequest) {
      return false;
    }
    _requestLatched = true;
    return true;
  }

  void resetOnResumed() {
    _requestLatched = false;
  }
}
