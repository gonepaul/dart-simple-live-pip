import 'dart:io';
import 'package:flutter/services.dart';
import 'package:simple_live_app/app/log.dart';

/// iOS native Picture-in-Picture service using AVPlayer.
/// Only supports HLS (.m3u8) streams.
class IosPipService {
  static final IosPipService instance = IosPipService._();
  IosPipService._();

  static const _channel = MethodChannel('simple_live/pip');
  bool _initialized = false;

  /// Whether the current stream URL is HLS and eligible for iOS PiP.
  static bool isHlsUrl(String url) {
    if (!Platform.isIOS) return false;
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        return false;
      }
      final path = uri.path.toLowerCase();
      return path.contains('.m3u8');
    } catch (_) {
      return false;
    }
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Function(String status)? onStatusChanged;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onPiPStatusChanged') {
      final status = call.arguments as String;
      SimpleLiveLogger().w('[IosPiP] Status: $status');
      onStatusChanged?.call(status);
    }
  }

  /// Check if PiP is available on this device.
  Future<bool> isPipAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isPipAvailable');
      return result ?? false;
    } catch (e) {
      SimpleLiveLogger().e('[IosPiP] isPipAvailable error: $e');
      return false;
    }
  }

  /// Start PiP with the given HLS URL and optional headers.
  Future<bool> startPip(String url, {Map<String, String>? headers}) async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod('startPip', {
        'url': url,
        if (headers != null) 'headers': headers,
      });
      return result == true;
    } catch (e) {
      SimpleLiveLogger().e('[IosPiP] startPip error: $e');
      return false;
    }
  }

  /// Stop any active PiP session.
  Future<void> stopPip() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('stopPip');
    } catch (e) {
      SimpleLiveLogger().e('[IosPiP] stopPip error: $e');
    }
  }

  /// Check if PiP is currently active.
  Future<bool> isPipActive() async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isPipActive');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
