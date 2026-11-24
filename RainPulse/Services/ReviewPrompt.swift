import Foundation

/// Decides when to ask for an App Store rating: only after the app has proved useful
/// (used on 4+ different days, a forecast just loaded), at most once per app version,
/// and never in UI tests. Apple also caps the prompt at 3 times a year.
enum ReviewPrompt {
    private static let daysKey = "review.activeDays"
    private static let versionKey = "review.lastAskedVersion"

    static func recordUseToday() {
        let d = UserDefaults.standard
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        var days = Set(d.stringArray(forKey: daysKey) ?? [])
        days.insert(today)
        d.set(Array(days.sorted().suffix(30)), forKey: daysKey)
    }

    /// Call right after something useful happened (a forecast loaded).
    static func shouldAsk() -> Bool {
        guard !AppConfig.isUITest else { return false }
        let d = UserDefaults.standard
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        guard d.string(forKey: versionKey) != version,
              (d.stringArray(forKey: daysKey) ?? []).count >= 4 else { return false }
        d.set(version, forKey: versionKey)
        return true
    }
}
