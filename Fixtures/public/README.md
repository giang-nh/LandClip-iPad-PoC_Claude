# Fixture công khai (tổng hợp)

Tất cả file ở đây do `scripts/create_public_fixture.py` sinh ra, **100% tổng hợp** —
không copy hình học, thuộc tính, tên hay mã định danh nào từ dữ liệu thật/khách hàng.
Được phép dùng và phân phối lại cùng project này.

## Nội dung

| File | Dùng cho |
|---|---|
| `sample.gdb/` | File Geodatabase tổng hợp, 3 layer, CRS `EPSG:9210` |
| `sample.ppkx` | ZIP chứa đúng `sample.gdb` — test trọn pipeline copy → giải nén → tìm gdb → catalog |
| `expected-catalog.json` | Kỳ vọng cho `testNativeOpenFileGDBCatalog` |
| `sample-aoi.geojson` | AOI hình vuông 15×15 (EPSG:9210) — cho `testNativeClipPipeline`, `testClipLayerSelection`, `testClipResumeAppends` |
| `sample-aoi.dxf` | Cùng ý tưởng nhưng dạng DXF closed polyline + WKT nhúng trong comment `999` — cho `testDXFAOIClips` |
| `expected-clip.json` | Kỳ vọng kết quả clip (points 2 / lines 1 / polygons 1) |

3 layer trong `sample.gdb`:

- `sample_points` — 3 point
- `sample_lines` — 2 line (OpenFileGDB đọc lại là MultiLineString)
- `sample_polygons` — 1 polygon (đọc lại là MultiPolygon)

`sample.ppkx` cũng được bundle vào app native để nút DEBUG **"Thử nhanh (dữ liệu mẫu)"**
chạy thử toàn bộ luồng mà không cần chọn file.
