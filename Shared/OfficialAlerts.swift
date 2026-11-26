import Foundation

// MARK: - Official warnings (government sources only)
//
// India: NDMA's SACHET feed (CAP 1.2), which carries warnings from IMD, CWC, INCOIS and the
// state disaster authorities. Elsewhere: Apple Weather's official alerts, where Apple has them.
// These are shown exactly as the agency wrote them and kept visually separate from
// RainPulse's own forecasts.

struct OfficialAlert: Identifiable, Codable, Hashable {
    enum Severity: Int, Codable, Comparable {
        case unknown = 0, minor, moderate, severe, extreme
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

        init(cap: String) {
            switch cap.lowercased() {
            case "extreme": self = .extreme
            case "severe": self = .severe
            case "moderate": self = .moderate
            case "minor": self = .minor
            default: self = .unknown
            }
        }
    }

    enum Source: String, Codable { case sachet, appleWeather }

    var id: String
    var event: String
    var headline: String
    var severity: Severity
    /// Issuing agency as the source names it, e.g. "IMD Chennai" or "National Weather Service".
    var agency: String
    var areaDesc: String
    var onset: Date?
    var expires: Date?
    var sent: Date
    var detailsURL: URL?
    var source: Source

    func isActive(at now: Date) -> Bool { (expires ?? .distantFuture) > now }
}

// MARK: - SACHET RSS feed

struct SachetFeedItem: Equatable {
    let guid: String
    let link: URL
    let author: String      // "IMD Chennai", "FSI", "Andhra Pradesh SDMA"
    let pubDate: Date
}

enum SachetFeed {
    static let url = URL(string: "https://sachet.ndma.gov.in/cap_public_website/rss/rss_india.xml")!
    static let portal = URL(string: "https://sachet.ndma.gov.in/")!

    static func parse(_ data: Data) -> [SachetFeedItem] {
        let p = SimpleXML(data: data)
        var items: [SachetFeedItem] = []
        for item in p.elements(named: "item") {
            guard let guid = item["guid"], let linkText = item["link"], let link = URL(string: linkText),
                  let date = item["pubDate"].flatMap(rfc822) else { continue }
            var author = item["author"] ?? ""
            if let open = author.firstIndex(of: "("), let close = author.lastIndex(of: ")"), open < close {
                author = String(author[author.index(after: open)..<close])
            }
            items.append(SachetFeedItem(guid: guid, link: link, author: author, pubDate: date))
        }
        return items
    }

    private static let rfcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    static func rfc822(_ s: String) -> Date? { rfcFormatter.date(from: s.trimmingCharacters(in: .whitespaces)) }
}

// MARK: - CAP 1.2 message

struct CAPMessage: Codable, Equatable {
    struct Info: Codable, Equatable {
        var language: String
        var event: String
        var headline: String
        var severity: String
        var onset: Date?
        var expires: Date?
        var areaDesc: String
    }

    var identifier: String
    var sender: String
    var sent: Date
    var msgType: String          // Alert, Update, Cancel
    var references: [String]     // identifiers this message updates or cancels
    var infos: [Info]

    /// Identifier without the "_NN" copy suffix SACHET adds per state authority.
    static func baseID(_ id: String) -> String {
        if let u = id.lastIndex(of: "_") { return String(id[..<u]) }
        return id
    }

    static func parse(_ data: Data) -> CAPMessage? {
        let x = SimpleXML(data: data)
        guard let root = x.elements(named: "alert").first, let identifier = root["identifier"] else { return nil }
        let sent = root["sent"].flatMap(isoDate) ?? Date()
        // references: "sender,identifier,sent sender,identifier,sent"
        let refs = (root["references"] ?? "").split(separator: " ").compactMap { entry -> String? in
            let parts = entry.split(separator: ",")
            return parts.count >= 2 ? String(parts[1]) : nil
        }
        let infos = x.elements(named: "info").map { i in
            Info(language: i["language"] ?? "en",
                 event: i["event"] ?? "",
                 headline: i["headline"] ?? "",
                 severity: i["severity"] ?? "",
                 onset: i["onset"].flatMap(isoDate),
                 expires: i["expires"].flatMap(isoDate),
                 areaDesc: i.child("area")?["areaDesc"] ?? "")
        }
        return CAPMessage(identifier: identifier, sender: root["sender"] ?? "", sent: sent,
                          msgType: root["msgType"] ?? "Alert", references: refs, infos: infos)
    }

    static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s.trimmingCharacters(in: .whitespaces))
    }

    /// The info block in the user's language when the agency published one, else English.
    func bestInfo(preferred languages: [String]) -> Info? {
        func lang(_ i: Info) -> String { i.language.lowercased().split(separator: "-").first.map(String.init) ?? "" }
        for want in languages.map({ $0.lowercased() }) {
            if let i = infos.first(where: { lang($0) == want && !$0.headline.isEmpty }) { return i }
        }
        return infos.first { lang($0) == "en" && !$0.headline.isEmpty } ?? infos.first { !$0.headline.isEmpty }
    }
}

// MARK: - Matching a place to a warning's area

/// Where the user is, in the words a warning uses ("Chennai district of Tamil Nadu").
struct AdminArea: Codable, Equatable {
    var country: String?          // ISO code, e.g. "IN"
    var state: String?
    var district: String?
    var locality: String?
}

enum AreaMatch {
    /// Spelling-tolerant key: "Kancheepuram" = "Kanchipuram", "Thoothukkudi" = "Thoothukudi".
    static func key(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        t = String(t.filter { $0.isLetter })
        t = t.replacingOccurrences(of: "h", with: "")
        t = t.replacingOccurrences(of: "ee", with: "i")
        t = t.replacingOccurrences(of: "oo", with: "u")
        t = t.replacingOccurrences(of: "y", with: "i")
        var out = ""
        for ch in t where out.last != ch { out.append(ch) }
        return out
    }

    /// "Chengalpattu, Kancheepuram districts of Tamil Nadu" → (["Chengalpattu","Kancheepuram"], "Tamil Nadu").
    static func split(_ areaDesc: String) -> (districts: [String], state: String?) {
        let lower = areaDesc.lowercased()
        for marker in [" districts of ", " district of "] {
            if let r = lower.range(of: marker) {
                let head = String(areaDesc[areaDesc.startIndex..<r.lowerBound])
                let state = String(areaDesc[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let districts = head.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return (districts, state.isEmpty ? nil : state)
            }
        }
        // No district list: a state- or region-wide warning ("Tamil Nadu", "Coastal Andhra Pradesh").
        return ([], areaDesc.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Does a warning for `areaDesc` cover this place?
    static func covers(_ areaDesc: String, place: AdminArea) -> Bool {
        let (districts, state) = split(areaDesc)
        let placeState = place.state.map(key)
        if let state, let placeState, !placeState.isEmpty {
            let s = key(state)
            // State must match when both are known (avoids "Bilaspur" in two states).
            guard s.contains(placeState) || placeState.contains(s) else { return false }
            if districts.isEmpty { return true }       // whole-state warning
        } else if districts.isEmpty {
            return false
        }
        let names = [place.district, place.locality].compactMap { $0 }.map(key).filter { $0.count >= 3 }
        guard !names.isEmpty else { return false }
        return districts.map(key).contains { d in names.contains { $0 == d || $0.hasPrefix(d) || d.hasPrefix($0) } }
    }
}

// MARK: - Turning CAP messages into the warnings to show

enum OfficialAlertLogic {
    /// Active, de-duplicated warnings covering `place`, most severe first.
    static func alerts(from messages: [CAPMessage], authorByID: [String: String], place: AdminArea,
                       languages: [String], now: Date) -> [OfficialAlert] {
        // Warnings the agency has cancelled. (Updates are handled by the duplicate check below:
        // the newest copy is seen first, and old versions expire on their own.)
        var cancelled = Set<String>()
        for m in messages where m.msgType.lowercased() == "cancel" {
            m.references.forEach { cancelled.insert(CAPMessage.baseID($0)) }
            cancelled.insert(CAPMessage.baseID(m.identifier))
        }
        var seen = Set<String>()
        var out: [OfficialAlert] = []
        for m in messages.sorted(by: { $0.sent > $1.sent }) {
            let base = CAPMessage.baseID(m.identifier)
            guard m.msgType.lowercased() != "cancel", !cancelled.contains(base) else { continue }
            guard let info = m.bestInfo(preferred: languages),
                  (info.expires ?? .distantFuture) > now,
                  m.infos.contains(where: { AreaMatch.covers($0.areaDesc, place: place) }) else { continue }
            // IMD issues one warning; each state authority re-sends it. Show it once.
            let dedupe = "\(AreaMatch.key(info.event))|\(info.expires?.timeIntervalSince1970 ?? 0)|\(AreaMatch.key(String(info.headline.prefix(60))))"
            guard seen.insert(dedupe).inserted else { continue }
            out.append(OfficialAlert(
                id: base, event: info.event, headline: info.headline,
                severity: .init(cap: info.severity),
                agency: authorByID[m.identifier] ?? prettySender(m.sender),
                areaDesc: info.areaDesc, onset: info.onset, expires: info.expires, sent: m.sent,
                detailsURL: SachetFeed.portal, source: .sachet))
        }
        return out.sorted { ($0.severity, $0.sent) > ($1.severity, $1.sent) }
    }

    /// "IMD-Chennai" → "IMD Chennai", "Kerala-SDMA" → "Kerala SDMA".
    static func prettySender(_ s: String) -> String { s.replacingOccurrences(of: "-", with: " ") }

    /// Notify only for serious warnings, once each.
    static func shouldNotify(_ alert: OfficialAlert, alreadyNotified: Set<String>) -> Bool {
        alert.severity >= .severe && !alreadyNotified.contains(alert.id)
    }
}

// MARK: - Tiny XML reader (enough for RSS and CAP)

/// Parses an XML document into a light element tree. Namespace prefixes (cap:) are dropped.
final class SimpleXML: NSObject, XMLParserDelegate {
    final class Element {
        let name: String
        var text = ""
        var children: [Element] = []
        weak var parent: Element?
        init(name: String, parent: Element?) { self.name = name; self.parent = parent }

        func child(_ name: String) -> Element? { children.first { $0.name == name } }
        subscript(_ name: String) -> String? {
            guard let c = child(name) else { return nil }
            let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
    }

    private let root = Element(name: "#root", parent: nil)
    private var current: Element

    init(data: Data) {
        current = root
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func elements(named name: String) -> [Element] {
        var found: [Element] = []
        func walk(_ e: Element) {
            if e.name == name { found.append(e) }
            e.children.forEach(walk)
        }
        walk(root)
        return found
    }

    private static func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let e = Element(name: Self.local(elementName), parent: current)
        current.children.append(e)
        current = e
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        current = current.parent ?? root
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { current.text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        current.text += String(decoding: CDATABlock, as: UTF8.self)
    }
}
