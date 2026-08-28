import SwiftUI
import MapKit

/// Map + attribute table for one written output layer.
struct LayerPreviewView: View {
    let datasetURL: URL
    let layerName: String
    var jobID: String = ""

    @State private var features: [PreviewFeature] = []
    @State private var selectedID: PreviewFeature.ID?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            map
                .frame(minHeight: 260)
            Divider()
            content
        }
        .navigationTitle(layerName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(features) { feature in
                let selected = feature.id == selectedID
                ForEach(Array(feature.shapes.enumerated()), id: \.offset) { _, shape in
                    switch shape {
                    case let .point(coordinate):
                        Marker(feature.title, coordinate: coordinate)
                            .tint(selected ? .yellow : .blue)
                    case let .line(coordinates):
                        MapPolyline(coordinates: coordinates)
                            .stroke(selected ? .yellow : .blue, lineWidth: selected ? 5 : 3)
                    case let .polygon(coordinates):
                        MapPolygon(coordinates: coordinates)
                            .foregroundStyle((selected ? Color.yellow : Color.blue).opacity(0.25))
                            .stroke(selected ? .yellow : .blue, lineWidth: 2)
                    }
                }
            }
        }
        .mapStyle(.imagery(elevation: .flat))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Đang đọc layer…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView("Không xem được layer", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
        } else if features.isEmpty {
            ContentUnavailableView("Layer rỗng", systemImage: "square.dashed")
        } else {
            List {
                Text("\(features.count) đối tượng")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(features) { feature in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { selectedID == feature.id },
                            set: { expanded in
                                selectedID = expanded ? feature.id : nil
                                if expanded, let region = feature.boundingRegion {
                                    withAnimation { camera = .region(region) }
                                }
                            }
                        )
                    ) {
                        ForEach(feature.attributes, id: \.key) { attribute in
                            LabeledContent(attribute.key, value: attribute.value.isEmpty ? "—" : attribute.value)
                                .font(.caption)
                        }
                        if !jobID.isEmpty {
                            RatingControl(key: "\(jobID)/feature/\(layerName)/\(feature.id)")
                                .padding(.top, 4)
                        }
                    } label: {
                        Text(feature.title).font(.subheadline)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        let url = datasetURL
        let name = layerName
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try NativeLayerReader().rawGeoJSON(datasetURL: url, layerName: name)
            }.value
            features = PreviewFeature.decodeCollection(data)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private extension PreviewFeature {
    var title: String {
        if let first = attributes.first(where: { !$0.value.isEmpty }) {
            return "\(first.key): \(first.value)"
        }
        return "Đối tượng #\(id + 1)"
    }
}
