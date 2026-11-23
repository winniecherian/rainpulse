import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "AI insights": a two-sentence, practical summary of the forecast.
/// Uses Apple's on-device model (Apple Intelligence, iOS 26) when available — free and private —
/// and falls back to a rule-based summary everywhere else.
enum InsightService {

    static func insight(for forecast: Forecast, place: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                do {
                    let session = LanguageModelSession(instructions: """
                        You are a concise weather assistant inside a rain radar app. \
                        Write exactly two short, friendly sentences of practical advice \
                        (umbrella, best time to go out, what to wear) using ONLY the data given. \
                        Do not invent numbers. No emojis.
                        """)
                    let response = try await session.respond(to: prompt(for: forecast, place: place))
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { return text }
                } catch {
                    // fall through to the rule-based summary
                }
            }
        }
        #endif
        return ruleBased(forecast, place: place)
    }

    static func prompt(for f: Forecast, place: String) -> String {
        let tz = f.timeZone
        let hours = f.hourly.filter { $0.time > Date().addingTimeInterval(-3600) }.prefix(12)
            .map { "\(Fmt.hour($0.time, in: tz)): \(Int($0.temperature.rounded()))°C, rain chance \($0.precipitationProbability ?? 0)%, \(String(format: "%.1f", $0.precipitation)) mm" }
            .joined(separator: "\n")
        let today = f.daily.first.map { "Today: high \(Int($0.maxTemperature.rounded()))°C, low \(Int($0.minTemperature.rounded()))°C, rain \(String(format: "%.1f", $0.precipitationSum)) mm" } ?? ""
        return """
        Place: \(place)
        Now: \(Int(f.current.temperature.rounded()))°C, \(WeatherCode.description(f.current.weatherCode))
        Next 3 hours: \(f.rainDetail())
        \(today)
        Hourly:
        \(hours)
        """
    }

    static func ruleBased(_ f: Forecast, place: String) -> String {
        var parts: [String] = [f.rainDetail()]
        let nextHours = f.hourly.filter { $0.time > Date() }.prefix(12)
        if let wettest = nextHours.max(by: { ($0.precipitationProbability ?? 0) < ($1.precipitationProbability ?? 0) }),
           (wettest.precipitationProbability ?? 0) >= 50 {
            parts.append(String(localized: "Carry an umbrella — rain is most likely around \(Fmt.hour(wettest.time, in: f.timeZone))."))
        } else if let dry = nextHours.first(where: { ($0.precipitationProbability ?? 0) < 20 }) {
            parts.append(String(localized: "Drier spell from about \(Fmt.hour(dry.time, in: f.timeZone)) — a good time to head out."))
        }
        return parts.joined(separator: " ")
    }
}
