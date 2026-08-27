import SwiftUI
import UniformTypeIdentifiers

struct PackageCatalogView: View {
    @StateObject private var model: PackageCatalogModel
    @State private var importing = false
    @State private var scanTask: Task<Void, Never>?

    init(model: PackageCatalogModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Thử nghiệm") {
                    Button("Chọn file PPKX") { importing = true }
                        .buttonStyle(.borderedProminent)
                }
                statusContent
            }
            .navigationTitle("LandClip iPad")
        } detail: {
            ContentUnavailableView(
                "Bản đồ sẽ được thêm sau PoC catalog",
                systemImage: "map",
                description: Text("Bước đầu xác minh khả năng đọc PPKX trực tiếp trên iPad.")
            )
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [UTType(filenameExtension: "ppkx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            scanTask?.cancel()
            scanTask = Task { await model.scan(url) }
        }
        .onDisappear { scanTask?.cancel() }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.state {
        case .idle:
            Text("Chưa chọn package").foregroundStyle(.secondary)
        case let .scanning(name):
            HStack {
                ProgressView()
                Text("Đang scan \(name)…")
                Spacer()
                Button("Hủy") { scanTask?.cancel() }
            }
        case let .ready(catalog):
            LabeledContent("Package", value: catalog.packageName)
            LabeledContent("Dung lượng", value: ByteCountFormatter.string(fromByteCount: catalog.packageSize, countStyle: .file))
            LabeledContent("Số layer", value: "\(catalog.layers.count)")
            ForEach(catalog.layers) { layer in
                VStack(alignment: .leading) {
                    Text(layer.name).font(.headline)
                    Text("\(layer.geodatabase) · \(layer.geometryType)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }
}
