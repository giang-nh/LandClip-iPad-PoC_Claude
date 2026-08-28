# Kế hoạch PoC đọc PPKX trực tiếp trên iPad

## Phạm vi

PoC chứng minh chuỗi xử lý native trên iPad. Không dùng backend, không gửi PPKX lên
cloud và không phụ thuộc LandClip Windows.

## Giai đoạn 0 — scaffold

- SwiftUI app chỉ dành cho iPad.
- Chọn `.ppkx` bằng document picker.
- Model trạng thái scan và unit test.
- C ABI để nối C++ engine.
- CI build bằng macOS simulator.

## Giai đoạn 1 — native dependencies

- Build XCFramework cho GDAL, PROJ, GEOS, SQLite và thư viện 7z.
- Chỉ bật các driver OpenFileGDB, GPKG và GeoJSON.
- Kiểm tra license của dependency trước khi phân phối.

### Trạng thái tích hợp

- [x] C ABI không để kiểu C++/GDAL lọt sang Swift.
- [x] Adapter OpenFileGDB chỉ mở read-only và trả layer, geometry, CRS, feature count.
- [x] Swift adapter quản lý ownership của chuỗi native và decode catalog.
- [x] Có script CI build GDAL/PROJ/GEOS/SQLite cho device + simulator.
- [x] Có cấu hình link XCFramework và bật `LANDCLIP_WITH_GDAL=1`.
- [x] Copy GDAL/PROJ resource data vào app bundle và cấu hình runtime search path.
- [x] Xác minh workflow native build xanh trên GitHub macOS runner.
- [x] Thêm fixture `.gdb` công khai và integration test OpenFileGDB thật.
- [x] Ghi nhận phiên bản và license chính xác của binary được chốt —
  [`DEPENDENCIES.md`](DEPENDENCIES.md).

Không bật macro trước khi XCFramework được link: nhánh fallback là chủ ý để CI
scaffold vẫn kiểm tra được Swift/C ABI, nhưng không được xem là pass Giai đoạn 1.

Workflow `Native iPad PoC` đã chạy xanh trên `macos-15` / Xcode 16.4: build 5
XCFramework (GDAL 3.11.4, PROJ 9.6.2, GEOS 3.14.1, SQLite 3.50.4, libarchive
3.8.9) cho `ios-arm64` + `ios-arm64-simulator`, link vào app với
`LANDCLIP_WITH_GDAL=1`, và 4 unit test pass — trong đó `testNativeOpenFileGDBCatalog`
đọc `.gdb` thật bằng OpenFileGDB và `testNativePPKXEndToEnd` chạy trọn pipeline
copy → giải nén ZIP → tìm `.gdb` → catalog.

Đã bổ sung: SHA-256 pin cho 5 nguồn tải trong build script, driver GeoJSON,
[`THIRD_PARTY_LICENSES/`](../THIRD_PARTY_LICENSES/) (full text + written offer GEOS),
và quyết định GEOS/LGPL cho bản PoC (giữ static, không phân phối — điều kiện phân
phối ghi trong [`DEPENDENCIES.md`](DEPENDENCIES.md)). Việc chuyển sang phân phối
thật (GEOS động hoặc relink-kit, màn Acknowledgements) để lại cho Giai đoạn 3.

## Giai đoạn 2 — catalog thật

- [x] Sao chép PPKX vào sandbox theo luồng streaming (`NativePackageScanner.copyStreaming`).
- [x] Giải nén vào `Library/Caches` (libarchive, hỗ trợ ZIP + 7z).
- [x] Tìm mọi `.gdb` và liệt kê layer, geometry, CRS, feature count.
- [x] Hủy scan an toàn và dọn file tạm (`CancelFlag` + dọn `jobDirectory`).
- [x] Progress theo phase (`copy` / `extract` / `catalog`) + số mục giải nén.

`prepare()` giữ lại thư mục đã giải nén cho Giai đoạn 3 dùng lại (không giải nén 2 lần);
caller chịu trách nhiệm dọn.

## Giai đoạn 3 — clip theo AOI

Port `engine.py` của bản Windows sang iPad. Toàn bộ vòng lặp chạy trong C++
(`landclip_clip_package_json`), Swift lo UI + file + cancel.

- [x] Nạp AOI (GeoJSON/GeoPackage, 1+ polygon, union, `MakeValid`).
- [x] Với mỗi layer hỗ trợ: transform AOI → CRS layer, lọc bbox (`SetSpatialFilter`),
  intersect chính xác (`OGR_G_Intersects` + `OGR_G_Intersection`).
- [x] **Point/MultiPoint = Select** (giữ nguyên), **Line/Polygon = Clip** (cắt theo AOI).
- [x] Giữ nguyên thuộc tính (`OGR_F_SetFrom`), ghi 1 layer GeoPackage / 1 layer nguồn.
- [x] Fault isolation: lỗi 1 layer ghi vào summary, không sập job.
- [x] Cancel theo ranh giới layer, xoá output dở.
- [x] Summary CSV (gdb, source_layer, output_layer, geometry_type, counts, status, message).
- [x] Integration test trên CI (`testNativeClipPipeline`): Select 2 điểm, clip 1 line + 1 polygon.
- [x] UI: MapKit (ảnh vệ tinh Esri) vẽ AOI polygon bằng chạm điểm → clip có progress →
  danh sách summary + filter → `ShareLink` GeoPackage + CSV.
- [x] Preview layer kết quả trên bản đồ + bảng thuộc tính (`LayerPreviewView`).
- [x] AOI từ file import: GeoJSON / GeoPackage / **DXF** (driver GDAL DXF, closed
  polyline → polygon, đọc WKT nhúng trong comment `999` như bản Windows).
- [x] Màn "Ghi nhận & Pháp lý" (`AcknowledgementsView`).

### Ngang tính năng với bản Windows (bổ sung sau)

- [x] Chọn / bỏ chọn từng layer trước khi clip (`LayerSelectionView`, options
  `{"layers":[...]}` cho engine).
- [x] Diện tích + chu vi AOI (reproject sang UTM zone của centroid như
  `estimate_utm_crs`).
- [x] Vẽ AOI: chạm thêm đỉnh / **chạm lên đỉnh để xoá** / **chế độ hình chữ nhật** /
  toggle vệ tinh ↔ đường phố.
- [x] Bảng đếm realtime từng layer trong lúc clip (nguồn → ứng viên → kết quả).
- [x] **Đánh giá Đúng/Sai** theo layer và theo đối tượng (`RatingStore`, lưu on-device)
  + tooltip trợ giúp.
- [x] **Tự tiếp tục sau khi dừng**: khoá = package + AOI + layer + processor version;
  giữ GeoPackage khi dừng, lần chạy sau append + `skipLayers`; nút "Chạy lại từ đầu".
- [x] **Khai báo tên người dùng** lần đầu (local, không auth), bắt buộc trước khi clip.
- [x] **Nhật ký hoạt động on-device** (`audit.jsonl`) + PPKX SHA-256 + `AuditLogView`.

### Cố ý KHÔNG port (giữ nguyên tắc on-device)

- Audit đẩy lên Supabase / hàng đợi offline — `AuditSink` để ngỏ cho bản opt-in.
- Upload PPKX khi báo lỗi — gửi data ra ngoài.
- Auto-update Velopack — TestFlight/App Store lo.
- Test đối chứng ArcGIS Pro — cần ArcGIS + máy Windows, xem
  [`ARCGIS_VALIDATION_VI.md`](ARCGIS_VALIDATION_VI.md).

- [x] Đường phát hành lên iPad khi không có Mac: workflow `TestFlight` +
  [`TESTFLIGHT_VI.md`](TESTFLIGHT_VI.md).
- [x] Verify luồng UI trong simulator: workflow `UI preview` tự chạy hết luồng
  (mở → catalog → AOI → clip → kết quả đúng points 2 / lines 1 / polygons 1 →
  preview layer) và xuất screenshots + video.
- [ ] Verify trên iPad thật (làm theo `TESTFLIGHT_VI.md` — cần Apple Developer account).
- [ ] Chuyển GEOS sang framework động trước bản phân phối
  ([`GEOS_DYNAMIC_PLAN.md`](GEOS_DYNAMIC_PLAN.md)).

## Tiêu chí pass

1. Đọc đúng số geodatabase và layer so với tool Windows/ArcGIS.
2. Không đưa dữ liệu ra khỏi iPad. — ✅ toàn bộ chạy on-device, không network trừ tile nền.
3. Peak memory không tăng theo toàn bộ kích thước layer. — ✅ đọc feature theo iterator,
   không nạp cả layer; catalog chỉ đọc metadata.
4. Scan có progress và cancel. — ✅
5. File tạm được dọn sau khi hoàn thành hoặc hủy. — ✅
