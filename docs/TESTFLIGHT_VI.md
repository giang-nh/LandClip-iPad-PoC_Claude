# Chạy LandClip iPad PoC trên iPad qua TestFlight

Hướng dẫn này dành cho trường hợp **chỉ có iPad, không có máy Mac**. Toàn bộ build
chạy trên GitHub Actions (máy ảo macOS), rồi đẩy lên TestFlight để cài về iPad.

Mọi thao tác dưới đây làm được từ Safari trên iPad.

---

## 0. Điều kiện bắt buộc

- **Apple Developer Program — 99 USD/năm.** Đây là chi phí không tránh được: Apple
  không cho cài app tự làm lên iPad (không jailbreak) nếu không có tài khoản này
  hoặc một máy Mac. Đăng ký tại <https://developer.apple.com/programs/enroll/>
  (cần Apple ID có bật 2FA; duyệt thường 24–48 giờ).
- Tài khoản GitHub sở hữu repo `giang-nh/LandClip-iPad-PoC_Claude`.

---

## 1. Tạo App Identifier

1. Vào <https://developer.apple.com/account/resources/identifiers/list>
2. Nút **+** → **App IDs** → **App** → Continue
3. Description: `LandClip iPad PoC`
4. Bundle ID: chọn **Explicit**, nhập đúng:
   `com.giangnh.landclip.ipad.poc`
5. Capabilities: không cần bật gì thêm. **Continue → Register**.

## 2. Tạo bản ghi App trong App Store Connect

1. Vào <https://appstoreconnect.apple.com/apps>
2. **+** → **New App**
3. Platforms: **iOS** · Name: `LandClip iPad PoC` (tên phải là duy nhất trên toàn
   App Store — nếu trùng thì thêm hậu tố, ví dụ `LandClip iPad PoC GN`)
4. Primary Language: Vietnamese · Bundle ID: chọn `com.giangnh.landclip.ipad.poc`
5. SKU: gõ bất kỳ, ví dụ `landclip-ipad-poc`
6. User Access: Full Access · **Create**

Không cần điền gì thêm ở phần App Store (chưa phát hành, chỉ dùng TestFlight nội bộ).

## 3. Tạo App Store Connect API Key

1. Vào <https://appstoreconnect.apple.com/access/integrations/api>
   (mục **Integrations → App Store Connect API**, tab **Team Keys**)
2. **Generate API Key** (hoặc **+**)
3. Name: `github-actions` · Access: **App Manager** · **Generate**
4. Ghi lại:
   - **Issuer ID** (chuỗi UUID hiển thị phía trên bảng) → dùng cho secret `APPSTORE_ISSUER_ID`
   - **KEY ID** (cột Key ID của dòng vừa tạo) → secret `APPSTORE_KEY_ID`
5. Bấm **Download** ở dòng key để tải file `AuthKey_XXXXXXXXXX.p8`.
   ⚠️ Chỉ tải được **một lần**. Lưu file này an toàn (ví dụ app Files → iCloud Drive).

## 4. Lấy Team ID

Vào <https://developer.apple.com/account> → mục **Membership details** →
**Team ID** (10 ký tự chữ + số) → secret `APPLE_TEAM_ID`.

## 5. Thêm secrets vào GitHub

1. Vào `https://github.com/giang-nh/LandClip-iPad-PoC_Claude/settings/secrets/actions`
2. **New repository secret** cho từng mục:

   | Name | Giá trị |
   |---|---|
   | `APPLE_TEAM_ID` | Team ID ở bước 4 |
   | `APPSTORE_ISSUER_ID` | Issuer ID ở bước 3 |
   | `APPSTORE_KEY_ID` | Key ID ở bước 3 |
   | `APPSTORE_PRIVATE_KEY` | **Toàn bộ nội dung** file `AuthKey_XXXX.p8` — mở bằng app Files (giữ → Quick Look / hoặc mở bằng app soạn thảo text), copy hết kể cả dòng `-----BEGIN PRIVATE KEY-----` và `-----END PRIVATE KEY-----`, dán vào |

## 6. Chạy build lên TestFlight

1. Vào tab **Actions** của repo
2. Chọn workflow **TestFlight** ở cột trái → **Run workflow** → nhánh `main` → **Run workflow**
3. Chờ:
   - Lần đầu (chưa có cache XCFramework): ~20–30 phút build thư viện native + ~5 phút archive/upload
   - Các lần sau: ~5–10 phút
4. Job xanh = đã đẩy lên App Store Connect. Vào
   <https://appstoreconnect.apple.com/apps> → app → tab **TestFlight**.
   Bản build mới hiện trạng thái "Processing" (~5–15 phút) rồi chuyển sang sẵn sàng.

> Export Compliance đã set sẵn `ITSAppUsesNonExemptEncryption = NO` trong
> `project-native.yml` (app chỉ dùng HTTPS chuẩn cho tile bản đồ), nên thường Apple
> không hỏi. Nếu vẫn hỏi → chọn "không dùng mã hóa non‑exempt".

## 7. Thêm mình vào Internal Testing

1. App Store Connect → app → **TestFlight** → mục **Internal Testing** →
   **+** tạo group (ví dụ `Nội bộ`)
2. Thêm bản build vừa xử lý xong vào group
3. **+** ở **Testers** → chọn Apple ID của bạn (phải nằm trong Users and Access của team)

Internal testing **không cần Apple duyệt**, dùng được ngay.

## 8. Cài trên iPad

1. Cài app **TestFlight** từ App Store
2. Đăng nhập bằng đúng Apple ID đã thêm làm tester
3. Mở email mời hoặc mở thẳng TestFlight → thấy **LandClip iPad PoC** → **Install**
4. Mở app.

---

## 9. Kiểm thử từng tính năng

| Bước | Cách làm | Kỳ vọng |
|---|---|---|
| Đọc PPKX | Nút **Mở** (góc trên trái) → **Chọn file PPKX** → chọn `.ppkx` từ Files. Hoặc **Thử nhanh (dữ liệu mẫu)** dùng gói tổng hợp bundle sẵn | Hiện tên package + "N layer · M hỗ trợ clip", có progress khi giải nén |
| Vẽ AOI | Chạm lên bản đồ nhiều điểm (≥ 3) | Mỗi chạm thêm 1 chấm; đủ 3 điểm thì hiện polygon xanh; nút **↩︎** hoàn tác, **🗑** xóa |
| Nhập AOI từ file | Nút **doc.badge.plus** cạnh "AOI" → chọn `.geojson` / `.gpkg` / `.dxf` | Hiện tên file; bản đồ tắt chế độ vẽ |
| Trích xuất | Nút **Trích xuất N layer** | Card progress chạy theo phase/layer; xong thì tự mở màn kết quả |
| Kết quả | Danh sách layer + trạng thái (written/empty/skipped/error); ô tìm kiếm lọc theo tên | Số "Layer có kết quả" khớp mong đợi |
| Preview | Chạm layer trạng thái **written** | Mở bản đồ vệ tinh + geometry layer; bung hàng để xem thuộc tính; chạm để zoom |
| Chia sẻ | Nút share (góc trên phải màn kết quả) | Sheet chia sẻ `result.gpkg` + `result_summary.csv` → lưu vào Files / gửi đi |
| Hủy | Nút **Hủy** trong lúc chạy | Dừng ở ranh giới an toàn, quay lại trạng thái trước |

File `.ppkx` thật: chép vào app **Files** (iCloud Drive hoặc "On My iPad") trước,
rồi chọn trong app. Dữ liệu không rời khỏi iPad.

---

## 10. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| Archive lỗi `No profiles for 'com.giangnh...'` | Chưa tạo App ID (bước 1) đúng bundle id, hoặc API key chưa đủ quyền **App Manager** |
| `Authentication credentials are missing or invalid` | Secret `APPSTORE_PRIVATE_KEY` dán thiếu dòng BEGIN/END, hoặc sai `KEY_ID` / `ISSUER_ID` |
| Upload báo `bundle version ... already exists` | Chạy lại workflow (số build lấy theo số lần chạy, sẽ tăng); hoặc build cũ đang Processing |
| Build lên rồi nhưng TestFlight không thấy | Chờ Processing xong (tới 15 phút); kiểm tra email Apple xem có yêu cầu Export Compliance |
| Native build (bước "Build native XCFrameworks") lỗi | Xem log; đây là phần đã chạy xanh ở workflow `Native iPad PoC`, thường chỉ do cache — chạy lại |

Khi cần bản mới: chỉ việc **Run workflow** lại. Không phải làm lại bước 1–5.
