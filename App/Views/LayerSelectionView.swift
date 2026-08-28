import SwiftUI

/// Pick which supported layers to clip. Unsupported layers are shown but locked.
struct LayerSelectionView: View {
    @ObservedObject var model: LandClipViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var layers: [LayerInfo] { model.catalog?.layers ?? [] }

    private var groups: [(gdb: String, layers: [LayerInfo])] {
        let needle = filter.lowercased()
        let matched = needle.isEmpty
            ? layers
            : layers.filter { $0.name.lowercased().contains(needle) || $0.geodatabase.lowercased().contains(needle) }
        return Dictionary(grouping: matched, by: \.geodatabase)
            .map { (gdb: $0.key, layers: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.gdb < $1.gdb }
    }

    private func key(_ layer: LayerInfo) -> String {
        "\(layer.geodatabase.replacingOccurrences(of: ".gdb", with: ""))::\(layer.name)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Chọn tất cả") { model.selectAllLayers() }
                        Spacer()
                        Button("Bỏ chọn tất cả") { model.deselectAllLayers() }
                    }
                    .font(.subheadline)
                }
                ForEach(groups, id: \.gdb) { group in
                    Section(group.gdb) {
                        ForEach(group.layers) { layer in
                            let supported = LandClipViewModel.isSupported(layer.geometryType)
                            let selected = supported && !model.deselectedLayerKeys.contains(key(layer))
                            Button {
                                if supported { model.toggleLayer(key(layer)) }
                            } label: {
                                HStack {
                                    Image(systemName: selected ? "checkmark.circle.fill"
                                          : (supported ? "circle" : "minus.circle"))
                                        .foregroundStyle(selected ? .blue : .secondary)
                                    VStack(alignment: .leading) {
                                        Text(layer.name)
                                        Text("\(layer.geometryType) · \(layer.featureCount.map(String.init) ?? "?") feature")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !supported {
                                        Text("không hỗ trợ").font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!supported)
                        }
                    }
                }
            }
            .searchable(text: $filter, prompt: "Tìm layer")
            .navigationTitle("Chọn layer (\(model.selectedLayerCount)/\(model.supportedLayerKeys.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } }
            }
        }
    }
}
