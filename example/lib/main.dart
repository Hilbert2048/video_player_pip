import 'package:flutter/material.dart';
import 'package:video_player_pip/video_player_pip.dart';
import 'pip_manager.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure PipManager
  PipManager.instance.navigatorKey = _navigatorKey;
  PipManager.instance.onTapMiniPlayer = (controller) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(controller: controller),
      ),
    );
  };

  runApp(MaterialApp(
    navigatorKey: _navigatorKey,
    home: const HomeScreen(),
  ));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                'https://i0.hdslb.com/bfs/archive/2fb0f8a4c71fa29b05051e628ff397d949bd8df3.jpg@375w_210h.webp',
                width: 300,
                height: 300,
              ),
              const Text('Big Buck Bunny'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PlayerScreen()));
                },
                child: const Text('Play'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, this.controller});

  /// Externally provided controller (used when restoring from mini player)
  final VideoPlayerController? controller;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _controller;
  String _debugStatus = "Starting initialization";
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _videoInitialized = true;
      _debugStatus = "Restored from PiP";
    } else {
      _createNewController();
    }
  }

  void _createNewController() async {
    try {
      setState(() {
        _debugStatus = "Creating controller";
      });

      _controller = VideoPlayerController.networkUrl(
        videoPlayerOptions: ExtendedVideoPlayerOptions(
            allowBackgroundPlayback: true,
            mixWithOthers: true,
            viewType: VideoViewType.platformView),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        },
        Uri.parse(
            'https://cn-gdjm-cm-01-03.bilivideo.com/upgcxcode/07/21/36010722107/36010722107-1-16.mp4?e=ig8euxZM2rNcNbRVhwdVhwdlhWdVhwdVhoNvNC8BqJIzNbfq9rVEuxTEnE8L5F6VnEsSTx0vkX8fqJeYTj_lta53NCM=&deadline=1770986363&uipk=5&platform=html5&mid=0&oi=2028708792&nbs=1&os=bcache&trid=000054bec746b8fe480ba3a1a138201980eh&gen=playurlv3&og=hw&upsig=1292d8d944680b68e211d496aac686b7&uparams=e,deadline,uipk,platform,mid,oi,nbs,os,trid,gen,og&cdnid=88503&bvc=vod&nettype=0&bw=228023&lrs=82&build=0&dl=0&f=h_0_0&agrr=1&buvid=&orderid=0,1'),
      );

      await _controller.initialize();
      await _controller.play();
      print('isPipSupported: ${await _controller.isPipSupported()}');

      setState(() {
        _debugStatus = "Playing";
        _videoInitialized = true;
      });
    } catch (e) {
      print(e);
      setState(() {
        _debugStatus = "Error: $e";
      });
    }
  }

  @override
  void dispose() {
    // Hand off to PipManager if in PIP mode, otherwise dispose normally
    if (!PipManager.instance.handoff(_controller)) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_debugStatus),
      ),
      body: Stack(
        children: [
          Center(
            child: _videoInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(_debugStatus),
                    ],
                  ),
          ),
          if (_videoInitialized)
            Center(
              child: IconButton(
                onPressed: () {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                  setState(() {});
                },
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _videoInitialized
          ? FloatingActionButton(
              onPressed: () {
                final aspectRatio = _controller.value.aspectRatio;
                const width = 300;
                final height = width / aspectRatio;
                PipManager.instance.enterPip(
                  _controller,
                  width: width,
                  height: height.toInt(),
                );
              },
              child: const Icon(Icons.picture_in_picture),
            )
          : null,
    );
  }
}
