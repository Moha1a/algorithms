import Flutter
import UIKit
import FirebaseAuth
import FirebaseMessaging
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var mapsSdkInitialized = false
  private var mapsDiagnostics: [String: Any] = [
    "map_plugin_used": "google_maps_flutter",
    "ios_maps_key_present": false,
    "ios_maps_key_source": "missing",
    "ios_maps_key_length": 0,
    "ios_maps_key_prefix_only": "",
    "map_sdk_initialized": false,
    "map_tiles_possible_auth_issue": true,
  ]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureGoogleMaps()

    GeneratedPluginRegistrant.register(with: self)
    application.registerForRemoteNotifications()
    logFirebasePhoneAuthNativeDiagnostics()
    installMapsDiagnosticsChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Auth.auth().setAPNSToken(deviceToken, type: firebaseAuthAPNSTokenType())
    Messaging.messaging().apnsToken = deviceToken
    print("[PHONE AUTH NATIVE] APNs token forwarded to FirebaseAuth type=\(firebaseAuthAPNSTokenTypeName()) bytes=\(deviceToken.count)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }

    super.application(
      application,
      didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler
    )
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if Auth.auth().canHandle(url) {
      return true
    }

    return super.application(app, open: url, options: options)
  }

  private func configureGoogleMaps() {
    let rawMapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let mapsApiKey = rawMapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let firebaseApiKey = readFirebaseApiKey()
    let hasKey = !mapsApiKey.isEmpty && !mapsApiKey.contains("$(")
    let isFirebaseApiKey = hasKey && firebaseApiKey != nil && mapsApiKey == firebaseApiKey
    var source = "Info.plist:GMSApiKey"

    if !hasKey {
      source = "missing_or_unexpanded_Info.plist:GMSApiKey"
      print("[MAP INIT] WARNING: Missing or unexpanded GMSApiKey in Info.plist")
    } else if isFirebaseApiKey {
      source = "invalid_firebase_api_key"
      print("[MAP INIT] WARNING: GMSApiKey matches Firebase API_KEY; provide a real iOS Google Maps key")
    } else {
      GMSServices.provideAPIKey(mapsApiKey)
      mapsSdkInitialized = true
      print("[MAP INIT] Google Maps iOS API key configured prefix=\(String(mapsApiKey.prefix(6))) length=\(mapsApiKey.count)")
    }

    mapsDiagnostics = [
      "map_plugin_used": "google_maps_flutter",
      "ios_maps_key_present": hasKey && !isFirebaseApiKey,
      "ios_maps_key_source": source,
      "ios_maps_key_length": mapsApiKey.count,
      "ios_maps_key_prefix_only": String(mapsApiKey.prefix(6)),
      "map_sdk_initialized": mapsSdkInitialized,
      "map_tiles_possible_auth_issue": true,
    ]
  }

  private func readFirebaseApiKey() -> String? {
    guard
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let plist = NSDictionary(contentsOfFile: path),
      let apiKey = plist["API_KEY"] as? String
    else {
      return nil
    }
    return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func firebaseAuthAPNSTokenType() -> AuthAPNSTokenType {
    #if DEBUG
    return .sandbox
    #else
    return .prod
    #endif
  }

  private func firebaseAuthAPNSTokenTypeName() -> String {
    #if DEBUG
    return "sandbox"
    #else
    return "prod"
    #endif
  }

  private func logFirebasePhoneAuthNativeDiagnostics() {
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    let backgroundModes =
      Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    let proxyValue = Bundle.main.object(forInfoDictionaryKey: "FirebaseAppDelegateProxyEnabled")
    let proxyDescription = proxyValue.map { "\($0)" } ?? "default_true"
    let urlTypes =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
    let urlSchemes = urlTypes.flatMap { item -> [String] in
      return item["CFBundleURLSchemes"] as? [String] ?? []
    }

    var googleBundleId = ""
    var googleAppId = ""
    var reversedClientId = ""
    if
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let plist = NSDictionary(contentsOfFile: path)
    {
      googleBundleId = plist["BUNDLE_ID"] as? String ?? ""
      googleAppId = plist["GOOGLE_APP_ID"] as? String ?? ""
      reversedClientId = plist["REVERSED_CLIENT_ID"] as? String ?? ""
    }

    let appIdScheme = googleAppId.replacingOccurrences(of: ":", with: "-")
    print("[PHONE AUTH NATIVE] bundleId=\(bundleId) googleBundleId=\(googleBundleId) googleAppId=\(googleAppId)")
    print("[PHONE AUTH NATIVE] reversedClientIdPresent=\(!reversedClientId.isEmpty) reversedClientIdSchemePresent=\(urlSchemes.contains(reversedClientId)) appIdSchemePresent=\(urlSchemes.contains(appIdScheme)) FirebaseAppDelegateProxyEnabled=\(proxyDescription) backgroundModes=\(backgroundModes.joined(separator: ","))")
  }

  private func installMapsDiagnosticsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("[MAP INIT] WARNING: FlutterViewController unavailable for diagnostics channel")
      return
    }

    let channel = FlutterMethodChannel(
      name: "manfathak/maps",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "diagnostics" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.mapsDiagnostics ?? [:])
    }
  }
}
