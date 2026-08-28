import SwiftUI

struct ClipResultsView: View {
    let result: ClipResult
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var jobID: String {
        result.outputGeoPackageURL.deletingLastPathComponent().lastPathComponent
    }

    private var filtered: [ClipLayerResult] {
        guard !filter.isEmpty else { return result.layers }
        let needle = filter.lowercased()
        return result.layers.filter {
            $0.sourceLayer.lowercased().contains(needle) || $0.gdb.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Layer có kết quả", value: "\(result.writtenLayerCount)")
                    LabeledContent("Tổng layer xử lý", value: "\(result.layers.count)")
                    if result.aoiAreaSqMeters > 0 {
                        LabeledContent("Diện tích AOI", value: Self.areaText(result.aoiAreaSqMeters))
                        LabeledContent("Chu vi AOI", value: Self.lengthText(result.aoiPerimeterMeters))
                    }
                }
                Section {
                    ForEach(filtered) { layer in
                        VStack(alignment: .leading, spacing: 6) {
                            if layer.status == "written" {
                                NavigationLink {
                                    LayerPreviewView(
                                        datasetURL: result.outputGeoPackageURL,
                                        layerName: layer.outputLayer,
                                        jobID: jobID
                                    )
                                } label: { row(layer) }
                                RatingControl(key: "\(jobID)/layer/\(layer.outputLayer)")
                            } else {
                                row(layer)
                            }
                        }
                    }
                } header: {
                    HStack { Text("Đánh giá kết quả"); RatingHelpButton() }
                }
            }
            .searchable(text: $filter, prompt: "Lọc theo layer hoặc geodatabase")
            .navigationTitle("Kết quả trích xuất")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        items: [result.outputGeoPackageURL, result.summaryCsvURL]
                    ) { url in
                        SharePreview(url.lastPathComponent)
                    }
                }
            }
        }
    }

    private func row(_ layer: ClipLayerResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(layer.sourceLayer).font(.headline)
                Spacer()
                statusBadge(layer.status)
            }
            Text("\(layer.gdb) · \(layer.geometryType)")
                .font(.caption).foregroundStyle(.secondary)
            Text("nguồn \(layer.sourceCount) · ứng viên \(layer.candidateCount) · kết quả \(layer.outputCount)")
                .font(.caption2).foregroundStyle(.secondary)
            if !layer.message.isEmpty {
                Text(layer.message).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    static func areaText(_ squareMeters: Double) -> String {
        squareMeters >= 1_000_000
            ? String(format: "%.2f km²", squareMeters / 1_000_000)
            : String(format: "%.0f m²", squareMeters)
    }

    static func lengthText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "written": return .green
            case "empty": return .secondary
            case "skipped": return .orange
            case "reused": return .blue
            default: return .red
            }
        }()
        return Text(status)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
