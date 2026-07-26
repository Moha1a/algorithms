import Flutter
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import GoogleMaps
import UserNotifications

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
  private var apnsTokenForwardedToFirebaseAuth = false
  private var apnsTokenByteCount = 0
  private var apnsTokenForwardedAt = ""
  private var remoteNotificationRegistrationError = ""
  private var remoteNotificationRegistrationFailedAt = ""
  private var remoteNotificationReceivedCount = 0
  private var lastRemoteNotificationAt = ""
  private var lastRemoteNotificationWasFirebaseAuth = false
  private var firebaseAuthSilentPushHandledCount = 0
  private var firebaseAuthSilentPushHandledAt = ""
  private var urlOpenReceivedCount = 0
  private var firebaseAuthUrlHandledCount = 0
  private var lastOpenedUrlAt = ""
  private var lastOpenedUrlScheme = ""
  private var lastOpenedUrlHost = ""
  private var lastOpenedUrlWasFirebaseAuth = false
  private var notificationAuthorizationStatus = "unknown"
  private var notificationAlertSetting = "unknown"
  private var notificationSoundSetting = "unknown"
  private var notificationBadgeSetting = "unknown"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureFirebaseIfNeeded()
    configureGoogleMaps()

    GeneratedPluginRegistrant.register(with: self)
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    application.registerForRemoteNotifications()
    refreshNotificationSettingsSnapshot()
    logFirebasePhoneAuthNativeDiagnostics()
    installMapsDiagnosticsChannel()
    installPhoneAuthDiagnosticsChannel()
    return didFinish
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Auth.auth().setAPNSToken(deviceToken, type: firebaseAuthAPNSTokenType())
    Messaging.messaging().apnsToken = deviceToken
    apnsTokenForwardedToFirebaseAuth = true
    apnsTokenByteCount = deviceToken.count
    apnsTokenForwardedAt = nowIsoString()
    remoteNotificationRegistrationError = ""
    remoteNotificationRegistrationFailedAt = ""
    print("[PHONE AUTH NATIVE] APNs token forwarded to FirebaseAuth type=\(firebaseAuthAPNSTokenTypeName()) bytes=\(deviceToken.count)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    remoteNotificationRegistrationError = error.localizedDescription
    remoteNotificationRegistrationFailedAt = nowIsoString()
    print("[PHONE AUTH NATIVE] APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    remoteNotificationReceivedCount += 1
    lastRemoteNotificationAt = nowIsoString()
    let handledByFirebaseAuth = Auth.auth().canHandleNotification(userInfo)
    lastRemoteNotificationWasFirebaseAuth = handledByFirebaseAuth
    if handledByFirebaseAuth {
      firebaseAuthSilentPushHandledCount += 1
      firebaseAuthSilentPushHandledAt = lastRemoteNotificationAt
      print("[PHONE AUTH NATIVE] FirebaseAuth silent push handled count=\(firebaseAuthSilentPushHandledCount)")
      completionHandler(.noData)
      return
    }

    Messaging.messaging().appDidReceiveMessage(userInfo)
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
    urlOpenReceivedCount += 1
    lastOpenedUrlAt = nowIsoString()
    lastOpenedUrlScheme = url.scheme ?? ""
    lastOpenedUrlHost = url.host ?? ""
    let handledByFirebaseAuth = Auth.auth().canHandle(url)
    lastOpenedUrlWasFirebaseAuth = handledByFirebaseAuth
    if handledByFirebaseAuth {
      firebaseAuthUrlHandledCount += 1
      print("[PHONE AUTH NATIVE] FirebaseAuth URL callback handled scheme=\(lastOpenedUrlScheme) count=\(firebaseAuthUrlHandledCount)")
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

  private func configureFirebaseIfNeeded() {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("[PHONE AUTH NATIVE] FirebaseApp configured natively before APNs registration")
    } else {
      print("[PHONE AUTH NATIVE] FirebaseApp already configured before APNs registration")
    }
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
    let diagnostics = phoneAuthNativeDiagnostics()
    print("[PHONE AUTH NATIVE] bundleId=\(diagnostics["bundleId"] ?? "") googleBundleId=\(diagnostics["googleBundleId"] ?? "") googleAppId=\(diagnostics["googleAppId"] ?? "")")
    print("[PHONE AUTH NATIVE] reversedClientIdPresent=\(diagnostics["reversedClientIdPresent"] ?? false) reversedClientIdSchemePresent=\(diagnostics["reversedClientIdSchemePresent"] ?? false) appIdSchemePresent=\(diagnostics["appIdSchemePresent"] ?? false) FirebaseAppDelegateProxyEnabled=\(diagnostics["firebaseAppDelegateProxyEnabled"] ?? "") backgroundModes=\(diagnostics["backgroundModes"] ?? [])")
    print("[PHONE AUTH NATIVE] profileApsEnvironment=\(diagnostics["profileApsEnvironment"] ?? "") profileTeamIdentifier=\(diagnostics["profileTeamIdentifier"] ?? "") profileApplicationIdentifier=\(diagnostics["profileApplicationIdentifier"] ?? "") embeddedProfilePresent=\(diagnostics["embeddedProfilePresent"] ?? false)")
  }

  private func phoneAuthNativeDiagnostics() -> [String: Any] {
    refreshNotificationSettingsSnapshot()
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

    let appIdScheme = "app-\(googleAppId.replacingOccurrences(of: ":", with: "-"))"
    var diagnostics: [String: Any] = [
      "bundleId": bundleId,
      "googleBundleId": googleBundleId,
      "googleAppId": googleAppId,
      "reversedClientIdPresent": !reversedClientId.isEmpty,
      "reversedClientIdSchemePresent": urlSchemes.contains(reversedClientId),
      "appIdScheme": appIdScheme,
      "appIdSchemePresent": urlSchemes.contains(appIdScheme),
      "firebaseAppDelegateProxyEnabled": proxyDescription,
      "applicationState": applicationStateName(UIApplication.shared.applicationState),
      "isRegisteredForRemoteNotifications": UIApplication.shared.isRegisteredForRemoteNotifications,
      "backgroundRefreshStatus": backgroundRefreshStatusName(UIApplication.shared.backgroundRefreshStatus),
      "isProtectedDataAvailable": UIApplication.shared.isProtectedDataAvailable,
      "iosSystemVersion": UIDevice.current.systemVersion,
      "iosDeviceModel": UIDevice.current.model,
      "notificationAuthorizationStatus": notificationAuthorizationStatus,
      "notificationAlertSetting": notificationAlertSetting,
      "notificationSoundSetting": notificationSoundSetting,
      "notificationBadgeSetting": notificationBadgeSetting,
      "backgroundModes": backgroundModes,
      "urlSchemes": urlSchemes,
      "apnsTokenTypeExpectedByBuild": firebaseAuthAPNSTokenTypeName(),
      "apnsTokenForwardedToFirebaseAuth": apnsTokenForwardedToFirebaseAuth,
      "apnsTokenByteCount": apnsTokenByteCount,
      "apnsTokenForwardedAt": apnsTokenForwardedAt,
      "remoteNotificationRegistrationError": remoteNotificationRegistrationError,
      "remoteNotificationRegistrationFailedAt": remoteNotificationRegistrationFailedAt,
      "remoteNotificationReceivedCount": remoteNotificationReceivedCount,
      "lastRemoteNotificationAt": lastRemoteNotificationAt,
      "lastRemoteNotificationWasFirebaseAuth": lastRemoteNotificationWasFirebaseAuth,
      "firebaseAuthSilentPushHandledCount": firebaseAuthSilentPushHandledCount,
      "firebaseAuthSilentPushHandledAt": firebaseAuthSilentPushHandledAt,
      "urlOpenReceivedCount": urlOpenReceivedCount,
      "firebaseAuthUrlHandledCount": firebaseAuthUrlHandledCount,
      "lastOpenedUrlAt": lastOpenedUrlAt,
      "lastOpenedUrlScheme": lastOpenedUrlScheme,
      "lastOpenedUrlHost": lastOpenedUrlHost,
      "lastOpenedUrlWasFirebaseAuth": lastOpenedUrlWasFirebaseAuth,
    ]

    for (key, value) in embeddedProvisioningProfileDiagnostics() {
      diagnostics[key] = value
    }
    return diagnostics
  }

  private func embeddedProvisioningProfileDiagnostics() -> [String: Any] {
    var diagnostics: [String: Any] = [
      "embeddedProfilePresent": false,
      "profileTeamIdentifier": "",
      "profileApplicationIdentifier": "",
      "profileApsEnvironment": "",
    ]
    guard
      let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url)
    else {
      return diagnostics
    }

    diagnostics["embeddedProfilePresent"] = true
    let text =
      String(data: data, encoding: .isoLatin1) ??
      String(data: data, encoding: .utf8) ??
      ""
    diagnostics["profileTeamIdentifier"] =
      firstMatch(in: text, pattern: "<key>TeamIdentifier</key>\\s*<array>\\s*<string>([^<]+)</string>")
    diagnostics["profileApplicationIdentifier"] =
      firstMatch(in: text, pattern: "<key>application-identifier</key>\\s*<string>([^<]+)</string>")
    diagnostics["profileApsEnvironment"] =
      firstMatch(in: text, pattern: "<key>aps-environment</key>\\s*<string>([^<]+)</string>")
    return diagnostics
  }

  private func firstMatch(in text: String, pattern: String) -> String {
    guard
      let regex = try? NSRegularExpression(pattern: pattern, options: []),
      let match = regex.firstMatch(
        in: text,
        options: [],
        range: NSRange(location: 0, length: text.utf16.count)
      ),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: text)
    else {
      return ""
    }
    return String(text[range])
  }

  private func nowIsoString() -> String {
    return ISO8601DateFormatter().string(from: Date())
  }

  private func refreshNotificationSettingsSnapshot() {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      self?.notificationAuthorizationStatus =
        self?.authorizationStatusName(settings.authorizationStatus) ?? "unknown"
      self?.notificationAlertSetting =
        self?.notificationSettingName(settings.alertSetting) ?? "unknown"
      self?.notificationSoundSetting =
        self?.notificationSettingName(settings.soundSetting) ?? "unknown"
      self?.notificationBadgeSetting =
        self?.notificationSettingName(settings.badgeSetting) ?? "unknown"
    }
  }

  private func authorizationStatusName(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    case .provisional:
      return "provisional"
    case .ephemeral:
      return "ephemeral"
    @unknown default:
      return "unknown"
    }
  }

  private func notificationSettingName(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported:
      return "notSupported"
    case .disabled:
      return "disabled"
    case .enabled:
      return "enabled"
    @unknown default:
      return "unknown"
    }
  }

  private func applicationStateName(_ state: UIApplication.State) -> String {
    switch state {
    case .active:
      return "active"
    case .inactive:
      return "inactive"
    case .background:
      return "background"
    @unknown default:
      return "unknown"
    }
  }

  private func backgroundRefreshStatusName(_ status: UIBackgroundRefreshStatus) -> String {
    switch status {
    case .available:
      return "available"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
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

  private func installPhoneAuthDiagnosticsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("[PHONE AUTH NATIVE] WARNING: FlutterViewController unavailable for diagnostics channel")
      return
    }

    let channel = FlutterMethodChannel(
      name: "manfathak/phone_auth",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "diagnostics" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.phoneAuthNativeDiagnostics() ?? [:])
    }
  }
}
