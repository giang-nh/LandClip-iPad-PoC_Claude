import SwiftUI

/// "Ghi nhận & Pháp lý" — the third-party components the PoC ships and their
/// licenses. Content mirrors THIRD_PARTY_LICENSES/ in the repo.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Component: Identifiable {
        let id = UUID()
        let name: String
        let version: String
        let license: String
        let url: String
    }

    private let components: [Component] = [
        .init(name: "GDAL", version: "3.11.4", license: "MIT",
              url: "https://github.com/OSGeo/gdal"),
        .init(name: "PROJ", version: "9.6.2", license: "MIT",
              url: "https://github.com/OSGeo/PROJ"),
        .init(name: "GEOS", version: "3.14.1", license: "LGPL-2.1-only",
              url: "https://github.com/libgeos/geos"),
        .init(name: "SQLite", version: "3.50.4", license: "Public Domain",
              url: "https://www.sqlite.org"),
        .init(name: "libarchive", version: "3.8.9", license: "BSD-2-Clause",
              url: "https://github.com/libarchive/libarchive"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Thư viện native") {
                    ForEach(components) { component in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(component.name).font(.headline)
                                Text(component.version).foregroundStyle(.secondary)
                                Spacer()
                                Text(component.license)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(component.url).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Dữ liệu hệ toạ độ") {
                    Text("proj.db và các bảng tham chiếu của PROJ/GDAL dẫn xuất từ EPSG Dataset "
                         + "(và ESRI, IGNF…). Sử dụng và phân phối lại theo EPSG Terms of Use, "
                         + "kèm ghi nguồn EPSG; không sửa đổi mà vẫn gọi là \"EPSG\".")
                        .font(.footnote)
                }

                Section("GEOS — LGPL-2.1") {
                    Text("GEOS phát hành theo LGPL-2.1. Toàn văn giấy phép của cả 5 thư viện "
                         + "nằm trong thư mục THIRD_PARTY_LICENSES/ của mã nguồn. Bản PoC này "
                         + "dùng cho đánh giá nội bộ; trước khi phân phối rộng, GEOS sẽ được "
                         + "liên kết động hoặc kèm bộ relink theo LGPL-2.1 §6.")
                        .font(.footnote)
                }

                Section {
                    LabeledContent("GIS engine",
                                   value: NativeGeodatabaseReader().isAvailable
                                   ? NativeGeodatabaseReader().engineVersion : "mock")
                }
            }
            .navigationTitle("Ghi nhận & Pháp lý")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
