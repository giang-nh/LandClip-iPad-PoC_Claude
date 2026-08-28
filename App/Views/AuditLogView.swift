import SwiftUI

/// Shows the on-device audit trail. Nothing here is sent anywhere.
struct AuditLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [AuditEvent] = []

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Nhật ký hoạt động lưu trên máy (Application Support/audit.jsonl). "
                         + "Không gửi đi đâu. Không chứa hình học hay thuộc tính dữ liệu.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.kind).font(.subheadline.bold())
                            Spacer()
                            Text(Self.time.string(from: event.timestamp))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if !event.userName.isEmpty {
                            Text("người dùng: \(event.userName)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let pkg = event.packageName {
                            Text(pkg).font(.caption2).foregroundStyle(.secondary)
                        }
                        detail(event)
                    }
                }
            }
            .navigationTitle("Nhật ký hoạt động")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onAppear { events = LocalFileAuditSink.shared.readAll() }
        }
    }

    @ViewBuilder
    private func detail(_ event: AuditEvent) -> some View {
        let parts: [String] = [
            event.layerCount.map { "\($0) layer" },
            event.selectedLayers.map { "chọn \($0)" },
            event.writtenLayers.map { "\($0) có kết quả" },
            event.durationMs.map { "\($0) ms" },
            event.message,
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
