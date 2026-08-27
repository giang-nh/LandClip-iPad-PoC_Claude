#!/usr/bin/env bash
set -euo pipefail

GDAL_VERSION="3.11.4"
PROJ_VERSION="9.6.2"
GEOS_VERSION="3.14.1"
SQLITE_VERSION="3500400"
SQLITE_YEAR="2025"
LIBARCHIVE_VERSION="3.8.9"
DEPLOYMENT_TARGET="17.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${RUNNER_TEMP:-${ROOT_DIR}/.native-build}/landclip-native"
SOURCE_DIR="${WORK_DIR}/sources"
OUTPUT_DIR="${ROOT_DIR}/Vendor"

rm -rf "${WORK_DIR}" "${OUTPUT_DIR}"
mkdir -p "${SOURCE_DIR}" "${OUTPUT_DIR}"

# Pinned SHA-256 of every source archive (see docs/DEPENDENCIES.md). A mismatch
# means upstream re-cut the release or the download was tampered with — fail hard.
SQLITE_SHA256="1d3049dd0f830a025a53105fc79fd2ab9431aea99e137809d064d8ee8356b032"
PROJ_SHA256="53d0cafaee3bb2390264a38668ed31d90787de05e71378ad7a8f35bb34c575d1"
GEOS_SHA256="3c20919cda9a505db07b5216baa980bacdaa0702da715b43f176fb07eff7e716"
GDAL_SHA256="0fa36ee34d4451db586d2bf78ea0dbfa3b0dfae0516587f8130d21add0ac9dad"
LIBARCHIVE_SHA256="f5a6539059cf5e597dbeda37bfa4874b1e8dea063c8d93bf85a2b44af90a5bd4"

download_and_extract() {
  local url="$1"
  local archive="$2"
  local sha256="$3"
  curl --fail --location --retry 3 --output "${WORK_DIR}/${archive}" "${url}"
  echo "${sha256}  ${WORK_DIR}/${archive}" | shasum -a 256 -c -
  case "${archive}" in
    *.zip) unzip -q "${WORK_DIR}/${archive}" -d "${SOURCE_DIR}" ;;
    *.tar.gz) tar -xzf "${WORK_DIR}/${archive}" -C "${SOURCE_DIR}" ;;
    *.tar.bz2) tar -xjf "${WORK_DIR}/${archive}" -C "${SOURCE_DIR}" ;;
    *) echo "Unsupported archive: ${archive}" >&2; return 1 ;;
  esac
}

download_and_extract \
  "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip" \
  "sqlite.zip" "${SQLITE_SHA256}"
download_and_extract \
  "https://github.com/OSGeo/PROJ/releases/download/${PROJ_VERSION}/proj-${PROJ_VERSION}.tar.gz" \
  "proj.tar.gz" "${PROJ_SHA256}"
download_and_extract \
  "https://github.com/libgeos/geos/releases/download/${GEOS_VERSION}/geos-${GEOS_VERSION}.tar.bz2" \
  "geos.tar.bz2" "${GEOS_SHA256}"
download_and_extract \
  "https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz" \
  "gdal.tar.gz" "${GDAL_SHA256}"
download_and_extract \
  "https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VERSION}/libarchive-${LIBARCHIVE_VERSION}.tar.gz" \
  "libarchive.tar.gz" "${LIBARCHIVE_SHA256}"

build_slice() {
  local slice="$1"
  local sdk="$2"
  local cmake_sysroot="$3"
  local clang_target="$4"
  local prefix="${WORK_DIR}/install/${slice}"
  local build_root="${WORK_DIR}/build/${slice}"
  local sdk_path
  sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  mkdir -p "${prefix}/include" "${prefix}/lib" "${build_root}"

  # GDAL's GPKG driver links against the full SQLite C API: column metadata
  # (sqlite3_column_table_name, ...), the load-extension entry points (which it
  # only calls to switch extension loading *off*), R*Tree for the spatial index
  # and FTS5. Omitting these leaves undefined symbols at app link time.
  xcrun --sdk "${sdk}" clang \
    -target "${clang_target}" \
    -isysroot "${sdk_path}" \
    -O2 -fPIC \
    -DSQLITE_ENABLE_COLUMN_METADATA=1 \
    -DSQLITE_ENABLE_RTREE=1 \
    -DSQLITE_ENABLE_FTS5=1 \
    -DSQLITE_ENABLE_GEOPOLY=1 \
    -c "${SOURCE_DIR}/sqlite-amalgamation-${SQLITE_VERSION}/sqlite3.c" \
    -o "${build_root}/sqlite3.o"
  libtool -static -o "${prefix}/lib/libsqlite3.a" "${build_root}/sqlite3.o"
  cp "${SOURCE_DIR}/sqlite-amalgamation-${SQLITE_VERSION}/sqlite3.h" "${prefix}/include/"
  cp "${SOURCE_DIR}/sqlite-amalgamation-${SQLITE_VERSION}/sqlite3ext.h" "${prefix}/include/"

  local common_cmake=(
    -G Ninja
    -DCMAKE_SYSTEM_NAME=iOS
    "-DCMAKE_OSX_SYSROOT=${cmake_sysroot}"
    -DCMAKE_OSX_ARCHITECTURES=arm64
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${DEPLOYMENT_TARGET}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DBUILD_SHARED_LIBS=OFF
    "-DCMAKE_INSTALL_PREFIX=${prefix}"
    "-DCMAKE_PREFIX_PATH=${prefix}"
    "-DSQLite3_INCLUDE_DIR=${prefix}/include"
    "-DSQLite3_LIBRARY=${prefix}/lib/libsqlite3.a"
  )

  # PROJ / GEOS / GDAL need link-less try-compiles because their cross-compile
  # feature checks would otherwise fail to link against the iOS sysroot.
  # libarchive is the opposite: it relies on check_function_exists actually
  # linking so that iOS-absent symbols (futimesat, ...) are reported missing.
  local try_static=(-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY)

  cmake -S "${SOURCE_DIR}/proj-${PROJ_VERSION}" -B "${build_root}/proj" \
    "${common_cmake[@]}" "${try_static[@]}" \
    -DBUILD_APPS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_PROJSYNC=OFF \
    -DENABLE_CURL=OFF \
    -DENABLE_TIFF=OFF \
    -DEXE_SQLITE3=/usr/bin/sqlite3
  cmake --build "${build_root}/proj" --target install --parallel

  cmake -S "${SOURCE_DIR}/geos-${GEOS_VERSION}" -B "${build_root}/geos" \
    "${common_cmake[@]}" "${try_static[@]}" \
    -DBUILD_TESTING=OFF \
    -DBUILD_GEOSOP=OFF
  cmake --build "${build_root}/geos" --target install --parallel
  libtool -static \
    -o "${prefix}/lib/libgeos_combined.a" \
    "${prefix}/lib/libgeos.a" \
    "${prefix}/lib/libgeos_c.a"

  cmake -S "${SOURCE_DIR}/libarchive-${LIBARCHIVE_VERSION}" -B "${build_root}/libarchive" \
    "${common_cmake[@]}" \
    -DENABLE_TEST=OFF \
    -DENABLE_TAR=OFF \
    -DENABLE_CPIO=OFF \
    -DENABLE_CAT=OFF \
    -DENABLE_UNZIP=OFF \
    -DENABLE_ACL=OFF \
    -DENABLE_XATTR=OFF \
    -DENABLE_OPENSSL=OFF \
    -DENABLE_MBEDTLS=OFF \
    -DENABLE_NETTLE=OFF \
    -DENABLE_LIBB2=OFF \
    -DENABLE_LIBXML2=OFF \
    -DENABLE_EXPAT=OFF \
    -DENABLE_LZMA=OFF \
    -DENABLE_BZip2=OFF \
    -DENABLE_LZ4=OFF \
    -DENABLE_ZSTD=OFF \
    -DENABLE_LZO=OFF
  cmake --build "${build_root}/libarchive" --target install --parallel

  cmake -S "${SOURCE_DIR}/gdal-${GDAL_VERSION}" -B "${build_root}/gdal" \
    "${common_cmake[@]}" "${try_static[@]}" \
    -DBUILD_APPS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_JAVA_BINDINGS=OFF \
    -DBUILD_CSHARP_BINDINGS=OFF \
    -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
    -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
    -DOGR_ENABLE_DRIVER_OPENFILEGDB=ON \
    -DOGR_ENABLE_DRIVER_GPKG=ON \
    -DOGR_ENABLE_DRIVER_GEOJSON=ON \
    -DGDAL_USE_EXTERNAL_LIBS=OFF \
    -DGDAL_USE_GEOS=ON \
    -DGDAL_USE_SQLITE3=ON \
    "-DPROJ_DIR=${prefix}/lib/cmake/proj" \
    "-DGEOS_DIR=${prefix}/lib/cmake/GEOS"
  cmake --build "${build_root}/gdal" --target install --parallel
}

build_slice "ios-arm64" "iphoneos" "iphoneos" "arm64-apple-ios${DEPLOYMENT_TARGET}"
build_slice "ios-arm64-simulator" "iphonesimulator" "iphonesimulator" \
  "arm64-apple-ios${DEPLOYMENT_TARGET}-simulator"

# Header-less static-library XCFrameworks. All five libraries were installed into
# the same prefix, so bundling ${prefix}/include inside each XCFramework made
# Xcode copy the same header from several frameworks into $BUILT_PRODUCTS_DIR and
# fail with "Multiple commands produce .../include/proj.h". The app only needs the
# GDAL and libarchive C headers, shipped once as a plain directory that
# project-native.yml adds to HEADER_SEARCH_PATHS.
create_xcframework() {
  local name="$1"
  local library="$2"
  xcodebuild -create-xcframework \
    -library "${WORK_DIR}/install/ios-arm64/lib/${library}" \
    -library "${WORK_DIR}/install/ios-arm64-simulator/lib/${library}" \
    -output "${OUTPUT_DIR}/${name}.xcframework"
}

create_xcframework SQLite libsqlite3.a
create_xcframework PROJ libproj.a
create_xcframework GEOS libgeos_combined.a
create_xcframework GDAL libgdal.a
create_xcframework Archive libarchive.a

# Public C headers needed to compile GISCore against GDAL + libarchive. Taken
# from the device slice (identical to the simulator slice for these C APIs).
HEADERS_OUT="${OUTPUT_DIR}/Headers"
rm -rf "${HEADERS_OUT}"
mkdir -p "${HEADERS_OUT}"
cp -R "${WORK_DIR}/install/ios-arm64/include/." "${HEADERS_OUT}/"

mkdir -p "${OUTPUT_DIR}/Resources"
cp -R "${WORK_DIR}/install/ios-arm64/share/proj" "${OUTPUT_DIR}/Resources/proj"
cp -R "${WORK_DIR}/install/ios-arm64/share/gdal" "${OUTPUT_DIR}/Resources/gdal"

echo "Native XCFrameworks created in ${OUTPUT_DIR}"
