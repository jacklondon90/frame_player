
import 'frame_player_platform_interface.dart';

class FramePlayer {
  Future<String?> getPlatformVersion() {
    return FramePlayerPlatform.instance.getPlatformVersion();
  }
}
