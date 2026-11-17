import Foundation

/// What lies on a pad. The charger reports only pad numbers.
enum PadKind: String, Codable {
    case phone, watch, earbuds, other

    /// Pad order of the A25X7, checked on the device.
    static func forPad(_ id: Int) -> PadKind {
        [1: .earbuds, 2: .phone, 3: .watch][id] ?? .other
    }

    var title: String {
        switch self {
        case .phone: "Телефон"
        case .watch: "Часы"
        case .earbuds: "Наушники"
        case .other: "Площадка"
        }
    }

    var symbol: String {
        switch self {
        case .phone: "iphone"
        case .watch: "applewatch"
        case .earbuds: "airpodspro"
        case .other: "circle.dashed"
        }
    }
}

struct Pad: Codable, Identifiable, Hashable {
    var id: Int
    var status: String        // "output", "not_connected", "unknown"
    var watts: Double
    var volts: Double? = nil
    var amps: Double? = nil
    var raw: String
    var kind: PadKind? = nil  // filled in by the app from user settings

    var isCharging: Bool { status == "output" }
}

struct DeviceInfo: Codable, Hashable {
    var name: String?
    var firmware: String?
    var serial: String?
    var mac: String?
}

/// One line of daemon output, plus pad names added by the app.
struct ChargerState: Codable, Hashable {
    var ts: Double
    var connected: Bool
    var device: DeviceInfo?
    var pads: [Pad]
    var total: Double
    var error: String?

    var date: Date { Date(timeIntervalSince1970: ts) }

    static let placeholder = ChargerState(
        ts: Date().timeIntervalSince1970, connected: true,
        device: DeviceInfo(name: "Charging", firmware: "v0.0.5.2"),
        pads: [
            Pad(id: 1, status: "not_connected", watts: 0, raw: "", kind: .earbuds),
            Pad(id: 2, status: "output", watts: 7.5, raw: "", kind: .phone),
            Pad(id: 3, status: "output", watts: 1.0, raw: "", kind: .watch),
        ],
        total: 8.7)
}

enum SharedStore {
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    /// State older than this is shown as stale.
    static let staleAfter: TimeInterval = 120

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("state.json")
    }

    static func load() -> ChargerState? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChargerState.self, from: data)
    }

    static func save(_ state: ChargerState) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

func formatWatts(_ w: Double) -> String {
    (w >= 10 ? String(format: "%.0f Вт", w) : String(format: "%.1f Вт", w))
        .replacingOccurrences(of: ".", with: ",")
}
