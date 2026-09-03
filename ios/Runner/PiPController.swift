import AVFoundation
import AVKit
import Flutter
import UIKit

/// Native iOS Picture-in-Picture controller using AVPlayer + AVPlayerLayer.
/// Only supports HLS (.m3u8) streams — system-managed PiP with full
/// background playback support via AVAudioSession.
class PiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PiPController()
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var pipContainerView: UIView?
    private var channel: FlutterMethodChannel?
    
    // Track PiP state
    private var isPiPActive = false
    
    private override init() {
        super.init()
    }
    
    /// Register the Flutter method channel.
    func register(with registrar: FlutterPluginRegistrar) {
        // Use the registrar's messenger
    }
    
    func setupChannel(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "simple_live/pip",
            binaryMessenger: messenger
        )
        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        
        // Configure audio session at setup time
        configureAudioSession()
    }
    
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isPipAvailable":
            result(AVPictureInPictureController.isPictureInPictureSupported())
            
        case "startPip":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing url", details: nil))
                return
            }
            let headers = args["headers"] as? [String: String]
            startPiP(url: url, headers: headers, result: result)
            
        case "stopPip":
            stopPiP()
            result(nil)
            
        case "isPipActive":
            result(isPiPActive)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("[PiP] Failed to configure audio session: \(error)")
        }
    }
    
    private func startPiP(url: String, headers: [String: String]?, result: @escaping FlutterResult) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            result(FlutterError(code: "NOT_SUPPORTED", message: "PiP not supported", details: nil))
            return
        }
        
        // Clean up any existing PiP
        cleanupPiP()
        
        // Re-configure audio session before starting
        configureAudioSession()
        
        // Create AVPlayer with HLS URL
        guard let streamURL = URL(string: url) else {
            result(FlutterError(code: "INVALID_URL", message: "Invalid URL: \(url)", details: nil))
            return
        }
        
        let asset: AVURLAsset
        if let headers = headers, !headers.isEmpty {
            asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: streamURL)
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player?.allowsExternalPlayback = true
        
        // Create a tiny hidden player layer — required for PiP
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        
        // Add to a container view attached to the window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            result(FlutterError(code: "NO_WINDOW", message: "No active window", details: nil))
            return
        }
        
        pipContainerView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        pipContainerView?.isUserInteractionEnabled = false
        pipContainerView?.clipsToBounds = true
        window.addSubview(pipContainerView!)
        pipContainerView?.layer.addSublayer(playerLayer!)
        
        // Start playback (muted — mpv handles actual audio)
        // Actually for PiP we want AVPlayer to handle audio too
        player?.isMuted = false
        player?.play()
        
        // Wait for player to be ready, then start PiP
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        
        // Store result for async callback
        pendingResult = result
    }
    
    private var pendingResult: FlutterResult?
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                change: [NSKeyValueChangeKey : Any]?,
                                context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let item = object as? AVPlayerItem {
            item.removeObserver(self, forKeyPath: "status")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if item.status == .readyToPlay {
                    self.enablePiPController()
                } else {
                    self.pendingResult?(FlutterError(
                        code: "PLAYBACK_FAILED",
                        message: "AVPlayer failed to load stream",
                        details: item.error?.localizedDescription
                    ))
                    self.pendingResult = nil
                    self.cleanupPiP()
                }
            }
        }
    }
    
    private func enablePiPController() {
        guard let playerLayer = playerLayer else {
            pendingResult?(FlutterError(code: "NO_LAYER", message: "No player layer", details: nil))
            pendingResult = nil
            return
        }
        
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        
        // On iOS 14.2+, auto-start PiP when app goes to background
        if #available(iOS 14.2, *) {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        
        // Small delay to let the controller initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, let pip = self.pipController else {
                self?.pendingResult?(FlutterError(code: "PIP_INIT_FAILED", message: "PiP controller not ready", details: nil))
                self?.pendingResult = nil
                return
            }
            
            if pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
                self.pendingResult?(true)
            } else {
                self.pendingResult?(FlutterError(code: "PIP_NOT_POSSIBLE", message: "PiP not possible right now", details: nil))
                self.cleanupPiP()
            }
            self.pendingResult = nil
        }
    }
    
    func stopPiP() {
        if let pip = pipController, pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
        cleanupPiP()
    }
    
    private func cleanupPiP() {
        isPiPActive = false
        pipController?.delegate = nil
        pipController = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        pipContainerView?.removeFromSuperview()
        pipContainerView = nil
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = true
        channel?.invokeMethod("onPiPStatusChanged", arguments: "willStart")
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = true
        channel?.invokeMethod("onPiPStatusChanged", arguments: "started")
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        channel?.invokeMethod("onPiPStatusChanged", arguments: "willStop")
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPiPActive = false
        channel?.invokeMethod("onPiPStatusChanged", arguments: "stopped")
        cleanupPiP()
    }
    
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        isPiPActive = false
        channel?.invokeMethod("onPiPStatusChanged", arguments: "failed")
        print("[PiP] Failed to start: \(error)")
        cleanupPiP()
    }
}
