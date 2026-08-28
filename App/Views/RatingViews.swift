import SwiftUI

/// Đúng / Sai control for one layer or feature. Stores locally only.
struct RatingControl: View {
    @EnvironmentObject private var ratings: RatingStore
    let key: String

    var body: some View {
        let current = ratings.verdict(for: key)
        HStack(spacing: 6) {
            button(.correct, "Đúng", "hand.thumbsup", .green, current)
            button(.wrong, "Sai", "hand.thumbsdown", .red, current)
        }
    }

    private func button(_ verdict: RatingStore.Verdict, _ title: String, _ icon: String,
                        _ tint: Color, _ current: RatingStore.Verdict?) -> some View {
        Button {
            ratings.set(current == verdict ? nil : verdict, for: key)
        } label: {
            Label(title, systemImage: current == verdict ? "\(icon).fill" : icon)
                .font(.caption2)
        }
        .buttonStyle(.bordered)
        .tint(current == verdict ? tint : .gray)
    }
}

/// The "?" next to an evaluation section (text from docs/08).
struct RatingHelpButton: View {
    @State private var show = false

    var body: some View {
        Button { show = true } label: { Image(systemName: "questionmark.circle") }
            .buttonStyle(.plain)
            .popover(isPresented: $show) {
                Text("Đánh giá kết quả trích xuất theo từng layer hoặc đối tượng. "
                     + "Chọn “Đúng” nếu hình học và thuộc tính phù hợp với vùng đã chọn; "
                     + "chọn “Sai” nếu kết quả bị thiếu, thừa hoặc không chính xác. "
                     + "Đánh giá không làm thay đổi dữ liệu đã trích xuất.")
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: 320)
                    .presentationCompactAdaptation(.popover)
            }
    }
}
