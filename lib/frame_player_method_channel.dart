import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'frame_player_platform_interface.dart';

/// An implementation of [FramePlayerPlatform] that uses method channels.
class MethodChannelFramePlayer extends FramePlayerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('frame_player');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
