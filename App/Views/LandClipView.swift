import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct LandClipView: View {
    @StateObject private var model = LandClipViewModel()
    @State private var importingPackage = false
    @State private var importingAOI = false
    @State private var showResults = false

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
                                if let url = LandClipViewModel.bundledSamplePackage {
                                    model.openPackage(url)
                                }
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
            Map {
                if model.aoiVertices.count >= 3 {
                    MapPolygon(coordinates: model.aoiVertices)
                        .foregroundStyle(.blue.opacity(0.20))
                        .stroke(.blue, lineWidth: 2)
                } else if model.aoiVertices.count == 2 {
                    MapPolyline(coordinates: model.aoiVertices)
                        .stroke(.blue, lineWidth: 2)
                }
                ForEach(Array(model.aoiVertices.enumerated()), id: \.offset) { index, coordinate in
                    Annotation("Điểm \(index + 1)", coordinate: coordinate) {
                        Circle()
                            .fill(.white)
                            .stroke(.blue, lineWidth: 3)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .mapStyle(.imagery(elevation: .flat))
            .onTapGesture(coordinateSpace: .local) { point in
                guard model.canDraw, let coordinate = proxy.convert(point, from: .local) else { return }
                model.aoiVertices.append(coordinate)
            }
        }
        .ignoresSafeArea(edges: .bottom)
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
                    Text("\(catalog.layers.count) layer · \(model.supportedLayerCount) hỗ trợ clip")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
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
                Text("AOI: \(model.aoiVertices.count) điểm")
                    .font(.subheadline)
                Spacer()
                Button {
                    importingAOI = true
                } label: { Image(systemName: "doc.badge.plus") }
                Button {
                    if !model.aoiVertices.isEmpty { model.aoiVertices.removeLast() }
                } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(model.aoiVertices.isEmpty)
                Button {
                    model.aoiVertices.removeAll()
                } label: { Image(systemName: "trash") }
                    .disabled(model.aoiVertices.isEmpty)
            }
            .buttonStyle(.bordered)
        }
    }

    private var clipButton: some View {
        Button {
            model.runClip()
        } label: {
            Text(model.hasAOI
                 ? "Trích xuất \(model.supportedLayerCount) layer"
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
}
