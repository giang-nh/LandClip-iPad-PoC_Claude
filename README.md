# LandClip iPad PoC

Bản thử nghiệm độc lập chứng minh: có thể đọc và **clip** một ArcGIS Project Package
(`.ppkx`) hoàn toàn **trên iPad**, không backend, không gửi dữ liệu ra cloud, không phụ
thuộc source/binary/runtime của LandClip Windows.

Port phần lõi của công cụ `landclip` (Windows) sang iPad: chọn 1 AOI → tự động clip mọi
vector layer trong `.ppkx` → xuất 1 GeoPackage nhiều layer + 1 CSV tổng hợp.

## Làm được gì

- **Đọc `.ppkx`**: copy streaming vào sandbox → giải nén (ZIP + 7z, libarchive) → tìm
  mọi `.gdb` → catalog layer (tên, geometry, CRS, feature count). Có progress + huỷ.
- **AOI**: vẽ đa giác / hình chữ nhật trên bản đồ vệ tinh (MapKit), hoặc nhập file
  **GeoJSON / GeoPackage / DXF** (DXF đọc WKT hệ toạ độ nhúng trong comment `999`).
- **Clip engine** (`landclip_clip_package_json`, chạy trọn trong C++ qua OGR):
  transform AOI sang CRS từng layer → lọc bbox → intersect chính xác →
  **Point/MultiPoint = Select**, **Line/Polygon = Clip** → giữ nguyên thuộc tính.
  Fault isolation (1 layer lỗi không sập job), huỷ theo ranh giới layer, `MakeValid`
  hình học lỗi.
- **Chọn / bỏ chọn** từng layer trước khi clip.
- **Kết quả**: danh sách tổng hợp + lọc text, diện tích/chu vi AOI, share GeoPackage + CSV
  ra Files, preview từng layer trên bản đồ + bảng thuộc tính.
- **Tự tiếp tục sau khi dừng** (append vào GeoPackage cũ, bỏ qua layer đã xong).
- **Đánh giá Đúng/Sai** theo layer và theo đối tượng (lưu on-device).
- **Khai báo tên người dùng** (local, không auth) + **nhật ký hoạt động on-device**
  (`audit.jsonl`, có SHA-256 của PPKX) — không gửi đi đâu.

Toàn bộ dữ liệu nằm trên iPad; chỉ ảnh nền bản đồ cần Internet.

## Kiến trúc

| Tầng | | |
|---|---|---|
| UI | SwiftUI + MapKit (`App/Views`, `App/ViewModels`) | chọn file, vẽ AOI, progress, kết quả, đánh giá |
| Cầu nối | C ABI thuần trong [`GISCore/Sources/GISCore.h`](GISCore/Sources/GISCore.h) | Swift chỉ thấy `char*`/`int`, không kiểu C++/GDAL nào lọt qua |
| Engine | C++ (`GISCore/Sources/GISCore.cpp`) | libarchive (giải nén), GDAL/OGR + GEOS + PROJ (đọc gdb, transform, clip, ghi GPKG) |

Hàm C ABI chính: `landclip_gis_copy_gdb_catalog_json` (catalog), `landclip_archive_extract_ppkx`
(giải nén), `landclip_clip_package_json` (clip), `landclip_read_layer_geojson` (preview).
Tất cả nhận callback progress/cancel dùng chung.

Build scaffold (`project.yml`) đặt `LANDCLIP_WITH_GDAL=0` + `MockPackageScanner` để CI
nhanh không cần binary native. Build native (`project-native.yml`) đặt
`LANDCLIP_WITH_GDAL=1`, link 5 XCFramework và chạy engine thật.

## CI / workflow (GitHub Actions, `macos-15` / Xcode 16.4)

| Workflow | Việc |
|---|---|
| `iPad PoC` (`ios.yml`) | build scaffold + unit test, chạy mọi push |
| `Native iPad PoC` (`native-ios.yml`) | build 5 XCFramework từ source (cache) + 10 unit test với GDAL thật |
| `UI preview` (`ui-preview.yml`) | chạy app trong iPad simulator, tự thao tác hết luồng, xuất **screenshots + video** (không cần tài khoản Apple) |
| `TestFlight` (`testflight.yml`) | archive + đẩy lên TestFlight qua App Store Connect API key (cần Apple Developer account — xem `docs/TESTFLIGHT_VI.md`) |

Không cần máy Mac cục bộ. Chạy các workflow thủ công từ tab **Actions**.

Build local (nếu có Mac):

```bash
xcodegen generate --spec project-native.yml   # cần Vendor/ đã có sẵn từ script
xcodebuild -project LandClipIPad.xcodeproj -scheme LandClipIPad \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -skip-testing:LandClipIPadUITests test
```

## Native dependencies

GDAL 3.11.4 · PROJ 9.6.2 · GEOS 3.14.1 · SQLite 3.50.4 · libarchive 3.8.9 — build static
cho `ios-arm64` + `ios-arm64-simulator` bằng
[`scripts/build-native-xcframeworks.sh`](scripts/build-native-xcframeworks.sh) (SHA-256
pin cho cả 5 nguồn). GDAL bật driver **OpenFileGDB + GPKG + GeoJSON + DXF**, runtime còn
giới hạn `OpenFileGDB` khi mở dataset.

Phiên bản + giấy phép + nghĩa vụ phân phối: [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md)
và [`THIRD_PARTY_LICENSES/`](THIRD_PARTY_LICENSES/).

## Tài liệu

- [`docs/POC_PLAN.md`](docs/POC_PLAN.md) — kế hoạch + trạng thái từng giai đoạn + tiêu chí pass
- [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md) — version + license native deps
- [`docs/TESTFLIGHT_VI.md`](docs/TESTFLIGHT_VI.md) — đưa app lên iPad khi không có Mac
- [`docs/GEOS_DYNAMIC_PLAN.md`](docs/GEOS_DYNAMIC_PLAN.md) — chuyển GEOS sang liên kết động (LGPL) trước khi phân phối
- [`docs/ARCGIS_VALIDATION_VI.md`](docs/ARCGIS_VALIDATION_VI.md) — quy trình đối chứng kết quả với ArcGIS Pro

## Nguyên tắc

- Một job xử lý tại một thời điểm.
- Đọc feature theo iterator, không nạp cả layer vào RAM.
- Lưu kết quả sau mỗi layer (resume).
- Tất cả dữ liệu nằm trên iPad, không gửi PPKX/geometry/thuộc tính ra máy chủ.
- SwiftUI phụ trách UX; C/C++ phụ trách giải nén, GDAL, PROJ, GEOS.
