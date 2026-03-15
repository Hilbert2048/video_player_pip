import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'pip_state.dart';
import 'video_player_pip_platform_interface.dart';
export 'video_player_pip.dart';
export 'video_player_pip_platform_interface.dart' show VideoPlayerPipPlatform;

// Export the PiP-enabled VideoPlayerController that supports view type selection
export 'package:video_player/video_player.dart';
export 'src/extensions.dart';

/// A Flutter plugin that adds Picture-in-Picture (PiP) functionality to the video_player package.
///
/// This plugin provides methods to enter and exit PiP mode, check if PiP is supported
/// on the current device, and monitor PiP state changes.
class VideoPlayerPip {
  static const MethodChannel _channel = MethodChannel('video_player_pip');

  static final VideoPlayerPipPlatform _platform = VideoPlayerPipPlatform.instance;

  /// Checks if the device supports PiP mode
  ///
  /// Returns `true` if PiP is supported, otherwise `false`.
  ///
  /// For Android, this requires API level 26 (Android 8.0) or higher.
  /// For iOS, this requires iOS 14.0 or higher.
  static Future<bool> isPipSupported() {
    return _platform.isPipSupported();
  }

  /// Pre-initializes the PiP controller for automatic entry when the app
  /// is backgrounded. Call this when video starts playing.
  ///
  /// On iOS 14.2+, this sets `canStartPictureInPictureAutomaticallyFromInline`
  /// to `true`, allowing the system to trigger PiP automatically.
  static Future<bool> enableAutoPip(VideoPlayerController controller) {
    if (controller.textureId == VideoPlayerController.kUninitializedTextureId) {
      debugPrint('VideoPlayerPip: Cannot enable auto PiP with uninitialized controller');
      return Future.value(false);
    }
    return _platform.enableAutoPip(controller.textureId);
  }

  /// Cleans up the pre-initialized PiP controller.
  ///
  /// Call this when the video player is disposed to release native resources.
  /// If [controller] is provided, only that specific player's PiP controller is disabled.
  static Future<bool> disableAutoPip([VideoPlayerController? controller]) {
    if (controller != null && controller.textureId != VideoPlayerController.kUninitializedTextureId) {
      return _platform.disableAutoPip(controller.textureId);
    }
    return _platform.disableAutoPip();
  }

  /// Enters Picture-in-Picture mode for the given video player controller.
  ///
  /// Returns a [Future] that completes with `true` if PiP mode was entered successfully,
  /// or `false` otherwise.
  ///
  /// Optional parameters:
  /// - [width]: Desired width of the PiP window (in pixels)
  /// - [height]: Desired height of the PiP window (in pixels)
  ///
  /// Note: The controller must be initialized and should preferably be using
  /// [VideoViewType.platformView] for PiP to work correctly.
  ///
  /// Example:
  /// ```dart
  /// final controller = VideoPlayerController.network(
  ///   'https://example.com/video.mp4',
  ///   videoViewType: VideoViewType.platformView,
  /// );
  /// await controller.initialize();
  /// await VideoPlayerPip.enterPipMode(controller, width: 300, height: 200);
  /// ```
  static Future<bool> enterPipMode(VideoPlayerController controller, {int? width, int? height}) {
    if (controller.textureId == VideoPlayerController.kUninitializedTextureId) {
      debugPrint('VideoPlayerPip: Cannot enter PiP mode with uninitialized controller');
      return Future.value(false);
    }

    // iOS implementation uses native PiP
    debugPrint('VideoPlayerPip: enterPipMode called for textureId: ${controller.textureId}');
    return _platform.enterPipMode(controller.textureId, width: width, height: height);
  }

  /// Exits Picture-in-Picture mode if currently active.
  ///
  /// Returns `true` if PiP mode was exited successfully, or `false` otherwise.
  static Future<bool> exitPipMode() {
    return _platform.exitPipMode();
  }

  /// Checks if the app is currently in PiP mode.
  ///
  /// Returns `true` if in PiP mode, or `false` otherwise.
  static Future<bool> isInPipMode() {
    return _platform.isInPipMode();
  }

  /// Stream of PiP mode state changes.
  ///
  /// You can listen to this stream to be notified when the app enters or exits PiP mode.
  /// The stream emits `true` when entering PiP mode and `false` when exiting PiP mode.
  ///
  /// Example:
  /// ```dart
  /// VideoPlayerPip.instance.onPipModeChanged.listen((isInPipMode) {
  ///   print('Is in PiP mode: $isInPipMode');
  /// });
  /// ```
  /// Stream of PiP mode state changes.
  ///
  /// You can listen to this stream to be notified when the app enters or exits PiP mode.
  /// The stream emits a [PipState] containing the status and optional player ID.
  ///
  /// Example:
  /// ```dart
  /// VideoPlayerPip.instance.onPipStateChanged.listen((state) {
  ///   print('Is in PiP mode: ${state.isInPipMode} for player: ${state.playerId}');
  /// });
  /// ```
  Stream<PipState> get onPipStateChanged {
    return _onPipStateChangedController.stream;
  }

  /// Deprecated: use [onPipStateChanged] instead.
  @Deprecated('Use onPipStateChanged instead')
  Stream<bool> get onPipModeChanged {
    return _onPipStateChangedController.stream.map((state) => state.isInPipMode);
  }

  // ... (onPipRestoreRequested unchanged)

  // Singleton instance
  static final VideoPlayerPip _instance = VideoPlayerPip._();

  /// The shared instance of [VideoPlayerPip].
  static VideoPlayerPip get instance => _instance;

  VideoPlayerPip._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final _onPipStateChangedController = StreamController<PipState>.broadcast();
  final _onPipRestoreRequestedController = StreamController<void>.broadcast();

  /// Stream of PiP restore requests.
  Stream<void> get onPipRestoreRequested {
    return _onPipRestoreRequestedController.stream;
  }

  /// Notifies the native layer that the UI restore is completed.
  static Future<void> notifyRestoreCompleted() async {
    await _channel.invokeMethod('restoreCompleted');
  }

  /// Toggles Picture-in-Picture mode.
  Future<bool> togglePipMode(VideoPlayerController controller, {int? width, int? height}) async {
    final bool isInPip = await isInPipMode();
    if (isInPip) {
      return await exitPipMode();
    } else {
      return await enterPipMode(controller, width: width, height: height);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    debugPrint('VideoPlayerPip: Received method call: ${call.method}');
    switch (call.method) {
      case 'pipModeChanged':
        final bool isInPipMode = call.arguments['isInPipMode'] as bool;
        final int? playerId = call.arguments['playerId'] as int?;
        debugPrint('VideoPlayerPip: Mode changed. isInPipMode: $isInPipMode, playerId: $playerId');
        _onPipStateChangedController.add(PipState(isInPipMode: isInPipMode, playerId: playerId));
        break;
      case 'pipRestoreRequested':
        _onPipRestoreRequestedController.add(null);
        break;
      case 'pipError':
        final String errorMessage = call.arguments['error'] as String;
        debugPrint('PiP Error: $errorMessage');
        break;
      default:
        debugPrint('Unhandled method ${call.method}');
    }
  }

  /// Disposes resources used by the plugin.
  ///
  /// Call this when you're done using PiP to free up resources.
  /// Typically called in the `dispose` method of your StatefulWidget.
  void dispose() {
    if (!_onPipStateChangedController.isClosed) {
      _onPipStateChangedController.close();
    }
    if (!_onPipRestoreRequestedController.isClosed) {
      _onPipRestoreRequestedController.close();
    }
    _channel.setMethodCallHandler(null);
  }
}
