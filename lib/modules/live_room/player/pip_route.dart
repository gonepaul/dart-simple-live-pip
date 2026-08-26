enum PipPlatform { android, ios, desktop }

enum PipPlayerBackend { mpv, mdk }

enum PipRoute {
  androidFloating,
  iosNative,
  unsupportedPlayer,
  unsupportedPlatform,
}

PipRoute resolvePipRoute({
  required PipPlatform platform,
  required PipPlayerBackend playerBackend,
}) {
  return switch ((platform, playerBackend)) {
    (PipPlatform.android, _) => PipRoute.androidFloating,
    (PipPlatform.ios, PipPlayerBackend.mpv) => PipRoute.iosNative,
    (PipPlatform.ios, PipPlayerBackend.mdk) => PipRoute.unsupportedPlayer,
    (PipPlatform.desktop, _) => PipRoute.unsupportedPlatform,
  };
}
