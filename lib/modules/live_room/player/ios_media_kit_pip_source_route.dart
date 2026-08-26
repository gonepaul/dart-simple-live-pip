enum IosMediaKitPipSourceRoute {
  sampleBuffer,
  hls,
}

IosMediaKitPipSourceRoute classifyIosMediaKitPipSource(String url) {
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
