import 'package:flutter/material.dart';

import 'package:video_player_pip/video_player_pip.dart';

/// Simplified floating mini player
///
/// Features:
/// - Default large landscape size (90% width)
/// - Drag to move
/// - Release to bounce/snap to nearest edge
/// - No entrance animation
/// - No shadows or complex decorations
class FloatingMiniPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const FloatingMiniPlayer({
    super.key,
    required this.controller,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<FloatingMiniPlayer> createState() => _FloatingMiniPlayerState();
}

class _FloatingMiniPlayerState extends State<FloatingMiniPlayer>
    with SingleTickerProviderStateMixin {
  /// Constants
  static const _edgePadding = 12.0;

  /// Layout state
  Offset _position = Offset.zero;
  bool _hasPosition = false;
  double _width = 0.0;
  double _height = 0.0;

  /// Animation state
  late final AnimationController _animController;
  Animation<Offset>? _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this);
    _animController.addListener(() {
      setState(() {
        _position = _animation?.value ?? _position;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Initialize layout based on constraints (called on first build)
  void _initLayout(BoxConstraints constraints) {
    if (_hasPosition) return;

    final screenWidth = constraints.maxWidth;
    final aspectRatio = widget.controller.value.aspectRatio;

    // Default width logic:
    // If landscape (or unknown), take 90% of screen width.
    // If portrait, take 40% of screen width.
    double widthFraction = 0.9;
    if (aspectRatio > 0 && aspectRatio < 1.0) {
      widthFraction = 0.4;
    }

    _width = screenWidth * widthFraction;
    _height = aspectRatio > 0 ? _width / aspectRatio : _width * (9.0 / 16.0);

    // Initial position: Bottom Right, safe area aware
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final initialX = (screenWidth - _width) / 2; // Center horizontally
    final initialY =
        constraints.maxHeight - _height - bottomSafe - _edgePadding * 2;

    _position = Offset(initialX, initialY);
    _hasPosition = true;
  }

  /// Snap/Bounce logic on release
  void _onDragEnd(DragEndDetails details, BoxConstraints constraints) {
    final screenWidth = constraints.maxWidth;
    final screenHeight = constraints.maxHeight;
    final topSafe = MediaQuery.of(context).padding.top + _edgePadding;
    final bottomSafe = MediaQuery.of(context).padding.bottom + _edgePadding;

    // Calculate target X: Left or Right edge
    final centerX = _position.dx + _width / 2;
    double targetX = _edgePadding;
    if (centerX > screenWidth / 2) {
      targetX = screenWidth - _width - _edgePadding;
    }

    // Calculate target Y: Clamp current Y to safe area
    double targetY = _position.dy.clamp(
      topSafe,
      screenHeight - _height - bottomSafe,
    );

    final target = Offset(targetX, targetY);

    // Animate snap to edge with bounce
    _animation = Tween<Offset>(begin: _position, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.duration = const Duration(milliseconds: 500);
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initLayout(constraints);

        if (!_hasPosition) return const SizedBox();

        return Stack(
          children: [
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                onPanStart: (_) {
                  _animController.stop();
                },
                onPanUpdate: (details) {
                  setState(() {
                    _position += details.delta;
                  });
                },
                onPanEnd: (details) => _onDragEnd(details, constraints),
                onTap: widget.onTap,
                child: Container(
                  width: _width,
                  height: _height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black, // Background in case video loads slow
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(widget.controller),
                        // Close button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: widget.onClose,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
