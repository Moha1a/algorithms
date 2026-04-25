import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       !mapsApiKey.contains("$(GMS_API_KEY)") {
      GMSServices.provideAPIKey(mapsApiKey)
      print("[MAP INIT] Google Maps iOS API key configured")
    } else {
      print("[MAP INIT] WARNING: Missing GMSApiKey in Info.plist")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}