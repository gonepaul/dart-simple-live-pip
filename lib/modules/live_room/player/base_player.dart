import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:simple_live_app/modules/live_room/player/player_states.dart';
import 'package:simple_live_app/services/ios_media_kit_pip_service.dart';

export 'package:simple_live_app/modules/live_room/player/player_states.dart';

abstract class BasePlayer {
  Stream<PlayerState> get stateStream;

  bool get supportsNativePip => false;

  Stream<IosMediaKitPipState> get pipStateStream =>
      const Stream<IosMediaKitPipState>.empty();

  PlayerState lastState = const PlayerState();

  Future<void> init();

  Widget? videoWidget(
    Key key,
    double? aspectRatio,
    BoxFit fit,
  );

  Future<void> dispose();

  Future<void> loadVideo(
    String url, {
    Map<String, String>? headers,
    bool play = true,
  });

  Future<void> play();

  Future<void> setVolume(double volume);

  Future<void> pause();

  Future<void> stop();

  Future<void> playOrPause();

  Future<bool> isPipAvailable() async => false;

  Future<bool> startPip() async => false;

  Future<void> stopPip() async {}

  Future<Uint8List?> snapshot();
}
