import Foundation
import BackgroundTasks
import UserNotifications

/// "Rain nearby" alerts. iOS wakes the app periodically (Background App Refresh);
/// we check the 15-minute precipitation forecast for the user's places and notify
/// when rain is about to start. iOS decides the exact timing, so alerts are
/// best-effort — a server push service is the upgrade path for guaranteed timing.
enum RainAlertService {
    static let taskID: String = (Bundle.main.bundleIdentifier ?? "rainpulse") + ".refresh"
    private static let lastNotifiedKey = "alerts.lastNotified"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Runs a check across all alert places.
    static func checkAll() async {
        guard AlertSettings.enabled else { return }
        let tier = SharedStore.tier

        var targets: [Place] = []
        if let current = SharedStore.lastLocation { targets.append(current) }
        if tier >= .essential {
            targets += SharedStore.loadPlaces().filter(\.alertsEnabled)
        }
        targets = Array(targets.prefix(tier.alertPlacesLimit))

        for place in targets {
            if Task.isCancelled { return }
            guard let forecast = try? await ForecastService.shared.forecast(
                latitude: place.latitude, longitude: place.longitude, days: 1, maxAge: 300) else { continue }
            await evaluate(forecast, for: place)
        }
    }

    private static func evaluate(_ forecast: Forecast, for place: Place) async {
        let threshold = AlertSettings.thresholdMM
        let lead = AlertSettings.leadMinutes
        guard !forecast.isRainingNow,
              let start = forecast.rainStart(within: lead, threshold: threshold) else { return }

        // Don't repeat an alert for the same place within 2 hours.
        let key = place.isCurrentLocation ? "current" : place.id.uuidString
        var log = SharedStore.defaults.dictionary(forKey: lastNotifiedKey) as? [String: Double] ?? [:]
        if let last = log[key], Date().timeIntervalSince1970 - last < 2 * 3600 { return }

        let minutes = max(5, Int(start.timeIntervalSinceNow / 60))
        let peak = forecast.upcomingSteps(hours: Double(lead) / 60 + 0.5).map(\.precipitation).max() ?? threshold

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rain in about \(minutes) min")
        content.body = String(localized: "\(Fmt.intensity(peak)) rain expected at \(place.name) around \(Fmt.time(start, in: forecast.timeZone)).")
        content.sound = .default
        content.threadIdentifier = "rain-\(key)"

        let request = UNNotificationRequest(identifier: "rain-\(key)-\(Int(start.timeIntervalSince1970))",
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)

        log[key] = Date().timeIntervalSince1970
        SharedStore.defaults.set(log, forKey: lastNotifiedKey)
    }
}
