import Foundation

/// Central configuration. Values come from Info.plist, which is filled in from
/// Config/Base.xcconfig and Config/Secrets.xcconfig at build time.
enum AppConfig {
    static var appGroupID: String { info("AppGroupID") ?? "group.rainpulse" }

    /// OpenWeather key — used for radar / precipitation map tiles.
    static var owmAPIKey: String { info("OWMAPIKey") ?? "" }

    /// Optional Tomorrow.io key — alternative tile source (testing only on the free plan).
    static var tomorrowAPIKey: String { info("TomorrowAPIKey") ?? "" }

    /// Optional Open-Meteo commercial key. Empty = free (non-commercial) endpoint.
    static var openMeteoAPIKey: String { info("OpenMeteoAPIKey") ?? "" }

    /// Apple's standard EULA. Replace with your own terms page if you write one.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var privacyURL: URL {
        if let s = info("PrivacyPolicyURL"), let url = URL(string: s) { return url }
        return URL(string: "https://winniecherian.github.io/rainpulse/privacy.html")!
    }

    /// True only in Debug builds launched by the UI tests.
    static var isUITest: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-UITestMode")
        #else
        return false
        #endif
    }

    /// UI tests can force a tier with "-UITestTier pro|essential|free".
    static var uiTestTier: Tier? {
        guard isUITest, let i = CommandLine.arguments.firstIndex(of: "-UITestTier"),
              i + 1 < CommandLine.arguments.count else { return nil }
        switch CommandLine.arguments[i + 1] {
        case "pro": return .pro
        case "essential": return .essential
        default: return .free
        }
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static func info(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.hasPrefix("$(") { return nil }
        return value
    }
}
