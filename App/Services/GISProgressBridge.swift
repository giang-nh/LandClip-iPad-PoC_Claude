import Foundation

/// Bridges a Swift closure to the C `landclip_progress_callback` signature.
///
/// The C engines call `callback(context, event_json)` from their worker thread;
/// returning a non-zero value asks them to stop at the next safe boundary. Keep a
/// strong reference to the bridge for the whole native call.
final class GISProgressBridge {
    /// Receives each event as a UTF-8 JSON string. Return `true` to request
    /// cancellation. Invoked on the native worker thread — keep it thread-safe.
    typealias Handler = @Sendable (String) -> Bool

    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var context: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    static let callback: landclip_progress_callback = { context, eventJSON in
        guard let context, let eventJSON else { return 0 }
        let bridge = Unmanaged<GISProgressBridge>.fromOpaque(context).takeUnretainedValue()
        return bridge.handler(String(cString: eventJSON)) ? 1 : 0
    }
}

/// A progress event emitted by `landclip_archive_extract_ppkx` or
/// `landclip_clip_package_json`, decoded from its JSON form.
struct GISProgressEvent: Decodable, Sendable {
    let event: String
    let phase: String?
    let gdb: String?
    let layer: String?
    let status: String?
    let geometryType: String?
    let sourceCount: Int?
    let entriesDone: Int?
    let bytesDone: Int?
    let candidateCount: Int?
    let outputCount: Int?

    static func decode(_ json: String) -> GISProgressEvent? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GISProgressEvent.self, from: data)
    }
}
