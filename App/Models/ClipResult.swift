import Foundation

/// One row of the clip summary — mirrors `LayerResult` in the Windows engine.
struct ClipLayerResult: Identifiable, Equatable, Sendable, Decodable {
    var id: String { "\(gdb)/\(sourceLayer)" }
    let gdb: String
    let sourceLayer: String
    let outputLayer: String
    let geometryType: String
    let sourceCount: Int
    let candidateCount: Int
    let outputCount: Int
    /// `written`, `empty`, `skipped` or `error`.
    let status: String
    let message: String
}

struct ClipResult: Equatable, Sendable, Decodable {
    let outputGeoPackage: String
    let summaryCsv: String
    let layers: [ClipLayerResult]
    let writtenLayerCount: Int

    var outputGeoPackageURL: URL { URL(fileURLWithPath: outputGeoPackage) }
    var summaryCsvURL: URL { URL(fileURLWithPath: summaryCsv) }
}
