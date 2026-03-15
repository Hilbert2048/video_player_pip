import Flutter
import UIKit
import AVFoundation
import AVKit

public class VideoPlayerPipPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate {
  private var channel: FlutterMethodChannel?
  
  // Cache controllers by playerId
  private var pipControllers: [Int: AVPictureInPictureController] = [:]
  
  // Map of observation tokens per playerId
  private var observationTokens: [Int: NSKeyValueObservation] = [:]
  
  private var isInPipMode = false
  private var restoreCompletionHandler: ((Bool) -> Void)?
  
  // Track the most recently active PiP player ID
  private var activePipPlayerId: Int?
  
  // Keep a weak reference to the registrar to access other plugins
  private static var registrar: FlutterPluginRegistrar?
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    let channel = FlutterMethodChannel(name: "video_player_pip", binaryMessenger: registrar.messenger())
    let instance = VideoPlayerPipPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    NSLog("VideoPlayerPip: Plugin registered")
  }
  
  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    NSLog("VideoPlayerPip: Plugin initialized")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("VideoPlayerPip: Received method call: \(call.method)")
    switch call.method {
    case "isPipSupported":
      let supported = isPipSupported()
      NSLog("VideoPlayerPip: isPipSupported = \(supported)")
      result(supported)
      
    case "enableAutoPip":
      guard let args = call.arguments as? [String: Any],
            let playerId = args["playerId"] as? Int else {
        NSLog("VideoPlayerPip: enableAutoPip failed - Invalid arguments")
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing playerId", details: nil))
        return
      }
      NSLog("VideoPlayerPip: Enabling auto PiP for playerId: \(playerId)")
      // Use retry mechanism to wait for the view to be composited
      enableAutoPipWithRetry(playerId: playerId, attempt: 0, maxAttempts: 10, completion: result)
      
    case "disableAutoPip":
      guard let args = call.arguments as? [String: Any],
            let playerId = args["playerId"] as? Int else {
          NSLog("VideoPlayerPip: disableAutoPip failed - Missing playerId")
          result(true)
          return
      }
      NSLog("VideoPlayerPip: Disabling auto PiP for playerId: \(playerId)")
      disableAutoPip(playerId: playerId)
      result(true)
      
    case "enterPipMode":
      guard let args = call.arguments as? [String: Any],
            let playerId = args["playerId"] as? Int else {
        NSLog("VideoPlayerPip: enterPipMode failed - Invalid arguments")
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing playerId", details: nil))
        return
      }
      
      NSLog("VideoPlayerPip: Attempting to enter PiP mode for playerId: \(playerId)")
      enterPipMode(playerId: playerId, completion: result)
      
    case "exitPipMode":
      NSLog("VideoPlayerPip: Attempting to exit PiP mode")
      exitPipMode(completion: result)
      
    case "isInPipMode":
      NSLog("VideoPlayerPip: isInPipMode query = \(isInPipMode)")
      result(isInPipMode)
      
    case "restoreCompleted":
      NSLog("VideoPlayerPip: Restore completed from Dart")
      restoreCompletionHandler?(true)
      restoreCompletionHandler = nil
      result(true)
      
    default:
      NSLog("VideoPlayerPip: Method not implemented: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func isPipSupported() -> Bool {
    if #available(iOS 14.0, *) {
      let supported = AVPictureInPictureController.isPictureInPictureSupported()
      NSLog("VideoPlayerPip: PiP supported by system: \(supported)")
      return supported
    }
    NSLog("VideoPlayerPip: PiP not supported (iOS < 14.0)")
    return false
  }
  
  /// Pre-initializes the PiP controller so the system can automatically trigger PiP
  /// when the user backgrounds the app. Does NOT call startPictureInPicture().
  private func enableAutoPipWithRetry(playerId: Int, attempt: Int, maxAttempts: Int, completion: @escaping FlutterResult) {
     if !isPipSupported() {
       NSLog("VideoPlayerPip: PiP not supported by the device")
       completion(false)
       return
     }

     if let playerLayer = findAVPlayerLayer(playerId: playerId) {
       NSLog("VideoPlayerPip: Found AVPlayerLayer on attempt \(attempt + 1)")
       setupAutoPipController(playerLayer: playerLayer, playerId: playerId, completion: completion)
       return
     }

     if attempt < maxAttempts {
       let delay = 0.1 * Double(attempt + 1)
       DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
           self?.enableAutoPipWithRetry(playerId: playerId, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
       }
     } else {
       NSLog("VideoPlayerPip: Could not find AVPlayerLayer after \(maxAttempts) attempts")
       completion(false)
     }
  }

  private func setupAutoPipController(playerLayer: AVPlayerLayer, playerId: Int, completion: @escaping FlutterResult) {
     NSLog("VideoPlayerPip: Setting up auto PiP controller with layer: \(playerLayer) for playerId: \(playerId)")
     
     if #available(iOS 14.0, *) {
       if AVPictureInPictureController.isPictureInPictureSupported() && playerLayer.player != nil {
         
         // Create new controller
         let controller = AVPictureInPictureController(playerLayer: playerLayer)
         controller?.delegate = self
         
         if #available(iOS 14.2, *) {
           // Ensure only this new controller has auto-pip enabled
           for (pid, otherController) in self.pipControllers {
               if pid != playerId {
                   otherController.canStartPictureInPictureAutomaticallyFromInline = false
               }
           }
           NSLog("VideoPlayerPip: Setting canStartPictureInPictureAutomaticallyFromInline = true for playerId: \(playerId)")
           controller?.canStartPictureInPictureAutomaticallyFromInline = true
         }
         
         if #available(iOS 15.0, *) {
           controller?.requiresLinearPlayback = false
         }
         
         // Store in map
         if let validController = controller {
             pipControllers[playerId] = validController
             
             // Set up observation
             let token = validController.observe(\.isPictureInPictureActive, options: [.new]) { [weak self] (controller, change) in
               guard let self = self, let newValue = change.newValue else { return }
               NSLog("VideoPlayerPip: isPictureInPictureActive changed to \(newValue) for playerId: \(playerId)")
               
               if newValue {
                   self.activePipPlayerId = playerId
                   self.isInPipMode = true
               } else {
                   if self.activePipPlayerId == playerId {
                       self.isInPipMode = false
                   }
               }
               
               self.channel?.invokeMethod("pipModeChanged", arguments: [
                   "isInPipMode": newValue,
                   "playerId": playerId
               ])
             }
             observationTokens[playerId] = token
         }
         
         NSLog("VideoPlayerPip: Auto PiP controller created successfully for playerId: \(playerId)")
         completion(true)
       } else {
         NSLog("VideoPlayerPip: Cannot create PiP controller (supported: \(AVPictureInPictureController.isPictureInPictureSupported()), player: \(playerLayer.player != nil))")
         completion(false)
       }
     } else {
       completion(false)
     }
  }

  private func enterPipMode(playerId: Int, completion: @escaping FlutterResult) {
    NSLog("VideoPlayerPip: enterPipMode called for playerId: \(playerId)")
    if !isPipSupported() {
      NSLog("VideoPlayerPip: PiP not supported by the device")
      completion(false)
      return
    }
    
    // Check cache first
    if let controller = pipControllers[playerId] {
        NSLog("VideoPlayerPip: Starting PiP from cached controller for \(playerId)")
        
        if !controller.isPictureInPictureActive {
             if !controller.isPictureInPicturePossible {
                 // Common reasons for not possible:
                 // 1. Video view not in window hierarchy
                 // 2. Video is not playing / paused
                 // 3. System hasn't acknowledged the layer yet
             }
            controller.startPictureInPicture()
        }
        completion(true)
        return
    }
    
    // No existing controller, create one from scratch
    NSLog("VideoPlayerPip: No existing controller, searching for AVPlayerLayer for playerId: \(playerId)")
    
    guard let playerLayer = findAVPlayerLayer(playerId: playerId) else {
      NSLog("VideoPlayerPip: Could not find player layer for ID: \(playerId)")
      completion(false)
      return
    }
    
    NSLog("VideoPlayerPip: Found AVPlayerLayer: \(playerLayer)")
    
    if let player = playerLayer.player {
      if player.timeControlStatus != .playing {
        player.play()
      }
      
      // Use setupAutoPipController to create and configure the controller
      setupAutoPipController(playerLayer: playerLayer, playerId: playerId) { [weak self] success in
          if let success = success as? Bool, success {
              if let controller = self?.pipControllers[playerId] {
                  NSLog("VideoPlayerPip: Starting newly created PiP controller")
                  if #available(iOS 15.0, *) {
                      controller.startPictureInPicture()
                      // Retry logic for iOS 15+ if needed
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak controller] in
                          if let c = controller, !c.isPictureInPictureActive {
                              c.startPictureInPicture()
                          }
                      }
                  } else {
                      controller.startPictureInPicture()
                  }
              }
              completion(true)
          } else {
              completion(false)
          }
      }
    } else {
      NSLog("VideoPlayerPip: AVPlayerLayer has no player set")
      completion(false)
    }
  }
  
  private func disableAutoPip(playerId: Int) {
    if let controller = pipControllers[playerId] {
        if #available(iOS 14.2, *) {
          controller.canStartPictureInPictureAutomaticallyFromInline = false
        }
        
        if let token = observationTokens[playerId] {
            token.invalidate()
            observationTokens.removeValue(forKey: playerId)
        }
        pipControllers.removeValue(forKey: playerId)
        NSLog("VideoPlayerPip: Removed controller for playerId: \(playerId)")
    }
  }

  private func cleanupPipController(playerId: Int? = nil) {
      if let id = playerId {
          // Clean specific
          if let token = observationTokens[id] {
              token.invalidate()
              observationTokens.removeValue(forKey: id)
          }
          pipControllers.removeValue(forKey: id)
      } else {
          // Clean all (e.g. on deinit)
          for (_, token) in observationTokens {
              token.invalidate()
          }
          observationTokens.removeAll()
          // Stop any active PiP
          for (_, controller) in pipControllers {
              if controller.isPictureInPictureActive {
                  controller.stopPictureInPicture()
              }
          }
          pipControllers.removeAll()
          activePipPlayerId = nil
      }
  }
  
  private func exitPipMode(completion: @escaping FlutterResult) {
      // Stop whichever is active
      if let activeId = activePipPlayerId, let controller = pipControllers[activeId] {
          NSLog("VideoPlayerPip: Stopping active PiP controller for \(activeId)")
          controller.stopPictureInPicture()
          completion(true)
      } else {
          NSLog("VideoPlayerPip: No active PiP ID found, sweeping all...")
          // Fallback: iterate all?
          var stoppedAny = false
          for (_, controller) in pipControllers {
              if controller.isPictureInPictureActive {
                  controller.stopPictureInPicture()
                  stoppedAny = true
              }
          }
          if !stoppedAny {
               NSLog("VideoPlayerPip: No active PiP controller to stop")
          }
          completion(true)
      }
  }
  
  /**
   * Find the AVPlayerLayer for the specified player ID.
   * This searches through the view hierarchy to find the platform view created by video_player.
   */
  /**
   * Find the AVPlayerLayer for the specified player ID.
   * This searches through the view hierarchy to find the platform view created by video_player.
   */
  private func findAVPlayerLayer(playerId: Int) -> AVPlayerLayer? {
    NSLog("VideoPlayerPip: Finding AVPlayerLayer for playerId: \(playerId)")
    // Use a more modern approach to get the active window
    let keyWindow = getKeyWindow()
    NSLog("VideoPlayerPip: keyWindow found: \(keyWindow != nil)")
    
    guard let rootViewController = keyWindow?.rootViewController else {
        NSLog("VideoPlayerPip: No rootViewController found")
        return nil
    }
    
    NSLog("VideoPlayerPip: Starting search from rootViewController: \(type(of: rootViewController))")
    
    // Collect ALL candidate layers
    var candidates: [AVPlayerLayer] = []
    collectAVPlayerLayers(view: rootViewController.view, depth: 0, into: &candidates)
    
    NSLog("VideoPlayerPip: Found \(candidates.count) candidate AVPlayerLayers")
    
    // Filter for the best candidate
    // Criteria:
    // 1. Must have a player
    // 2. Player should be playing (rate > 0)
    // 3. (Optional) View should be visible/in-bounds?
    // Since we know the user is trying to PiP the *active* video, prioritizing the playing one is safest.
    
    var bestLayer: AVPlayerLayer?
    
    for layer in candidates {
        if let player = layer.player {
            let isPlaying = player.rate > 0
            
            if isPlaying {
                // Strong signal: this is the active video
                bestLayer = layer
                break // Found the playing video!
            }
            
            // Fallback: keep the last one found if none are playing (e.g. paused)
            if bestLayer == nil {
                bestLayer = layer
            }
        }
    }
    
    if let best = bestLayer {
        NSLog("VideoPlayerPip: Selected best layer: \(best)")
        return best
    }
    
    return nil
  }
  
  /**
   * Get the key window using a more modern approach that works on iOS 13+
   */
  private func getKeyWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes
        .filter { $0.activationState == .foregroundActive }
        .compactMap { $0 as? UIWindowScene }
      
      NSLog("VideoPlayerPip: Found \(scenes.count) active window scenes")
      
      if let windowScene = scenes.first {
        let windows = windowScene.windows.filter { $0.isKeyWindow }
        NSLog("VideoPlayerPip: Found \(windows.count) key windows in the first scene")
        return windows.first
      }
      return nil
    } else {
      let window = UIApplication.shared.keyWindow
      NSLog("VideoPlayerPip: Using legacy keyWindow approach: \(window != nil)")
      return window
    }
  }
  
  /**
   * Recursively collect all AVPlayerLayers in the view hierarchy.
   */
  private func collectAVPlayerLayers(view: UIView, depth: Int, into candidates: inout [AVPlayerLayer]) {
    // Check if this view's backing layer is an AVPlayerLayer (e.g. FVPPlayerView)
    if let playerLayer = view.layer as? AVPlayerLayer {
      if playerLayer.player != nil && !candidates.contains(playerLayer) {
          candidates.append(playerLayer)
      }
    }
    
    // Check sublayers directly
    // Some implementations add the AVPlayerLayer as a sublayer instead of the backing layer
    if let sublayers = view.layer.sublayers {
      for sublayer in sublayers {
        if let playerLayer = sublayer as? AVPlayerLayer {
          if playerLayer.player != nil && !candidates.contains(playerLayer) {
            candidates.append(playerLayer)
          }
        }
      }
    }
    
    // Recursively check subviews
    for subview in view.subviews {
      collectAVPlayerLayers(view: subview, depth: depth + 1, into: &candidates)
    }
  }

  public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    let nsError = error as NSError
    NSLog("VideoPlayerPip: Failed to start PiP. Error Domain: \(nsError.domain), Code: \(nsError.code), Description: \(nsError.localizedDescription)")
    channel?.invokeMethod("pipError", arguments: ["error": error.localizedDescription])
  }
  
  public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    NSLog("VideoPlayerPip: PiP will start")
  }
  
  public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    NSLog("VideoPlayerPip: PiP will stop")
  }
  
  public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    NSLog("VideoPlayerPip: Restore UI requested")
    restoreCompletionHandler = completionHandler
    channel?.invokeMethod("pipRestoreRequested", arguments: nil)
    
    // Timeout protection: auto-complete if Dart doesn't respond within 5 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
      if let handler = self?.restoreCompletionHandler {
        NSLog("VideoPlayerPip: Restore timeout, completing automatically")
        handler(true)
        self?.restoreCompletionHandler = nil
      }
    }
  }
  
  deinit {
    NSLog("VideoPlayerPip: Plugin being deallocated")
    cleanupPipController()
  }
}
