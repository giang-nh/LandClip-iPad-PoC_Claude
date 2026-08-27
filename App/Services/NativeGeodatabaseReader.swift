import Foundation

enum NativeGeodatabaseError: LocalizedError {
    case unavailable
    case scanFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "GISCore chưa được link với GDAL XCFramework."
        case let .scanFailed(message):
            return message
        case .invalidResponse:
            return "GISCore trả về catalog không hợp lệ."
        }
    }
}

struct NativeGeodatabaseReader: Sendable {
    private struct Response: Decodable {
        struct Layer: Decodable {
            let name: String
            let geometryType: String
            let featureCount: Int?
            let crs: String?
        }

        let engineVersion: String
        let layers: [Layer]
    }

    var isAvailable: Bool { landclip_gis_has_gdal() == 1 }

    var engineVersion: String {
        String(cString: landclip_gis_engine_version())
    }

    func read(gdbURL: URL) throws -> [LayerInfo] {
        guard isAvailable else { throw NativeGeodatabaseError.unavailable }
        configureDataPaths()

        var nativeError: UnsafeMutablePointer<CChar>?
        let jsonPointer = gdbURL.path.withCString {
            landclip_gis_copy_gdb_catalog_json($0, &nativeError)
        }
        defer {
            landclip_gis_free_string(jsonPointer)
            landclip_gis_free_string(nativeError)
        }
        guard let jsonPointer else {
            let message = nativeError.map { String(cString: $0) } ?? "Không thể đọc geodatabase."
            throw NativeGeodatabaseError.scanFailed(message)
        }
        guard let response = try? JSONDecoder().decode(
            Response.self,
            from: Data(bytes: jsonPointer, count: strlen(jsonPointer))
        ) else {
            throw NativeGeodatabaseError.invalidResponse
        }
        return response.layers.map { layer in
            LayerInfo(
                id: "\(gdbURL.lastPathComponent)/\(layer.name)",
                geodatabase: gdbURL.lastPathComponent,
                name: layer.name,
                geometryType: layer.geometryType,
                featureCount: layer.featureCount,
                crs: layer.crs
            )
        }
    }

    private func configureDataPaths() {
        let gdalPath = Bundle.main.url(forResource: "gdal", withExtension: nil)?.path
            ?? Bundle.main.url(forResource: "gdal", withExtension: nil, subdirectory: "Resources")?.path
        let projPath = Bundle.main.url(forResource: "proj", withExtension: nil)?.path
            ?? Bundle.main.url(forResource: "proj", withExtension: nil, subdirectory: "Resources")?.path
        gdalPath?.withCString { gdalCString in
            projPath?.withCString { projCString in
                landclip_gis_configure_data_paths(gdalCString, projCString)
            }
        }
    }
}
