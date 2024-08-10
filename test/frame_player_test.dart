import 'package:flutter_test/flutter_test.dart';
import 'package:frame_player/frame_player.dart';
import 'package:frame_player/frame_player_platform_interface.dart';
import 'package:frame_player/frame_player_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFramePlayerPlatform
    with MockPlatformInterfaceMixin
    implements FramePlayerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FramePlayerPlatform initialPlatform = FramePlayerPlatform.instance;

  test('$MethodChannelFramePlayer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFramePlayer>());
  });

  test('getPlatformVersion', () async {
    FramePlayer framePlayerPlugin = FramePlayer();
    MockFramePlayerPlatform fakePlatform = MockFramePlayerPlatform();
    FramePlayerPlatform.instance = fakePlatform;

    expect(await framePlayerPlugin.getPlatformVersion(), '42');
  });
}
