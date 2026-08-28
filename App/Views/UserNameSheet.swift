import SwiftUI

/// First-launch / "đổi người dùng" name declaration. Not authentication — no
/// password, no email. The name is attached to ratings.
struct UserNameSheet: View {
    @EnvironmentObject private var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ví dụ: Nguyễn Văn A", text: $draft)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Tên người dùng")
                } footer: {
                    Text("Chỉ để ghi nhận ai thực hiện — không phải đăng nhập, không mật khẩu. "
                         + "Tên được lưu trên máy và gắn vào phần đánh giá kết quả.")
                }
            }
            .navigationTitle("Khai báo người dùng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") {
                        profile.setName(draft)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if profile.hasName {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Huỷ") { dismiss() }
                    }
                }
            }
            .onAppear { draft = profile.name }
        }
        .interactiveDismissDisabled(!profile.hasName)
    }
}
