# Native dependencies — phiên bản & license

**Cập nhật:** 2026-08-27
**Nguồn chốt phiên bản:** [`scripts/build-native-xcframeworks.sh`](../scripts/build-native-xcframeworks.sh)

PoC nối 5 thư viện native (build static, iOS `arm64` device + `arm64` simulator, đóng
thành XCFramework trong `Vendor/`). Tài liệu này ghi phiên bản chính xác được chốt và
đánh giá nghĩa vụ license **trước khi phân phối** ứng dụng — theo yêu cầu Giai đoạn 1
trong [`POC_PLAN.md`](POC_PLAN.md).

## Bảng tổng hợp

| Thư viện | Phiên bản chốt | License | SPDX | Nghĩa vụ khi phân phối |
|---|---|---|---|---|
| GDAL | 3.11.4 | MIT (kiểu X/MIT) | `MIT` | Kèm license + copyright notice |
| PROJ | 9.6.2 | MIT (trước đây "X/MIT") | `MIT` | Kèm license + copyright notice |
| GEOS | 3.14.1 | **LGPL-2.1-only** | `LGPL-2.1-only` | **Xem mục "GEOS / LGPL-2.1" bên dưới** |
| SQLite | 3.50.4 (amalgamation `3500400`, year `2025`) | Public Domain | — | Không |
| libarchive | 3.8.9 | BSD 2-Clause | `BSD-2-Clause` | Kèm license + copyright notice |

Tất cả đều phát hành trong năm 2025. Link release chính thức:

- GDAL: <https://github.com/OSGeo/gdal/releases/tag/v3.11.4>
- PROJ: <https://github.com/OSGeo/PROJ/releases/tag/9.6.2>
- GEOS: <https://github.com/libgeos/geos/releases/tag/3.14.1>
- SQLite: <https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip>
- libarchive: <https://github.com/libarchive/libarchive/releases/tag/v3.8.9>

## Cấu hình build (ảnh hưởng tới license)

Script build **tối giản** để giảm bề mặt license và kích thước:

- `GDAL_BUILD_OPTIONAL_DRIVERS=OFF`, `OGR_BUILD_OPTIONAL_DRIVERS=OFF` — tắt toàn bộ
  driver mặc định.
- Chỉ bật: `OGR_ENABLE_DRIVER_OPENFILEGDB=ON`, `OGR_ENABLE_DRIVER_GPKG=ON`.
  - Runtime còn giới hạn thêm bằng `allowed_drivers = {"OpenFileGDB"}` trong
    [`GISCore.cpp`](../GISCore/Sources/GISCore.cpp) khi mở dataset.
- `GDAL_USE_EXTERNAL_LIBS=OFF` — GDAL dùng bản nhúng nội bộ (json-c…) thay vì lib hệ
  thống, nên không kéo thêm license ngoài.
- libarchive: tắt hầu hết format/filter, chỉ giữ đủ để giải nén ZIP
  (`ENABLE_LZMA/BZip2/LZ4/ZSTD/OPENSSL/MBEDTLS/NETTLE/LIBXML2/EXPAT = OFF`).
- SQLite build với `SQLITE_OMIT_LOAD_EXTENSION=1`.

### Driver OpenFileGDB

`OpenFileGDB` là bản hiện thực **độc lập trong GDAL** (MIT), **không** chứa mã hay SDK
của Esri, không cần Esri FileGDB API. Đọc thẳng định dạng `.gdb` ở mức nhị phân. Không
phát sinh nghĩa vụ license với Esri.

## GEOS / LGPL-2.1 — điểm cần xử lý trước khi phân phối

GEOS là thư viện duy nhất **không** phải license permissive. Build hiện tại link GEOS
**static** (vào `libgdal.a` qua `GDAL_USE_GEOS=ON`, rồi vào binary app). LGPL-2.1 §6
yêu cầu: khi phân phối tác phẩm liên kết static với thư viện LGPL, phải cho phép người
dùng cuối **thay thế GEOS bằng bản khác và relink**, bằng một trong hai cách:

1. Dùng cơ chế shared library (GEOS là `.framework` động), **hoặc**
2. Kèm theo phần "work that uses the Library" ở dạng object code (`.o`) + script link,
   đủ để relink với GEOS khác.

Kèm theo: notice rõ ràng có dùng GEOS + 1 bản copy license LGPL-2.1.

### Đánh giá theo kênh phân phối

| Kênh | Vướng mắc | Xử lý |
|---|---|---|
| Nội bộ / ad-hoc / enterprise / TestFlight | Ít rủi ro pháp lý thực tế nhưng vẫn nên tuân thủ §6 | Cung cấp gói relink object code, hoặc chuyển GEOS sang framework động |
| App Store công khai | ĐKSD App Store áp thêm ràng buộc DRM → xung đột với GPL, LGPL "nhẹ" hơn nhưng vẫn cần thoả mãn quyền relink. Tiền lệ: VLC (LGPL) có trên App Store nhờ publish object-code relink kit | Phải chọn (1) hoặc (2) ở trên **trước khi submit** |

### Khuyến nghị cho PoC hiện tại

`GISCore.cpp` **chưa gọi hàm GEOS nào** — catalog chỉ đọc metadata layer
(name / geometry type / CRS / feature count), không cần phép toán hình học. Đề xuất:

- **Trước mắt:** build GDAL với `GDAL_USE_GEOS=OFF` và **bỏ GEOS XCFramework** khỏi
  `project-native.yml`. Loại bỏ hoàn toàn nghĩa vụ LGPL cho tới khi thực sự cần.
- **Khi làm spatial engine (Giai đoạn 3, clip theo AOI):** đưa GEOS trở lại dưới dạng
  **`.framework` động** (thoả LGPL §6 cách 1), hoặc dựng sẵn quy trình phát hành
  object-code relink kit.

> Quyết định giữ hay bỏ GEOS ở bản PoC này: **CHƯA CHỐT** — cần xác nhận kênh phân phối
> mục tiêu.

## Data files đi kèm bundle

Script copy `share/proj` và `share/gdal` từ bản build vào `Vendor/Resources/`, rồi app
bundle chúng và trỏ runtime search path (`landclip_gis_configure_data_paths`).

| Thư mục | Nội dung | License / điều khoản |
|---|---|---|
| `Vendor/Resources/proj` | `proj.db`, `proj.ini`, một số file cấu hình (KHÔNG có grid tải qua projsync — script đặt `BUILD_PROJSYNC=OFF`, `ENABLE_CURL=OFF`) | `proj.db` tổng hợp từ **EPSG Dataset** + ESRI + IGNF… — EPSG Dataset Terms of Use: được dùng & phân phối lại **kèm ghi nguồn**, không được sửa mà vẫn gọi là "EPSG". File còn lại theo license PROJ (MIT) |
| `Vendor/Resources/gdal` | Bảng CSV/GeoTIFF templates, header… của GDAL | Phần lớn MIT; một phần dữ liệu tham chiếu dẫn xuất từ EPSG (ghi nguồn như trên) |

Cần đưa ghi nguồn EPSG vào phần "Acknowledgements / Legal" của app.

## Khoảng trống cần khắc phục

1. **Chưa verify checksum** — `scripts/build-native-xcframeworks.sh` tải tarball bằng
   `curl` không kiểm SHA256. Build không tái lập được và có rủi ro supply-chain. Nên
   pin SHA256 cho cả 5 nguồn.
2. **Chưa có file `THIRD_PARTY_LICENSES`** trong repo / bundle — cần tạo khi tiến tới
   phân phối, gom đủ text license + copyright notice của 5 lib + ghi nguồn EPSG.
3. **Chưa chốt kênh phân phối** → chưa chốt cách xử lý GEOS.

## Trạng thái checklist Giai đoạn 1

- [x] Ghi nhận phiên bản chính xác của binary được chốt (bảng trên).
- [x] Ghi nhận license từng dependency + nghĩa vụ phân phối.
- [ ] Chốt cách xử lý GEOS/LGPL-2.1 theo kênh phân phối mục tiêu.
- [ ] Pin SHA256 cho 5 nguồn tải trong build script.
- [ ] Tạo `THIRD_PARTY_LICENSES` khi chuẩn bị phân phối.
