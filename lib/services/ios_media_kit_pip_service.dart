import 'dart:async';

import 'package:flutter/services.dart';

enum IosMediaKitPipState {
  unavailable,
  inactive,
  starting,
  active,
  stopping,
  failed,
}

abstract class IosMediaKitPipTransport {
  const IosMediaKitPipTransport();

  Stream<Object?> get events;

  Future<T?> invokeMethod<T>(
    String method,
    Map<String, Object?> arguments,
  );

  Future<void> prepareHls({
    required String handle,
    required String url,
    required Map<String, String> headers,
  }) {
    return invokeMethod<void>(
      'VideoOutputManager.PiPPrepareHls',
      <String, Object?>{
        'handle': handle,
        'url': url,
        'headers': headers,
      },
    );
  }

  Future<void> clearHls({required String handle}) {
    return invokeMethod<void>(
      'VideoOutputManager.PiPClearHls',
      <String, Object?>{'handle': handle},
    );
  }
}

final class MethodChannelIosMediaKitPipTransport
    extends IosMediaKitPipTransport {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.alexmercerind/media_kit_video/pip_events',
  );

  const MethodChannelIosMediaKitPipTransport();

  @override
  Stream<Object?> get events => _eventChannel.receiveBroadcastStream();

  @override
  Future<T?> invokeMethod<T>(
    String method,
    Map<String, Object?> arguments,
  ) {
    return _methodChannel.invokeMethod<T>(method, arguments);
  }
}

final class IosMediaKitPipService {
  IosMediaKitPipService({IosMediaKitPipTransport? transport})
      : _transport = transport ?? const MethodChannelIosMediaKitPipTransport();

  final IosMediaKitPipTransport _transport;
  final StreamController<IosMediaKitPipState> _stateController =
      StreamController<IosMediaKitPipState>.broadcast(sync: true);

  StreamSubscription<Object?>? _eventSubscription;
  String? _handle;
  IosMediaKitPipState _state = IosMediaKitPipState.unavailable;
  bool _disposed = false;

  IosMediaKitPipState get state => _state;

  Stream<IosMediaKitPipState> get states => _stateController.stream;

  Stream<IosMediaKitPipState> get stateStream => states;

  Future<void> prepareHls(
    String url,
    Map<String, String>? headers,
  ) async {
    if (_disposed) {
      return;
    }

    final copiedHeaders = Map<String, String>.from(
      headers ?? const <String, String>{},
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await _transport.prepareHls(
          handle: _requiredHandle,
          url: url,
          headers: copiedHeaders,
        );
        return;
      } on PlatformException catch (error) {
        if (error.code != 'unknown_handle' || attempt == 9) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> clearHls() async {
    if (_disposed || _handle == null) {
      return;
    }

    await _transport.clearHls(handle: _requiredHandle);
  }

  Future<void> bind(Future<int> handle) async {
    if (_disposed) {
      return;
    }

    final resolvedHandle = (await handle).toString();
    if (_disposed || _handle == resolvedHandle && _eventSubscription != null) {
      return;
    }

    await _eventSubscription?.cancel();
    _handle = resolvedHandle;
    _updateState(IosMediaKitPipState.unavailable);
    _eventSubscription = _transport.events.listen(
      _handleEvent,
      onError: _handleEventError,
    );
  }

  Future<bool> isAvailable() async {
    if (_disposed) {
      return false;
    }

    try {
      final available =
          await _transport.invokeMethod<bool>(
            'VideoOutputManager.PiPIsAvailable',
            _handleArguments,
          ) ??
          false;
      _updateState(
        available
            ? IosMediaKitPipState.inactive
            : IosMediaKitPipState.unavailable,
      );
      return available;
    } catch (error) {
      _updateState(IosMediaKitPipState.failed);
      rethrow;
    }
  }

  Future<bool> start({
    Duration activationTimeout = const Duration(seconds: 3),
  }) async {
    if (_disposed) {
      return false;
    }
    if (_state == IosMediaKitPipState.active) {
      return true;
    }
    if (_state == IosMediaKitPipState.starting ||
        _state == IosMediaKitPipState.stopping) {
      return false;
    }

    _updateState(IosMediaKitPipState.starting);
    final activation = states
        .firstWhere(
          (state) =>
              state == IosMediaKitPipState.active ||
              state == IosMediaKitPipState.failed ||
              state == IosMediaKitPipState.inactive,
        )
        .timeout(activationTimeout, onTimeout: () => _state);
    try {
      await _transport.invokeMethod<void>(
        'VideoOutputManager.PiPStart',
        _handleArguments,
      );
      final result = await activation;
      if (result != IosMediaKitPipState.active &&
          _state == IosMediaKitPipState.starting) {
        _updateState(IosMediaKitPipState.failed);
      }
      return result == IosMediaKitPipState.active;
    } catch (error) {
      _updateState(IosMediaKitPipState.failed);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_disposed ||
        _state != IosMediaKitPipState.starting &&
            _state != IosMediaKitPipState.active) {
      return;
    }

    _updateState(IosMediaKitPipState.stopping);
    try {
      await _transport.invokeMethod<void>(
        'VideoOutputManager.PiPStop',
        _handleArguments,
      );
    } catch (error) {
      _updateState(IosMediaKitPipState.failed);
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    Object? nativeError;
    StackTrace? nativeStackTrace;
    if (_state == IosMediaKitPipState.starting ||
        _state == IosMediaKitPipState.active) {
      _updateState(IosMediaKitPipState.stopping);
      try {
        await _transport.invokeMethod<void>(
          'VideoOutputManager.PiPStop',
          _handleArguments,
        );
      } catch (error, stackTrace) {
        nativeError = error;
        nativeStackTrace = stackTrace;
        _updateState(IosMediaKitPipState.failed);
      }
    }

    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _handle = null;
    await _stateController.close();

    if (nativeError != null) {
      Error.throwWithStackTrace(nativeError, nativeStackTrace!);
    }
  }

  Map<String, Object?> get _handleArguments {
    return <String, Object?>{'handle': _requiredHandle};
  }

  String get _requiredHandle {
    final handle = _handle;
    if (handle == null) {
      throw StateError('bind must complete before invoking PiP methods.');
    }
    return handle;
  }

  void _handleEvent(Object? event) {
    if (_disposed || event is! Map<Object?, Object?>) {
      return;
    }
    if (event['handle'] != _handle) {
      return;
    }

    final state = switch (event['state']) {
      'unavailable' => IosMediaKitPipState.unavailable,
      'inactive' => IosMediaKitPipState.inactive,
      'starting' => IosMediaKitPipState.starting,
      'active' => IosMediaKitPipState.active,
      'stopping' => IosMediaKitPipState.stopping,
      'failed' => IosMediaKitPipState.failed,
      _ => null,
    };
    if (state != null) {
      _updateState(state);
    }
  }

  void _handleEventError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _updateState(IosMediaKitPipState.failed);
    }
  }

  void _updateState(IosMediaKitPipState state) {
    if (_state == state) {
      return;
    }
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
