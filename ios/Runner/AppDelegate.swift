import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Set up PiP method channel using the engine's binary messenger
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SimpleLivePiP")
    if let registrar = registrar {
      PiPController.shared.setupChannel(messenger: registrar.messenger())
    }
  }
}
