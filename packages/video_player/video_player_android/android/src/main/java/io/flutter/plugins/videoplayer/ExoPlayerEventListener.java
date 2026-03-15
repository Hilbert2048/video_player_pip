// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.datasource.HttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import java.util.HashMap;
import java.util.Map;

public abstract class ExoPlayerEventListener implements Player.Listener {
  private boolean isBuffering = false;
  private boolean isInitialized;
  protected final ExoPlayer exoPlayer;
  protected final VideoPlayerCallbacks events;

  protected enum RotationDegrees {
    ROTATE_0(0),
    ROTATE_90(90),
    ROTATE_180(180),
    ROTATE_270(270);

    private final int degrees;

    RotationDegrees(int degrees) {
      this.degrees = degrees;
    }

    public static RotationDegrees fromDegrees(int degrees) {
      for (RotationDegrees rotationDegrees : RotationDegrees.values()) {
        if (rotationDegrees.degrees == degrees) {
          return rotationDegrees;
        }
      }
      throw new IllegalArgumentException("Invalid rotation degrees specified: " + degrees);
    }

    public int getDegrees() {
      return this.degrees;
    }
  }

  public ExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @NonNull VideoPlayerCallbacks events, boolean initialized) {
    this.exoPlayer = exoPlayer;
    this.events = events;
    this.isInitialized = initialized;
  }

  private void setBuffering(boolean buffering) {
    if (isBuffering == buffering) {
      return;
    }
    isBuffering = buffering;
    if (buffering) {
      events.onBufferingStart();
    } else {
      events.onBufferingEnd();
    }
  }

  protected abstract void sendInitialized();

  @Override
  public void onPlaybackStateChanged(final int playbackState) {
    switch (playbackState) {
      case Player.STATE_BUFFERING:
        setBuffering(true);
        events.onBufferingUpdate(exoPlayer.getBufferedPosition());
        break;
      case Player.STATE_READY:
        if (!isInitialized) {
          isInitialized = true;
          sendInitialized();
        }
        // No early return here, we need to handle buffering state regardless of initialization
        break;
      case Player.STATE_ENDED:
        events.onCompleted();
        break;
      case Player.STATE_IDLE:
        break;
    }
    if (playbackState != Player.STATE_BUFFERING) {
      setBuffering(false);
    }
  }

  @Override
  public void onPlayerError(@NonNull final PlaybackException error) {
    setBuffering(false);
    if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
      // See
      // https://exoplayer.dev/live-streaming.html#behindlivewindowexception-and-error_code_behind_live_window
      exoPlayer.seekToDefaultPosition();
      exoPlayer.prepare();
    } else {
      Integer httpStatus = findHttpStatus(error);
      String message = buildMessage(error);
      Throwable root = getDeepestCause(error);
      String reasonCode = PlaybackException.getErrorCodeName(error.errorCode);
      Map<String, Object> details = new HashMap<>();
      details.put("platform", "android");
      details.put("reasonCode", reasonCode);
      details.put("reasonMessage", message);
      details.put("nativeCode", error.errorCode);
      details.put("nativeDomain", "ExoPlayer");
      details.put("exceptionClass", root.getClass().getName());
      if (httpStatus != null) {
        details.put("httpStatus", httpStatus);
      }
      events.onError("VideoError", message, details);
    }
  }

  private static String buildMessage(@NonNull PlaybackException error) {
    Throwable root = getDeepestCause(error);
    String rootMessage = root != null ? root.getMessage() : null;
    return
        (rootMessage != null && !rootMessage.isEmpty())
            ? rootMessage
            : (error.getMessage() != null ? error.getMessage() : "Video player had error");
  }

  private static Throwable getDeepestCause(@NonNull Throwable error) {
    Throwable cursor = error;
    Throwable next = cursor.getCause();
    while (next != null) {
      cursor = next;
      next = cursor.getCause();
    }
    return cursor;
  }

  private static Integer findHttpStatus(@NonNull Throwable error) {
    Throwable cursor = error;
    while (cursor != null) {
      if (cursor instanceof HttpDataSource.InvalidResponseCodeException) {
        return ((HttpDataSource.InvalidResponseCodeException) cursor).responseCode;
      }
      cursor = cursor.getCause();
    }
    return null;
  }

  @Override
  public void onIsPlayingChanged(boolean isPlaying) {
    events.onIsPlayingStateUpdate(isPlaying);
  }
}
