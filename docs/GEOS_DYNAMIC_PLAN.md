# Chuyển GEOS sang liên kết động (LGPL-2.1 §6)

**Khi nào làm:** ngay trước lần phát hành đầu tiên (TestFlight / nội bộ / App Store).
Không làm sớm hơn vì thay đổi cách nạp thư viện lúc runtime, rủi ro dyld/rpath chỉ
lộ ra trên thiết bị thật — phải verify bằng một bản TestFlight chạy được trên iPad.

**Tại sao cần:** GEOS là LGPL-2.1. Bản PoC hiện link **static** GEOS vào app. LGPL-2.1
§6 yêu cầu người dùng cuối có thể thay GEOS bằng bản khác và relink. Cách gọn nhất
cho iOS: đóng GEOS thành framework **động**, nhúng vào app (giống VLC for iOS).

Toàn văn LGPL-2.1 + written offer đã có ở [`THIRD_PARTY_LICENSES/`](../THIRD_PARTY_LICENSES/);
màn **Ghi nhận & Pháp lý** trong app đã nêu. Chỉ còn phần kỹ thuật dưới đây.

---

## 1. Build GEOS shared (`scripts/build-native-xcframeworks.sh`)

Trong `build_slice`, tách GEOS ra khỏi `common_cmake` (đang có `BUILD_SHARED_LIBS=OFF`):

```sh
cmake -S "${SOURCE_DIR}/geos-${GEOS_VERSION}" -B "${build_root}/geos" \
  "${common_cmake[@]/-DBUILD_SHARED_LIBS=OFF/-DBUILD_SHARED_LIBS=ON}" "${try_static[@]}" \
  -DBUILD_TESTING=OFF -DBUILD_GEOSOP=OFF \
  -DCMAKE_INSTALL_RPATH='@loader_path' \
  -DCMAKE_MACOSX_RPATH=ON
cmake --build "${build_root}/geos" --target install --parallel
```

Kết quả: `libgeos.dylib` + `libgeos_c.dylib` (thay cho `.a`). Bỏ bước
`libtool -static ... libgeos_combined.a`.

Đặt `install_name` đúng cho cả hai:

```sh
for slice_lib in "${prefix}/lib/libgeos_c.dylib" "${prefix}/lib/libgeos.dylib"; do
  install_name_tool -id "@rpath/$(basename "$slice_lib")" "$slice_lib"
done
install_name_tool -change "$(otool -L "${prefix}/lib/libgeos_c.dylib" | awk '/libgeos\.[0-9].*dylib/{print $1; exit}')" \
  "@rpath/libgeos.$(...).dylib" "${prefix}/lib/libgeos_c.dylib"
```

(GEOS đánh version dylib, ví dụ `libgeos.3.14.1.dylib` + symlink — giữ nguyên tên có
version, sửa cả `-id` lẫn dependency `libgeos_c → libgeos`.)

GDAL vẫn build như cũ (`GDAL_USE_GEOS=ON`); nó sẽ link động tới GEOS.

## 2. Đóng XCFramework động cho GEOS

```sh
create_dynamic_xcframework() {   # thay cho create_xcframework với GEOS
  xcodebuild -create-xcframework \
    -library "${WORK_DIR}/install/ios-arm64/lib/libgeos_c.<ver>.dylib" \
    -library "${WORK_DIR}/install/ios-arm64-simulator/lib/libgeos_c.<ver>.dylib" \
    -output "${OUTPUT_DIR}/GEOS.xcframework"
}
```

Cũng phải kèm `libgeos.<ver>.dylib` (libgeos_c phụ thuộc nó). Cách chắc ăn: gộp
symbol của `libgeos` vào `libgeos_c` bằng `-reexport` khi build, hoặc đóng **cả 2
dylib** vào framework và nhúng cả 2. Đơn giản nhất: build GEOS với
`-DBUILD_GEOS_CXX_SHARED=OFF` không có sẵn → dùng cách gộp: link `libgeos_c.dylib`
với `-Wl,-all_load libgeos.a` để nó self-contained, rồi chỉ ship `libgeos_c.dylib`.
Tức là: build `libgeos.a` static (như cũ) + `libgeos_c` shared re-export toàn bộ:

```sh
clang -dynamiclib -install_name @rpath/libgeos_c.dylib \
  -Wl,-force_load,"${prefix}/lib/libgeos.a" \
  -Wl,-force_load,"${prefix}/lib/libgeos_c.a" \
  -o "${prefix}/lib/libgeos_c.dylib" -lc++ -isysroot "$sdk_path" -target "$clang_target"
```

→ 1 dylib duy nhất, self-contained. Đây là cách ít rắc rối nhất.

## 3. `project-native.yml`

```yaml
      - framework: Vendor/GEOS.xcframework
        embed: true          # thay vì false
```

Thêm vào `settings.base` của target `LandClipIPad`:

```yaml
        LD_RUNPATH_SEARCH_PATHS:
          - "$(inherited)"
          - "@executable_path/Frameworks"
```

Các XCFramework còn lại (GDAL/PROJ/SQLite/Archive) giữ `embed: false` (vẫn static).

## 4. Kiểm chứng (bắt buộc, trên thiết bị)

1. `Native iPad PoC` xanh — `testNativeClipPipeline` vẫn pass (giờ chạy qua GEOS động
   trong simulator).
2. Chạy `TestFlight` workflow → cài lên iPad → mở app:
   - App **khởi động được** (không crash dyld "Library not loaded: @rpath/libgeos_c.dylib").
   - "Thử nhanh" → clip ra kết quả đúng (2 điểm / 1 line / 1 polygon).
3. Nếu crash: kiểm `otool -L LandClipIPad.app/LandClipIPad` và
   `LandClipIPad.app/Frameworks/` — thiếu dylib hoặc sai `@rpath`.

## 5. Sau khi xong

- Cập nhật `DEPENDENCIES.md` và `THIRD_PARTY_LICENSES/README.md`: GEOS giờ **động**,
  đã thoả LGPL-2.1 §6 cách (1).
- Bỏ dòng "không phát hành build static" trong `DEPENDENCIES.md`.
- `POC_PLAN.md`: tick ô GEOS/LGPL.

## Phương án B — nếu framework động quá rắc rối

Ship **relink kit**: workflow phụ đóng gói `LandClipIPad.app/` dạng chưa link cuối
(`*.o` + `libgdal.a` + `libgeos.a` + script `ld`), kèm hướng dẫn, thoả LGPL-2.1 §6
cách (2). Ít rủi ro runtime hơn nhưng nặng tay hơn cho người phát hành.
