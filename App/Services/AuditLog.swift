import Foundation

/// On-device audit trail. Records what happened (not the geodata) so an operator
/// can review activity. Written as JSON lines to Application Support; nothing is
/// sent anywhere. A cloud sink (e.g. Supabase) would implement `AuditSink` and be
/// opt-in — see docs/07_service_setup_vi.md in the Windows repo for that side.
protocol AuditSink: Sendable {
    func record(_ event: AuditEvent)
}

struct AuditEvent: Codable, Sendable {
    let timestamp: Date
    let kind: String
    var userName: String = ""
    var deviceName: String = ""
    var appVersion: String = ""
    var packageName: String?
    var packageSize: Int64?
    var packageSHA256: String?
    var layerCount: Int?
    var selectedLayers: Int?
    var writtenLayers: Int?
    var status: String?
    var durationMs: Int?
    var message: String?
}

/// Appends events to `audit.jsonl` in Application Support.
final class LocalFileAuditSink: AuditSink, @unchecked Sendable {
    static let shared = LocalFileAuditSink()

    private let queue = DispatchQueue(label: "landclip.audit")
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("audit.jsonl")
    }

    func record(_ event: AuditEvent) {
        queue.async { [fileURL, encoder] in
            guard var line = try? encoder.encode(event) else { return }
            line.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// The whole log, newest first, for an in-app viewer.
    func readAll() -> [AuditEvent] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").reversed().compactMap {
            try? decoder.decode(AuditEvent.self, from: Data($0.utf8))
        }
    }
}

enum Audit {
    static var sink: AuditSink = LocalFileAuditSink.shared

    static func record(_ kind: String, user: String, configure: (inout AuditEvent) -> Void = { _ in }) {
        var event = AuditEvent(timestamp: Date(), kind: kind)
        event.userName = user
        event.deviceName = deviceName
        event.appVersion = appVersion
        configure(&event)
        sink.record(event)
    }

    private static var deviceName: String {
        #if canImport(UIKit)
        return "iPad"
        #else
        return "unknown"
        #endif
    }

    private static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
