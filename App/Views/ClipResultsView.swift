import SwiftUI

struct ClipResultsView: View {
    let result: ClipResult
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

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
                }
                Section("Chi tiết") {
                    ForEach(filtered) { layer in
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

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "written": return .green
            case "empty": return .secondary
            case "skipped": return .orange
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
