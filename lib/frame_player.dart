import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:frame_player/video_player.dart';

import 'frame_player_platform_interface.dart';

/*class FramePlayer {
  Future<String?> getPlatformVersion() {
    return FramePlayerPlatform.instance.getPlatformVersion();
  }
}*/

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Video Player',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Video Player'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return VideoPlayerWidget();
  }
}
