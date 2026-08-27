import Foundation

enum ClipEngineError: LocalizedError {
    case unavailable
    case failed(String)
    case cancelled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: return "GISCore chưa được link với GDAL."
        case let .failed(message): return message
        case .cancelled: return "Đã hủy trích xuất."
        case .invalidResponse: return "GISCore trả về kết quả không hợp lệ."
        }
    }
}

/// Swift front end for `landclip_clip_package_json`: clips every supported layer
/// of the given geodatabases against a polygonal AOI, writing a GeoPackage + CSV.
struct NativeClipEngine: Sendable {
    var isAvailable: Bool { landclip_gis_has_gdal() == 1 }

    /// - Parameters:
    ///   - gdbURLs: `.gdb` directories discovered inside the package.
    ///   - aoiURL: GeoJSON / GeoPackage file with one or more polygons and a CRS.
    ///   - outputDirectory: where `result.gpkg` and `result_summary.csv` are written.
    ///   - onEvent: progress events, delivered on a background thread.
    func clip(
        gdbURLs: [URL],
        aoiURL: URL,
        outputDirectory: URL,
        onEvent: @escaping GISProgressBridge.Handler = { _ in false }
    ) throws -> ClipResult {
        guard isAvailable else { throw ClipEngineError.unavailable }

        let gpkgURL = outputDirectory.appendingPathComponent("result.gpkg")
        let csvURL = outputDirectory.appendingPathComponent("result_summary.csv")
        for stale in [gpkgURL, csvURL] { try? FileManager.default.removeItem(at: stale) }

        let pathsJSON = String(
            data: try JSONEncoder().encode(gdbURLs.map(\.path)),
            encoding: .utf8
        ) ?? "[]"

        let bridge = GISProgressBridge(onEvent)
        var nativeError: UnsafeMutablePointer<CChar>?
        let jsonPointer = pathsJSON.withCString { paths in
            aoiURL.path.withCString { aoi in
                gpkgURL.path.withCString { gpkg in
                    csvURL.path.withCString { csv in
                        landclip_clip_package_json(
                            paths, aoi, gpkg, csv,
                            GISProgressBridge.callback, bridge.context,
                            &nativeError
                        )
                    }
                }
            }
        }
        withExtendedLifetime(bridge) {}
        defer {
            landclip_gis_free_string(jsonPointer)
            landclip_gis_free_string(nativeError)
        }

        guard let jsonPointer else {
            let message = nativeError.map { String(cString: $0) } ?? "Clip thất bại."
            throw message.contains("cancelled") || message.contains("hủy")
                ? ClipEngineError.cancelled
                : ClipEngineError.failed(message)
        }
        guard let result = try? JSONDecoder().decode(
            ClipResult.self,
            from: Data(bytes: jsonPointer, count: strlen(jsonPointer))
        ) else {
            throw ClipEngineError.invalidResponse
        }
        return result
    }
}
