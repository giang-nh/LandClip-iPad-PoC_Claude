import Foundation

enum LayerReaderError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "GISCore chưa được link với GDAL."
        case let .failed(message): return message
        }
    }
}

/// Reads a layer of a GeoPackage / File Geodatabase back as WGS-84 GeoJSON for
/// on-map preview.
struct NativeLayerReader: Sendable {
    var isAvailable: Bool { landclip_gis_has_gdal() == 1 }

    /// Raw WGS-84 GeoJSON for one layer. `Data` crosses the concurrency boundary
    /// cleanly; decode with `PreviewFeature.decodeCollection`.
    func rawGeoJSON(datasetURL: URL, layerName: String, maxFeatures: Int = 1000) throws -> Data {
        guard isAvailable else { throw LayerReaderError.unavailable }
        var nativeError: UnsafeMutablePointer<CChar>?
        let jsonPointer = datasetURL.path.withCString { path in
            layerName.withCString { layer in
                landclip_read_layer_geojson(path, layer, Int32(maxFeatures), &nativeError)
            }
        }
        defer {
            landclip_gis_free_string(jsonPointer)
            landclip_gis_free_string(nativeError)
        }
        guard let jsonPointer else {
            throw LayerReaderError.failed(nativeError.map { String(cString: $0) } ?? "Không đọc được layer.")
        }
        return Data(bytes: jsonPointer, count: strlen(jsonPointer))
    }

    func features(datasetURL: URL, layerName: String, maxFeatures: Int = 1000) throws -> [PreviewFeature] {
        PreviewFeature.decodeCollection(
            try rawGeoJSON(datasetURL: datasetURL, layerName: layerName, maxFeatures: maxFeatures)
        )
    }
}
