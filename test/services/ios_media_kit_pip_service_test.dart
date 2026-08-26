import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/ios_media_kit_pip_service.dart';

void main() {
  group('IosMediaKitPipService', () {
    late _FakePipTransport transport;
    late IosMediaKitPipService service;

    setUp(() async {
      transport = _FakePipTransport();
      service = IosMediaKitPipService(transport: transport);
      await service.bind(Future<int>.value(42));
    });

    tearDown(() async {
      await service.dispose();
      await transport.dispose();
    });

    test('strictly maps all six states', () async {
      expect(
        IosMediaKitPipState.values,
        const <IosMediaKitPipState>[
          IosMediaKitPipState.unavailable,
          IosMediaKitPipState.inactive,
          IosMediaKitPipState.starting,
          IosMediaKitPipState.active,
          IosMediaKitPipState.stopping,
          IosMediaKitPipState.failed,
        ],
      );

      for (final state in IosMediaKitPipState.values) {
        transport.emit(<String, Object?>{
          'handle': '42',
          'state': state.name,
        });
        await _flushEvents();
        expect(service.state, state);
      }
    });

    test('filters events by handle and ignores malformed states', () async {
      transport.emit(const <String, Object?>{
        'handle': '7',
        'state': 'active',
      });
      transport.emit(const <String, Object?>{
        'handle': '42',
        'state': 'unknown',
      });
      await _flushEvents();

      expect(service.state, IosMediaKitPipState.unavailable);

      transport.emit(const <String, Object?>{
        'handle': '42',
        'state': 'active',
      });
      await _flushEvents();

      expect(service.state, IosMediaKitPipState.active);
    });

    test('prepares and clears the native HLS route with source metadata',
        () async {
      await service.prepareHls(
        'https://example.com/live/channel.m3u8?token=abc',
        const <String, String>{
          'Referer': 'https://example.com/',
          'User-Agent': 'Simple Live',
        },
      );
      await service.clearHls();

      expect(transport.invocations, hasLength(2));
      expect(
        transport.invocations[0].method,
        'VideoOutputManager.PiPPrepareHls',
      );
      expect(transport.invocations[0].arguments, <String, Object?>{
        'handle': '42',
        'url': 'https://example.com/live/channel.m3u8?token=abc',
        'headers': const <String, String>{
          'Referer': 'https://example.com/',
          'User-Agent': 'Simple Live',
        },
      });
      expect(
        transport.invocations[1].method,
        'VideoOutputManager.PiPClearHls',
      );
      expect(
        transport.invocations[1].arguments,
        const <String, Object?>{'handle': '42'},
      );
    });

    test('retries HLS preparation until native VideoOutput exists', () async {
      transport.transientErrors['VideoOutputManager.PiPPrepareHls'] = <Object>[
        PlatformException(code: 'unknown_handle'),
        PlatformException(code: 'unknown_handle'),
      ];

      await service.prepareHls(
        'https://example.com/live/channel.m3u8',
        const <String, String>{'Referer': 'https://example.com/'},
      );

      expect(
        transport.invocations
            .where(
              (invocation) =>
                  invocation.method == 'VideoOutputManager.PiPPrepareHls',
            )
            .length,
        3,
      );
    });

    test('HLS route methods safely no-op after disposal', () async {
      await service.dispose();
      final invocationCount = transport.invocations.length;

      await service.prepareHls(
        'https://example.com/live/channel.m3u8',
        const <String, String>{'X-Test-Header': 'ignored'},
      );
      await service.clearHls();

      expect(transport.invocations, hasLength(invocationCount));
    });

    test('passes a string handle and makes start stop and dispose idempotent',
        () async {
      transport.responses['VideoOutputManager.PiPIsAvailable'] = true;

      expect(await service.isAvailable(), isTrue);
      final start = service.start();
      await _flushEvents();
      transport.emit(const <String, Object?>{
        'handle': '42',
        'state': 'active',
      });
      expect(await start, isTrue);
      expect(await service.start(), isTrue);
      await _flushEvents();

      await service.stop();
      await service.stop();
      await service.dispose();
      await service.dispose();

      expect(
        transport.invocations.map((invocation) => invocation.method),
        <String>[
          'VideoOutputManager.PiPIsAvailable',
          'VideoOutputManager.PiPStart',
          'VideoOutputManager.PiPStop',
        ],
      );
      for (final invocation in transport.invocations) {
        expect(invocation.arguments, const <String, Object?>{'handle': '42'});
      }
      expect(transport.cancelCount, 1);
    });

    test('does not report success before native active arrives', () async {
      transport.responses['VideoOutputManager.PiPIsAvailable'] = true;
      expect(await service.isAvailable(), isTrue);

      final start = service.start(
        activationTimeout: const Duration(milliseconds: 10),
      );

      expect(await start, isFalse);
      expect(service.state, IosMediaKitPipState.failed);

      final retry = service.start(
        activationTimeout: const Duration(milliseconds: 10),
      );
      await _flushEvents();
      transport.emit(const <String, Object?>{
        'handle': '42',
        'state': 'active',
      });
      expect(await retry, isTrue);
    });

    test('returns false when native reports start failure', () async {
      transport.responses['VideoOutputManager.PiPIsAvailable'] = true;
      expect(await service.isAvailable(), isTrue);

      final start = service.start();
      await _flushEvents();
      transport.emit(const <String, Object?>{
        'handle': '42',
        'state': 'failed',
      });

      expect(await start, isFalse);
      expect(service.state, IosMediaKitPipState.failed);
    });

    test('maps a native method error to failed', () async {
      transport.errors['VideoOutputManager.PiPStart'] = PlatformException(
        code: 'pip_not_available',
        message: 'Picture in Picture is not currently available.',
      );

      await expectLater(service.start(), throwsA(isA<PlatformException>()));
      expect(service.state, IosMediaKitPipState.failed);
    });
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _Invocation {
  const _Invocation(this.method, this.arguments);

  final String method;
  final Map<String, Object?> arguments;
}

final class _FakePipTransport extends IosMediaKitPipTransport {
  _FakePipTransport() {
    _events = StreamController<Object?>.broadcast(
      onCancel: () => cancelCount += 1,
    );
  }

  late final StreamController<Object?> _events;
  final List<_Invocation> invocations = <_Invocation>[];
  final Map<String, Object?> responses = <String, Object?>{};
  final Map<String, Object> errors = <String, Object>{};
  final Map<String, List<Object>> transientErrors = <String, List<Object>>{};
  int cancelCount = 0;

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<T?> invokeMethod<T>(
    String method,
    Map<String, Object?> arguments,
  ) async {
    invocations.add(_Invocation(method, arguments));
    final queuedErrors = transientErrors[method];
    if (queuedErrors != null && queuedErrors.isNotEmpty) {
      throw queuedErrors.removeAt(0);
    }
    final error = errors[method];
    if (error != null) {
      throw error;
    }
    return responses[method] as T?;
  }

  void emit(Object? event) => _events.add(event);

  Future<void> dispose() => _events.close();
}
