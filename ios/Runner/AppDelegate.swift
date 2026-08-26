import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let notificationCenter = NotificationCenter.default
  private var audioSessionObservers: [NSObjectProtocol] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    observeAudioSessionNotifications()
    configureAndActivateAudioSession(reason: "application launch")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  deinit {
    for observer in audioSessionObservers {
      notificationCenter.removeObserver(observer)
    }
  }

  private func configureAndActivateAudioSession(reason: String) {
    let audioSession = AVAudioSession.sharedInstance()

    do {
      try audioSession.setCategory(.playback, mode: .moviePlayback)
      try audioSession.setActive(true)
    } catch {
      NSLog(
        "Failed to configure or activate the audio session after %@: %@",
        reason,
        String(describing: error)
      )
    }
  }

  private func observeAudioSessionNotifications() {
    guard audioSessionObservers.isEmpty else {
      return
    }

    audioSessionObservers.append(
      notificationCenter.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioSessionInterruption(notification)
      }
    )

    audioSessionObservers.append(
      notificationCenter.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.configureAndActivateAudioSession(reason: "media services reset")
      }
    )
  }

  private func handleAudioSessionInterruption(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue),
      interruptionType == .ended,
      let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
    else {
      return
    }

    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
    guard options.contains(.shouldResume) else {
      return
    }

    configureAndActivateAudioSession(reason: "resumable interruption")
  }
}
