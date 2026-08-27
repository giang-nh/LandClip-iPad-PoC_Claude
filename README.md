# LandClip iPad PoC

Project thử nghiệm độc lập để đánh giá khả năng đọc và xử lý `.ppkx` hoàn toàn trên
iPad. Project này không phụ thuộc source, binary hay runtime của LandClip Windows.

## Mục tiêu PoC đầu tiên

1. Chọn một file `.ppkx` từ ứng dụng Files.
2. Sao chép file vào sandbox của ứng dụng.
3. Giải nén package bằng thư viện native.
4. Tìm các thư mục `.gdb`.
5. Dùng GDAL/OpenFileGDB đọc danh sách layer.
6. Hiển thị catalog layer và số liệu hiệu năng.

Engine native chưa được nối ở scaffold đầu tiên. App dùng `MockPackageScanner` để
kiểm tra luồng UI và test trước khi build GDAL.

`GISCore` hiện đã có C ABI để mở một thư mục `.gdb` bằng đúng driver
`OpenFileGDB` và trả catalog JSON cho `NativeGeodatabaseReader`. Build mặc định
giữ `LANDCLIP_WITH_GDAL=0`, nên không vô tình báo thành công khi binary native
chưa được đóng gói. Khi thêm GDAL XCFramework, đặt `LANDCLIP_WITH_GDAL=1`, link
framework vào target `LandClipIPad`, và bảo đảm headers `gdal.h`, `ogr_api.h`,
`ogr_srs_api.h` nằm trong header search path.

Không cần máy Mac cục bộ để build native. Workflow `Native iPad PoC` chạy script
`scripts/build-native-xcframeworks.sh` trên GitHub macOS runner, cache bốn
XCFramework, generate project từ `project-native.yml`, rồi chạy unit test trên
iPad Simulator. Có thể chạy thủ công từ tab Actions bằng `workflow_dispatch`.

## Yêu cầu build

- macOS và Xcode phiên bản hiện hành.
- XcodeGen (`brew install xcodegen`).
- iPadOS deployment target 17.0 trở lên.

```bash
xcodegen generate
xcodebuild -project LandClipIPad.xcodeproj -scheme LandClipIPad \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' test
```

## Nguyên tắc

- Một job xử lý tại một thời điểm.
- Đọc feature theo batch, không nạp toàn bộ layer vào RAM.
- Lưu checkpoint sau mỗi layer.
- Tất cả dữ liệu nằm trên iPad, không gửi PPKX ra máy chủ.
- SwiftUI phụ trách UX; C/C++ phụ trách 7z, GDAL, PROJ và GEOS.

Xem [docs/POC_PLAN.md](docs/POC_PLAN.md) để biết tiêu chí nghiệm thu và trạng thái
tích hợp dependency.
