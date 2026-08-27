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

Tất cả đều phát hành trong năm 2025. Full text từng license: xem
[`THIRD_PARTY_LICENSES/`](../THIRD_PARTY_LICENSES/).

## SHA-256 các nguồn tải (đã pin trong build script)

| Nguồn | Tệp | SHA-256 |
|---|---|---|
| SQLite | `sqlite-amalgamation-3500400.zip` | `1d3049dd0f830a025a53105fc79fd2ab9431aea99e137809d064d8ee8356b032` |
| PROJ | `proj-9.6.2.tar.gz` | `53d0cafaee3bb2390264a38668ed31d90787de05e71378ad7a8f35bb34c575d1` |
| GEOS | `geos-3.14.1.tar.bz2` | `3c20919cda9a505db07b5216baa980bacdaa0702da715b43f176fb07eff7e716` |
| GDAL | `gdal-3.11.4.tar.gz` | `0fa36ee34d4451db586d2bf78ea0dbfa3b0dfae0516587f8130d21add0ac9dad` |
| libarchive | `libarchive-3.8.9.tar.gz` (release asset) | `f5a6539059cf5e597dbeda37bfa4874b1e8dea063c8d93bf85a2b44af90a5bd4` |

`download_and_extract` chạy `shasum -a 256 -c -` cho từng tệp; mismatch → build fail.

Link release chính thức:

- GDAL: <https://github.com/OSGeo/gdal/releases/tag/v3.11.4>
- PROJ: <https://github.com/OSGeo/PROJ/releases/tag/9.6.2>
- GEOS: <https://github.com/libgeos/geos/releases/tag/3.14.1>
- SQLite: <https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip>
- libarchive: <https://github.com/libarchive/libarchive/releases/tag/v3.8.9>

## Cấu hình build (ảnh hưởng tới license)

Script build **tối giản** để giảm bề mặt license và kích thước:

- `GDAL_BUILD_OPTIONAL_DRIVERS=OFF`, `OGR_BUILD_OPTIONAL_DRIVERS=OFF` — tắt toàn bộ
  driver mặc định.
- Chỉ bật: `OGR_ENABLE_DRIVER_OPENFILEGDB=ON`, `OGR_ENABLE_DRIVER_GPKG=ON`,
  `OGR_ENABLE_DRIVER_GEOJSON=ON`.
  - Runtime còn giới hạn thêm bằng `allowed_drivers = {"OpenFileGDB"}` trong
    [`GISCore.cpp`](../GISCore/Sources/GISCore.cpp) khi mở dataset.
- `GDAL_USE_EXTERNAL_LIBS=OFF` — GDAL dùng bản nhúng nội bộ (json-c…) thay vì lib hệ
  thống, nên không kéo thêm license ngoài.
- libarchive: tắt hầu hết format/filter, chỉ giữ đủ để giải nén ZIP
  (`ENABLE_LZMA/BZip2/LZ4/ZSTD/OPENSSL/MBEDTLS/NETTLE/LIBXML2/EXPAT/ACL/XATTR/LIBB2 = OFF`).
- SQLite build với `SQLITE_ENABLE_COLUMN_METADATA/RTREE/FTS5/GEOPOLY` (GDAL GPKG cần),
  không đặt `SQLITE_OMIT_LOAD_EXTENSION`.

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

### Quyết định cho bản PoC hiện tại (2026-08-27)

`GISCore.cpp` **chưa gọi hàm GEOS nào** — catalog chỉ đọc metadata layer. Nhưng
Giai đoạn 3 (spatial engine, clip theo AOI) sẽ cần GEOS, nên **giữ GEOS trong
build** (đúng phạm vi Giai đoạn 1 của `POC_PLAN.md`).

- **Bản PoC = KHÔNG phân phối** — chỉ build + test trên CI để đánh giá nội bộ
  (`docs/02_product_requirement.md`: "Đối tượng dùng ban đầu: Nội bộ, số lượng nhỏ").
  Ở trạng thái này, link static GEOS **chấp nhận được**.
- **Trước KHI phân phối (bất kỳ kênh nào)** phải thoả LGPL-2.1 §6 bằng (1) GEOS
  framework động, hoặc (2) relink object-code kit + notice + full text LGPL-2.1.
  Chọn cách nào là một phần quyết định kiến trúc Giai đoạn 3.
- Full text LGPL-2.1 + written offer: [`THIRD_PARTY_LICENSES/`](../THIRD_PARTY_LICENSES/).

> Không phát hành build tạo ra từ cấu hình static hiện tại cho tới khi hoàn tất
> một trong hai cách trên.

## Data files đi kèm bundle

Script copy `share/proj` và `share/gdal` vào `Vendor/Resources/`; `project-native.yml`
bundle chúng vào **thư mục `proj/` và `gdal/` ở gốc `.app`** (không phải folder tên
`Resources/` — sẽ làm iOS từ chối bundle), runtime trỏ qua
`landclip_gis_configure_data_paths`.

| Thư mục | Nội dung | License / điều khoản |
|---|---|---|
| `proj/` | `proj.db`, `proj.ini`, vài file cấu hình (KHÔNG có grid projsync — `BUILD_PROJSYNC=OFF`, `ENABLE_CURL=OFF`) | `proj.db` tổng hợp từ **EPSG Dataset** + ESRI + IGNF… — EPSG Terms of Use: dùng & phân phối lại **kèm ghi nguồn**, không sửa mà vẫn gọi là "EPSG". File còn lại theo PROJ (MIT) |
| `gdal/` | Bảng CSV, template… của GDAL | Phần lớn MIT; một phần dẫn xuất từ EPSG (ghi nguồn như trên) |

Cần đưa ghi nguồn EPSG + danh sách 5 component vào màn "Acknowledgements / Legal".

## Trạng thái checklist Giai đoạn 1

- [x] Ghi nhận phiên bản chính xác của binary được chốt (bảng trên).
- [x] Ghi nhận license từng dependency + nghĩa vụ phân phối.
- [x] Pin SHA256 cho 5 nguồn tải trong build script.
- [x] Tạo [`THIRD_PARTY_LICENSES/`](../THIRD_PARTY_LICENSES/) (full text 5 license + written offer GEOS).
- [x] Chốt cách xử lý GEOS/LGPL-2.1 cho bản PoC (giữ static, không phân phối; điều
  kiện phân phối đã ghi rõ).

## Việc chuyển sang Giai đoạn 3 phải làm

- Quyết định GEOS động vs relink-kit và implement trước khi có build phân phối.
- Bổ sung màn Acknowledgements/Legal trong app.
