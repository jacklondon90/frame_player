import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  VideoPlayerWidget({required this.videoUrl});

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  MethodChannel? platform;
  double _currentSliderValue = 0.0;
  double _bufferSliderValue = 0.0;
  String _elapsedTime = "00:00";
  double _videoDuration = 1.0;
  String _totalDuration = "00:00";
  List<String> _subtitles = [];
  List<String> _audioOptions = [];
  bool isLandscape = false;
  bool pause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    platform?.setMethodCallHandler(_handleMethodCall);
    _initializePlayer(widget.videoUrl);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    platform?.invokeMethod('disposePlayer');

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.leanBack);
    } else if (orientation == Orientation.portrait) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.didChangeMetrics();
  }

  void _toggleOrientation() {
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
    }
    setState(() {
      isLandscape = !isLandscape;
    });
  }

  Future<void> _initializePlayer(String url) async {
    if (platform == null) return;

    try {
      await platform!.invokeMethod('initializePlayer', {'url': url});
      print("Player initialized with URL: $url");
    } on PlatformException catch (e) {
      print("Failed to initialize player: '${e.message}'.");
    }
  }

  Future<List<Map<String, String>>> parseM3U8(String url) async {
    final response = await http.get(Uri.parse(url));
    final lines = response.body.split('\n');

    List<Map<String, String>> qualityOptions = [];

    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
        final resolutionMatch =
            RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(lines[i]);
        final resolution = resolutionMatch?.group(1) ?? 'Unknown';
        final uri = lines[i + 1].trim(); // The URI should be the next line
        qualityOptions.add({'resolution': resolution, 'uri': uri});
      }
    }

    return qualityOptions;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'updateSlider':
        double value;
        Platform.isIOS
            ? value = double.parse(call.arguments)
            : value = call.arguments as double;
        setState(() {
          _currentSliderValue = value;
          _elapsedTime = FormatDuration().formatDuration(
              Duration(seconds: (value * _videoDuration).toInt()));
        });
        break;
      case 'updateBuffer':
        if (Platform.isAndroid) {
          double bufferValue = call.arguments as double;
          setState(() {
            _bufferSliderValue = bufferValue / 100.0;
          });
        } else {
          double bufferValue = double.parse(call.arguments);
          setState(() {
            _bufferSliderValue = bufferValue / _videoDuration;
          });
        }
        break;
      case 'updateDuration':
        double duration;
        Platform.isIOS
            ? duration = double.parse(call.arguments)
            : duration = call.arguments as double;

        setState(() {
          _videoDuration = duration;
          _totalDuration = FormatDuration()
              .formatDuration(Duration(seconds: duration.toInt()));
        });
        break;
      case 'updateAudio':
        List<dynamic> audioOptions = call.arguments;

        setState(() {
          _audioOptions = audioOptions.cast<String>();
        });
        break;
      case 'updateSubtitles':
        List<dynamic> subtitles = call.arguments;

        setState(() {
          _subtitles = subtitles.cast<String>();
        });
        break;
      default:
        print('Unknown method ${call.method}');
    }
  }

  Future<void> _changeAudio(String language) async {
    if (platform == null) return;

    try {
      await platform!.invokeMethod('changeAudio', {'language': language});
      print("Subtitle changed to: $language");
    } on PlatformException catch (e) {
      print("Failed to change subtitle: '${e.message}'.");
    }
  }

  Future<void> _changeVideoQuality(String url) async {
    if (platform == null) return;

    try {
      await platform!.invokeMethod('changeVideoQuality', {'url': url});
      print("Video quality changed to: $url");
    } on PlatformException catch (e) {
      print("Failed to change video quality: '${e.message}'.");
    }
  }

  void _showVideoQualityOptions(String m3u8Url) async {
    List<Map<String, String>> qualityOptions = await parseM3U8(m3u8Url);

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return ListView(
          children: qualityOptions.map((option) {
            return ListTile(
              title: Text(option['resolution']!),
              onTap: () {
                _changeVideoQuality(option['uri']!);
                debugPrint(option['uri']!);
                Navigator.pop(context);
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _showSubtitleOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return ListView(
          children: _subtitles.map((subtitle) {
            return ListTile(
              title: Text(subtitle),
              onTap: () {
                _changeSubtitle(subtitle);
                Navigator.pop(context);
              },
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _changeSubtitle(String language) async {
    if (platform == null) return;

    try {
      await platform!.invokeMethod('changeSubtitle', {'language': language});
      print("Subtitle changed to: $language");
    } on PlatformException catch (e) {
      print("Failed to change subtitle: '${e.message}'.");
    }
  }

  void _showPlaybackSpeedOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return ListView(
          children: [
            _buildSpeedOption('0.25x', 0.25),
            _buildSpeedOption('0.5x', 0.5),
            _buildSpeedOption('0.75x', 0.75),
            _buildSpeedOption('Normal', 1.0),
            _buildSpeedOption('1.25x', 1.25),
            _buildSpeedOption('1.5x', 1.5),
            _buildSpeedOption('1.75x', 1.75),
          ],
        );
      },
    );
  }

  ListTile _buildSpeedOption(String label, double speed) {
    return ListTile(
      title: Text(label),
      onTap: () {
        _setPlaybackSpeed(speed);
        Navigator.pop(context);
      },
    );
  }

  ListTile _buildQualityOption(String quality, String url) {
    return ListTile(
      title: Text(quality),
      onTap: () {
        _changeVideoQuality(url);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    if (platform == null) return;

    try {
      await platform!.invokeMethod('setPlaybackSpeed', {'speed': speed});
      print("Playback speed set to: $speed");
    } on PlatformException catch (e) {
      print("Failed to set playback speed: '${e.message}'.");
    }
  }

  void _showAudioOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return ListView(
          children: _audioOptions.map((subtitle) {
            return ListTile(
              title: Text(subtitle),
              onTap: () {
                _changeAudio(subtitle);
                Navigator.pop(context);
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('test'),
        actions: [
          IconButton(
            icon: Icon(isLandscape
                ? Icons.screen_lock_rotation
                : Icons.screen_rotation),
            onPressed: _toggleOrientation,
          ),
        ],
      ),
      body: OrientationBuilder(builder: (context, orientation) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: orientation == Orientation.portrait
                  ? 300
                  : MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: Platform.isIOS
                  ? UiKitView(
                      viewType: 'SwiftPlayer',
                      onPlatformViewCreated: _onPlatformViewCreated,
                    )
                  : AndroidView(
                      viewType: 'plugins.frame/flutter_player',
                      onPlatformViewCreated: _onPlatformViewCreated,
                    ),
            ),
            _buildControlButtons(),
            _buildSlider(context, orientation),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: _showAudioOptions,
                    child: const Text('Audio'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: () {
                      _showVideoQualityOptions(
                          'https://files.etibor.uz/media/backup_beekeeper/master.m3u8');
                    },
                    child: const Text('Quality'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: _showSubtitleOptions,
                    child: const Text('Subtitles'),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: _showPlaybackSpeedOptions,
                child: const Text('Speed'),
              ),
            ),
          ],
        );
      }),
    );
  }

  Row _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
            onPressed: () {
              Platform.isIOS ? _sendData('10-') : _sendDataAndroid('10-');
            },
            icon: const Icon(
              Icons.timer_10_rounded,
              color: Colors.white,
              size: 40,
            )),
        IconButton(
            onPressed: () {
              if (!pause) {
                Platform.isIOS ? _sendData('pause') : _sendDataAndroid('pause');

                setState(() {
                  pause = true;
                });
              } else {
                Platform.isIOS ? _sendData('play') : _sendDataAndroid('play');

                setState(() {
                  pause = false;
                });
              }
            },
            icon: Icon(
              pause ? Icons.play_circle : Icons.pause_circle,
              color: Colors.white,
              size: 40,
            )),
        IconButton(
            onPressed: () {
              Platform.isIOS ? _sendData('10+') : _sendDataAndroid('10+');
            },
            icon: const Icon(
              Icons.timer_10_rounded,
              color: Colors.white,
              size: 40,
            )),
      ],
    );
  }

  Padding _buildSlider(BuildContext context, Orientation orientation) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).size.height / 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(_elapsedTime),
          Stack(
            children: [
              Slider(
                value: _bufferSliderValue,
                max: 1,
                divisions: 100,
                label: 'Buffer',
                onChanged: null,
              ),
              Slider(
                value: _currentSliderValue,
                max: 1,
                activeColor: Colors.red,
                divisions: 100,
                label: _elapsedTime,
                onChanged: (double value) {
                  setState(() {
                    _currentSliderValue = value;
                    _elapsedTime = FormatDuration().formatDuration(
                        Duration(seconds: (value * _videoDuration).toInt()));
                  });
                  _sendIsSliderBeingDragged(true);
                },
                onChangeEnd: (double value) {
                  _sendSeekValue(value);
                  print('Flutter slider: $value');
                  _sendIsSliderBeingDragged(false);
                },
              ),
            ],
          ),
          Text(_totalDuration),
        ],
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    platform = MethodChannel('fluff_view_channel_$id');
    platform?.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _sendData(String type) async {
    if (platform == null) return;

    try {
      final String result =
          await platform!.invokeMethod('sendData', {'data': type});
      print("Result from Swift: $result");
    } on PlatformException catch (e) {
      print("Failed to send data: '${e.message}'.");
    }
  }

  Future<void> _sendSeekValue(double value) async {
    if (platform == null) return;

    try {
      await platform!.invokeMethod('seekTo', {'value': value});
      print("SUCCESS to send seek value: '$value'.");
    } on PlatformException catch (e) {
      print("Failed to send seek value: '${e.message}'.");
    }
  }

  Future<void> _sendIsSliderBeingDragged(bool isDragging) async {
    if (platform == null) return;

    try {
      await platform!
          .invokeMethod('isSliderBeingDragged', {'isDragging': isDragging});
    } on PlatformException catch (e) {
      print("Failed to send slider dragging state: '${e.message}'.");
    }
  }

  //Android
  Future<void> _sendDataAndroid(String type) async {
    if (platform == null) return;

    try {
      final String result = await platform!.invokeMethod(type);

      print("Result from Kotlin: $result");
    } on PlatformException catch (e) {
      print("Failed to send data: '${e.message}'.");
    }
  }

//Android
}

class FormatDuration {
  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
