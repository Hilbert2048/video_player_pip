import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player_pip/video_player_pip.dart';
import 'floating_mini_player.dart';

/// Global PIP manager that takes over the controller only after the page is disposed.
/// Shows a floating mini player on restore.
class PipManager {
  PipManager._() {
    _pipSubscription =
        VideoPlayerPip.instance.onPipModeChanged.listen(_onPipModeChanged);
    _restoreSubscription = VideoPlayerPip.instance.onPipRestoreRequested
        .listen(_onRestoreRequested);
  }

  static final PipManager instance = PipManager._();

  VideoPlayerController? _controller;
  StreamSubscription<bool>? _pipSubscription;
  StreamSubscription<void>? _restoreSubscription;
  bool _isInPip = false;
  OverlayEntry? _overlayEntry;

  /// Navigator key used to access the Overlay
  GlobalKey<NavigatorState>? navigatorKey;

  /// Callback when the mini player is tapped (opens fullscreen player)
  void Function(VideoPlayerController controller)? onTapMiniPlayer;

  bool get isInPip => _isInPip;
  bool get hasController => _controller != null;

  /// Enter PIP mode (only marks the state, does not take over the controller)
  Future<bool> enterPip(
    VideoPlayerController controller, {
    int? width,
    int? height,
  }) async {
    final result = await controller.enterPipMode(width: width, height: height);
    if (result) {
      _isInPip = true;
    }
    return result;
  }

  /// Called on page dispose: hands the controller to PipManager if in PIP mode.
  bool handoff(VideoPlayerController controller) {
    if (_isInPip) {
      // If we already hold a controller (e.g. from previous PIP session),
      // we must dispose it to prevent leaks and audio overlap.
      if (_controller != null && _controller != controller) {
        dismissMiniPlayer(); // Remove old overlay if showing
        _controller!.dispose();
      }
      _controller = controller;
      return true;
    }
    return false;
  }

  /// Take back ownership of the controller
  VideoPlayerController? takeController() {
    final c = _controller;
    _controller = null;
    return c;
  }

  /// Dismiss the floating mini player
  void dismissMiniPlayer() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onPipModeChanged(bool isInPip) {
    _isInPip = isInPip;
    if (!isInPip && _controller != null && _overlayEntry == null) {
      // PIP ended with no mini player overlay, release the controller
      _controller?.dispose();
      _controller = null;
    }
  }

  void _onRestoreRequested(void _) {
    // Page is still alive, no need for a mini player
    if (_controller == null) {
      VideoPlayerPip.notifyRestoreCompleted();
      return;
    }

    _showMiniPlayer();
    VideoPlayerPip.notifyRestoreCompleted();
  }

  void _showMiniPlayer() {
    final overlay = navigatorKey?.currentState?.overlay;
    if (overlay == null || _controller == null) return;

    dismissMiniPlayer();

    _overlayEntry = OverlayEntry(
      builder: (context) => FloatingMiniPlayer(
        controller: _controller!,
        onTap: () {
          final controller = takeController();
          dismissMiniPlayer();
          if (controller != null) {
            onTapMiniPlayer?.call(controller);
          }
        },
        onClose: () {
          dismissMiniPlayer();
          _controller?.dispose();
          _controller = null;
        },
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void dispose() {
    dismissMiniPlayer();
    _pipSubscription?.cancel();
    _restoreSubscription?.cancel();
    _controller?.dispose();
    _controller = null;
  }
}
