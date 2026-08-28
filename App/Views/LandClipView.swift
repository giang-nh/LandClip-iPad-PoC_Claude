import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct LandClipView: View {
    @StateObject private var model = LandClipViewModel()
    @State private var importingPackage = false
    @State private var importingAOI = false
    @State private var showResults = false
    @State private var showAcknowledgements = false
    @State private var showLayerSelection = false
    @State private var satellite = true
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 16.0, longitude: 106.0),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
    )

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                controlPanel
            }
            .navigationTitle("LandClip iPad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            importingPackage = true
                        } label: {
                            Label("Chọn file PPKX", systemImage: "folder")
                        }
                        #if DEBUG
                        if LandClipViewModel.bundledSamplePackage != nil {
                            Button {
                                model.openDemo()
                            } label: {
                                Label("Thử nhanh (dữ liệu mẫu)", systemImage: "sparkles")
                            }
                        }
                        #endif
                    } label: {
                        Label("Mở", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.catalog != nil {
                        Button("Bắt đầu lại", role: .destructive) { model.reset() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAcknowledgements = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $importingPackage,
                allowedContentTypes: [UTType(filenameExtension: "ppkx") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    model.openPackage(url)
                }
            }
            .fileImporter(
                isPresented: $importingAOI,
                allowedContentTypes: [.json,
                                      UTType(filenameExtension: "geojson") ?? .json,
                                      UTType(filenameExtension: "gpkg") ?? .data,
                                      UTType(filenameExtension: "dxf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    model.importAOI(url)
                }
            }
            .sheet(isPresented: $showResults) {
                if let result = model.result {
                    ClipResultsView(result: result)
                }
            }
            .sheet(isPresented: $showAcknowledgements) {
                AcknowledgementsView()
            }
            .sheet(isPresented: $showLayerSelection) {
                LayerSelectionView(model: model)
            }
            .onChange(of: model.stage) { _, stage in
                if stage == .done { showResults = true }
            }
            .overlay {
                if !model.engineAvailable {
                    ContentUnavailableView(
                        "Chưa có GIS engine native",
                        systemImage: "gearshape.2",
                        description: Text("Bản build này chưa bật GDAL (LANDCLIP_WITH_GDAL=0).")
                    )
                }
            }
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if model.aoiVertices.count >= 3 {
                    MapPolygon(coordinates: model.aoiVertices)
                        .foregroundStyle(.blue.opacity(0.20))
                        .stroke(.blue, lineWidth: 2)
                } else if model.aoiVertices.count == 2 {
                    MapPolyline(coordinates: model.aoiVertices)
                        .stroke(.blue, lineWidth: 2)
                }
                if let anchor = model.rectangleAnchor {
                    Annotation("Góc 1", coordinate: anchor) {
                        Image(systemName: "plus.viewfinder").foregroundStyle(.blue)
                    }
                }
                ForEach(Array(model.aoiVertices.enumerated()), id: \.offset) { index, coordinate in
                    Annotation("Điểm \(index + 1)", coordinate: coordinate) {
                        Circle()
                            .fill(.white).stroke(.blue, lineWidth: 3)
                            .frame(width: 16, height: 16)
                            .onTapGesture { model.deleteVertex(at: index) }
                    }
                }
            }
            .mapStyle(satellite ? .imagery(elevation: .flat) : .standard)
            .onTapGesture(coordinateSpace: .local) { point in
                handleMapTap(point, proxy: proxy)
            }
            .overlay(alignment: .topTrailing) { mapControls }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            Button {
                satellite.toggle()
            } label: {
                Image(systemName: satellite ? "map" : "globe.americas.fill")
            }
            if model.canDraw {
                Button {
                    model.drawMode = model.drawMode == .polygon ? .rectangle : .polygon
                    model.clearAOIDrawing()
                } label: {
                    Image(systemName: model.drawMode == .polygon ? "hexagon" : "rectangle")
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }

    private func handleMapTap(_ point: CGPoint, proxy: MapProxy) {
        guard model.canDraw, let coordinate = proxy.convert(point, from: .local) else { return }
        // Tap near an existing vertex deletes it.
        for (index, vertex) in model.aoiVertices.enumerated() {
            if let screen = proxy.convert(vertex, to: .local), hypot(screen.x - point.x, screen.y - point.y) < 22 {
                model.deleteVertex(at: index)
                return
            }
        }
        switch model.drawMode {
        case .polygon:
            model.aoiVertices.append(coordinate)
        case .rectangle:
            if let anchor = model.rectangleAnchor {
                model.setRectangle(anchor, coordinate)
            } else {
                model.clearAOIDrawing()
                model.rectangleAnchor = coordinate
            }
        }
    }

    @ViewBuilder
    private var controlPanel: some View {
        VStack(spacing: 12) {
            switch model.stage {
            case .idle:
                hint("Chọn một file .ppkx để bắt đầu.")
            case let .preparing(name):
                progressCard(title: "Đang mở \(name)")
            case .ready:
                catalogSummary
                aoiControls
                clipButton
            case .clipping:
                progressCard(title: "Đang trích xuất")
            case .done:
                Button {
                    showResults = true
                } label: {
                    Label("Xem kết quả", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                aoiControls
                clipButton
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var catalogSummary: some View {
        HStack {
            if let catalog = model.catalog {
                VStack(alignment: .leading) {
                    Text(catalog.packageName).font(.headline)
                    Text("\(catalog.layers.count) layer · chọn \(model.selectedLayerCount)/\(model.supportedLayerCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                showLayerSelection = true
            } label: {
                Label("Chọn layer", systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var aoiControls: some View {
        if let name = model.importedAOIName {
            HStack {
                Label(name, systemImage: "doc")
                    .font(.subheadline).lineLimit(1)
                Spacer()
                Button("Bỏ", role: .destructive) { model.clearImportedAOI() }
                    .buttonStyle(.bordered)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AOI \(model.drawMode == .rectangle ? "hình chữ nhật" : "đa giác"): \(model.aoiVertices.count) điểm")
                        .font(.subheadline)
                    Text(model.drawMode == .rectangle
                         ? "Chạm 2 góc đối diện"
                         : "Chạm để thêm · chạm lên đỉnh để xoá")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    importingAOI = true
                } label: { Image(systemName: "doc.badge.plus") }
                Button {
                    if !model.aoiVertices.isEmpty { model.aoiVertices.removeLast() }
                } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(model.aoiVertices.isEmpty || model.drawMode == .rectangle)
                Button {
                    model.clearAOIDrawing()
                } label: { Image(systemName: "trash") }
                    .disabled(model.aoiVertices.isEmpty && model.rectangleAnchor == nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private var clipButton: some View {
        Button {
            model.runClip()
        } label: {
            Text(model.hasAOI
                 ? "Trích xuất \(model.selectedLayerCount) layer"
                 : "Chạm lên bản đồ để vẽ AOI (≥ 3 điểm) hoặc nhập file")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canClip)
    }

    private func progressCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                Text(model.progress.phase.isEmpty ? title : model.progress.phase)
                    .font(.headline)
                Spacer()
                Button("Hủy") { model.cancel() }
                    .buttonStyle(.bordered)
            }
            if !model.progress.detail.isEmpty {
                Text(model.progress.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !model.liveRows.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.liveRows.reversed()) { row in
                            HStack {
                                Image(systemName: row.status == "running" ? "circle.dotted" : "checkmark.circle")
                                    .foregroundStyle(row.status == "running" ? .secondary : .green)
                                    .font(.caption2)
                                Text(row.layer).font(.caption).lineLimit(1)
                                Spacer()
                                Text(row.status == "running"
                                     ? "nguồn \(row.sourceCount)"
                                     : "\(row.candidateCount) → \(row.outputCount)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
}
