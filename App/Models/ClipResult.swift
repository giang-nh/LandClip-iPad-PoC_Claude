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
    /// `written`, `empty`, `skipped`, `reused` or `error`.
    let status: String
    let message: String

    var key: String { "\(gdb)::\(sourceLayer)" }
}

struct ClipResult: Equatable, Sendable, Decodable {
    let outputGeoPackage: String
    let summaryCsv: String
    var layers: [ClipLayerResult]
    var writtenLayerCount: Int
    var cancelled: Bool = false
    var aoiAreaSqMeters: Double = 0
    var aoiPerimeterMeters: Double = 0

    var outputGeoPackageURL: URL { URL(fileURLWithPath: outputGeoPackage) }
    var summaryCsvURL: URL { URL(fileURLWithPath: summaryCsv) }

    /// Layer keys (`gdb::sourceLayer`) that reached a terminal state, for resume.
    var completedLayerKeys: [String] {
        layers.filter { ["written", "empty", "skipped", "reused"].contains($0.status) }.map(\.key)
    }

    /// Replaces this run's `reused` stubs with the real rows from a prior result.
    func merging(reusedFrom previous: ClipResult) -> ClipResult {
        var merged = self
        merged.layers = layers.map { row in
            guard row.status == "reused",
                  let old = previous.layers.first(where: { $0.key == row.key }) else { return row }
            return old
        }
        merged.writtenLayerCount = merged.layers.filter { $0.status == "written" }.count
        return merged
    }

    /// Rewrites the CSV to match `layers` (used after a resumed run).
    func rewriteCSV() {
        var text = "gdb,source_layer,output_layer,geometry_type,source_count,candidate_count,output_count,status,message\n"
        for layer in layers {
            let cells = [layer.gdb, layer.sourceLayer, layer.outputLayer, layer.geometryType,
                         String(layer.sourceCount), String(layer.candidateCount),
                         String(layer.outputCount), layer.status, layer.message]
            text += cells.map(Self.csvCell).joined(separator: ",") + "\n"
        }
        try? text.data(using: .utf8)?.write(to: summaryCsvURL, options: .atomic)
    }

    private static func csvCell(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
