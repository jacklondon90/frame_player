import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'frame_player_method_channel.dart';

abstract class FramePlayerPlatform extends PlatformInterface {
  /// Constructs a FramePlayerPlatform.
  FramePlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FramePlayerPlatform _instance = MethodChannelFramePlayer();

  /// The default instance of [FramePlayerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFramePlayer].
  static FramePlayerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FramePlayerPlatform] when
  /// they register themselves.
  static set instance(FramePlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
