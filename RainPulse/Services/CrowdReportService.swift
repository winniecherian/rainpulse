import Foundation
import CloudKit
import CoreLocation

/// Sends and fetches "Rain Truth" reports through the app's public CloudKit database.
/// Reports are stored under predictable record names (cell + time bucket + slot), so
/// nearby reports are fetched by name: no server code, queries or indexes needed.
actor CrowdReportService {
    static let shared = CrowdReportService()

    enum SubmitError: LocalizedError {
        case unavailable, noAccount, tooSoon, full, offline, busy
        var errorDescription: String? {
            switch self {
            case .offline: return String(localized: "No internet connection. Try again in a moment.")
            case .busy: return String(localized: "Reports are busy right now. Try again in a minute.")
            case .unavailable: return String(localized: "Reports aren't available right now.")
            case .noAccount: return String(localized: "Sign in to iCloud in Settings to send reports.")
            case .tooSoon: return String(localized: "Thanks! You can send another report in a few minutes.")
            case .full: return String(localized: "Lots of reports here already — thanks!")
            }
        }
    }

    /// Turns a CloudKit error into a friendly message, plus technical detail for TestFlight testers.
    static func describe(_ error: Error) -> (message: String, detail: String?) {
        if let e = error as? SubmitError { return (e.localizedDescription, nil) }
        guard let ck = error as? CKError else {
            return (SubmitError.unavailable.localizedDescription, isTestFlight ? error.localizedDescription : nil)
        }
        let friendly: SubmitError
        switch ck.code {
        case .notAuthenticated: friendly = .noAccount
        case .networkUnavailable, .networkFailure: friendly = .offline
        case .requestRateLimited, .zoneBusy, .serviceUnavailable, .quotaExceeded: friendly = .busy
        default: friendly = .unavailable
        }
        // CloudKit hides the server's reason in the description after "to server:".
        var reason = ck.localizedDescription
        if let r = reason.range(of: "to server:") { reason = String(reason[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        let detail = "CKError \(ck.code.rawValue): \(reason)"
        return (friendly.localizedDescription, isTestFlight ? detail : nil)
    }

    /// TestFlight builds carry a sandbox receipt.
    static var isTestFlight: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }

    static let recordType = "Report"
    private static let lastSentKey = "reports.lastSent"
    private var cache: (key: String, at: Date, reports: [CrowdReport])?
    private var mine: [CrowdReport] = []

    /// CloudKit is only touched in signed builds (CI test builds are unsigned and have no iCloud entitlement).
    static var isEnabled: Bool { AppConfig.cloudReportsEnabled }

    private lazy var database: CKDatabase? = {
        guard Self.isEnabled else { return nil }
        return CKContainer(identifier: AppConfig.cloudContainerID).publicCloudDatabase
    }()

    // MARK: Fetch

    func reports(near c: CLLocationCoordinate2D, maxAge: TimeInterval = 120) async -> [CrowdReport] {
        if AppConfig.isUITest { return CrowdReport.samples(around: c) }
        let key = Geohash.encode(c, precision: ReportKeys.precision)
        if let cache, cache.key == key, Date().timeIntervalSince(cache.at) < maxAge { return merged(cache.reports) }
        guard let db = database else { return mine }
        let names = ReportKeys.namesNear(c, now: Date())
        var found: [CrowdReport] = []
        for chunk in stride(from: 0, to: names.count, by: 200).map({ Array(names[$0..<min($0 + 200, names.count)]) }) {
            found += await fetch(chunk.map { CKRecord.ID(recordName: $0) }, from: db)
        }
        cache = (key, Date(), found)
        return merged(found)
    }

    /// Adds the user's own recent reports so they show up immediately.
    private func merged(_ list: [CrowdReport]) -> [CrowdReport] {
        let ids = Set(list.map(\.id))
        return list + mine.filter { !ids.contains($0.id) && Date().timeIntervalSince($0.time) < 2 * 3600 }
    }

    private func fetch(_ ids: [CKRecord.ID], from db: CKDatabase) async -> [CrowdReport] {
        await withCheckedContinuation { cont in
            var out: [CrowdReport] = []
            let op = CKFetchRecordsOperation(recordIDs: ids)
            op.desiredKeys = ["condition", "lat", "lon", "time", "area"]
            op.qualityOfService = .userInitiated
            op.perRecordResultBlock = { _, result in
                if case .success(let record) = result, let r = Self.report(from: record) { out.append(r) }
            }
            op.fetchRecordsResultBlock = { _ in cont.resume(returning: out) }
            db.add(op)
        }
    }

    static func report(from record: CKRecord) -> CrowdReport? {
        guard let raw = record["condition"] as? Int64, let condition = ReportCondition(rawValue: Int(raw)),
              let lat = record["lat"] as? Double, let lon = record["lon"] as? Double,
              let time = record["time"] as? Date else { return nil }
        return CrowdReport(id: record.recordID.recordName, condition: condition, latitude: lat, longitude: lon,
                           time: time, area: record["area"] as? String)
    }

    // MARK: Submit

    /// Minutes until the user may report again (one report every 5 minutes).
    static func cooldownMinutes(now: Date = Date()) -> Int {
        let last = UserDefaults.standard.double(forKey: lastSentKey)
        let wait = 300 - now.timeIntervalSince1970 + last
        return wait > 0 ? Int(ceil(wait / 60)) : 0
    }

    func submit(_ condition: ReportCondition, at c: CLLocationCoordinate2D, area: String?) async throws -> CrowdReport {
        if Self.cooldownMinutes() > 0 { throw SubmitError.tooSoon }
        let now = Date()
        let cell = Geohash.encode(c, precision: ReportKeys.precision)
        let base = CrowdReport(id: "", condition: condition,
                               latitude: ReportKeys.approximate(c.latitude),
                               longitude: ReportKeys.approximate(c.longitude),
                               time: now, area: condition == .waterlogging ? area : nil)
        if AppConfig.isUITest || !Self.isEnabled {
            guard AppConfig.isUITest else { throw SubmitError.unavailable }
            var r = base; r.id = "local-\(Int(now.timeIntervalSince1970))"
            remember(r)
            return r
        }
        guard let db = database else { throw SubmitError.unavailable }
        let status = try? await CKContainer(identifier: AppConfig.cloudContainerID).accountStatus()
        guard status == .available else { throw SubmitError.noAccount }

        let slots = ReportKeys.isFlood(condition) ? ReportKeys.floodSlots : ReportKeys.rainSlots
        for slot in (0..<slots).shuffled() {
            let name = ReportKeys.recordName(cell: cell, condition: condition, time: now, slot: slot)
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name))
            record["condition"] = Int64(condition.rawValue)
            record["lat"] = base.latitude
            record["lon"] = base.longitude
            record["time"] = now
            if let a = base.area { record["area"] = a }
            do {
                _ = try await db.save(record)
                var r = base; r.id = name
                remember(r)
                return r
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue    // slot taken by someone else: try the next one
            }
        }
        throw SubmitError.full
    }

    private func remember(_ r: CrowdReport) {
        mine.append(r)
        cache = nil
        UserDefaults.standard.set(r.time.timeIntervalSince1970, forKey: Self.lastSentKey)
    }
}
