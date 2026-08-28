# Đối chứng kết quả clip với ArcGIS Pro

Bản Windows có bộ test so output của engine với ground-truth do ArcGIS Pro sinh ra
(`tests/reference/` trong repo `MyArcGis_GPT`). iPad không chạy được ArcGIS, nên phần
này là **quy trình thủ công** — làm khi cần nghiệm thu độ chính xác.

## Cần

- 1 máy Windows có **ArcGIS Pro 3.x** + arcpy (bản Windows: `D:\ArcGIS_Pro`).
- File `.ppkx` thật (bản tham khảo: `gathuthiem23-8.ppkx`).
- 1 AOI polygon (GeoJSON hoặc GeoPackage), cùng dùng cho cả 2 bên.

## Bước 1 — Sinh reference bằng ArcGIS Pro

Trên máy Windows, dùng Python của ArcGIS Pro:

```
"D:\ArcGIS_Pro\bin\Python\envs\arcgispro-py3\python.exe" ^
  D:\MyArcGis_GPT\tests\reference\generate_arcpy_reference.py
```

Script tự dò mọi gdb + feature class (`arcpy.da.Walk`, không hard-code), áp policy
**Point = Select · Line/Polygon = Clip**, transform AOI sang CRS từng layer, thử
`RepairGeometry` khi Clip lỗi, bỏ qua annotation. Ra: 1 GeoPackage + 1 CSV.

## Bước 2 — Sinh kết quả iPad

Trên iPad: mở đúng `.ppkx` đó → nhập đúng AOI đó → **Trích xuất tất cả layer** →
màn kết quả → nút chia sẻ → lưu `result.gpkg` + `result_summary.csv` ra Files →
chuyển sang máy Windows.

> Quan trọng: cùng 1 AOI. Nếu vẽ tay trên map thì toạ độ sẽ lệch — dùng **cùng 1 file
> AOI** cho cả 2 bên.

## Bước 3 — So sánh

Trên máy Windows, Python thường (không cần arcpy):

```
py D:\MyArcGis_GPT\tests\reference\compare_outputs.py ^
   --reference <gpkg ArcGIS> --candidate <gpkg iPad>
```

`compare_outputs.py` ghép cặp feature theo hình học gần nhất (không theo OID vì 2
engine đánh OID khác nhau), so khớp hình học trong sai số ~0.1% diện tích/chiều dài
và so khớp thuộc tính.

## Kỳ vọng

- Cùng tập layer có kết quả.
- Mỗi layer: số feature kết quả bằng nhau (± vài feature ở biên do khác thuật toán
  làm tròn/repair).
- Hình học trùng trong sai số nhỏ.
- Thuộc tính giữ nguyên.

Khác biệt điển hình có thể chấp nhận: GEOS vs ArcGIS xử lý biên/điểm chạm khác nhau;
GDAL `MakeValid` vs `RepairGeometry`. Khác biệt lớn (thiếu hẳn layer, lệch CRS) là lỗi
cần điều tra.
