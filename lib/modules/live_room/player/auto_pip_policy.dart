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

final class AutoPipRequest {
  const AutoPipRequest(this.generation);

  final int generation;
}

final class AutoPipBackgroundPolicy {
  int _generation = 0;
  bool _requestInFlight = false;
  bool _requestCompleted = false;
  bool _retryQueued = false;

  AutoPipRequest? tryBeginRequest(AutoPipEligibility eligibility) {
    if (!eligibility.canRequest || _requestCompleted) {
      return null;
    }
    if (_requestInFlight) {
      _retryQueued = true;
      return null;
    }
    _requestInFlight = true;
    return AutoPipRequest(_generation);
  }

  bool isCurrent(AutoPipRequest request) =>
      request.generation == _generation &&
      _requestInFlight &&
      !_requestCompleted;

  /// Completes [request] and returns whether one coalesced background event
  /// requested an immediate retry after a failed readiness/start attempt.
  bool completeRequest(
    AutoPipRequest request, {
    required bool succeeded,
  }) {
    if (request.generation != _generation || !_requestInFlight) {
      return false;
    }
    if (succeeded) {
      _requestInFlight = false;
      _requestCompleted = true;
      _retryQueued = false;
      return false;
    }
    if (_retryQueued) {
      _retryQueued = false;
      return true;
    }
    _requestInFlight = false;
    return false;
  }

  void resetOnResumed() {
    _generation += 1;
    _requestInFlight = false;
    _requestCompleted = false;
    _retryQueued = false;
  }
}
