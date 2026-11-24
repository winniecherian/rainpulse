import Foundation

/// One hardened URLSession for all weather requests:
/// - TLS 1.2+ only (App Transport Security already forbids plain HTTP)
/// - no cookies, no credential storage, nothing cached to disk
enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": "RainPulse-iOS"]
        return URLSession(configuration: c)
    }()

    /// Coordinates sent to third-party weather services are rounded to ~1 km,
    /// enough for weather, never your exact position.
    static func approx(_ v: Double) -> String { String(format: "%.2f", v) }
}
