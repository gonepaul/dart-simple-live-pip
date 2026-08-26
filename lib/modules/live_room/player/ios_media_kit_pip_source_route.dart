enum IosMediaKitPipSourceRoute {
  sampleBuffer,
  hls,
}

IosMediaKitPipSourceRoute classifyIosMediaKitPipSource(String url) {
  if (_hasInvalidPercentEncoding(url)) {
    return IosMediaKitPipSourceRoute.sampleBuffer;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return IosMediaKitPipSourceRoute.sampleBuffer;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return IosMediaKitPipSourceRoute.sampleBuffer;
  }
  return uri.path.toLowerCase().contains('.m3u8')
      ? IosMediaKitPipSourceRoute.hls
      : IosMediaKitPipSourceRoute.sampleBuffer;
}

bool _hasInvalidPercentEncoding(String value) {
  bool isHexDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39 ||
      codeUnit >= 0x41 && codeUnit <= 0x46 ||
      codeUnit >= 0x61 && codeUnit <= 0x66;

  for (var index = 0; index < value.length; index++) {
    if (value.codeUnitAt(index) != 0x25) {
      continue;
    }
    if (index + 2 >= value.length ||
        !isHexDigit(value.codeUnitAt(index + 1)) ||
        !isHexDigit(value.codeUnitAt(index + 2))) {
      return true;
    }
    index += 2;
  }
  return false;
}
