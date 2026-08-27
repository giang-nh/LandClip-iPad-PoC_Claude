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

download_and_extract() {
  local url="$1"
  local archive="$2"
  curl --fail --location --retry 3 --output "${WORK_DIR}/${archive}" "${url}"
  case "${archive}" in
    *.zip) unzip -q "${WORK_DIR}/${archive}" -d "${SOURCE_DIR}" ;;
    *.tar.gz) tar -xzf "${WORK_DIR}/${archive}" -C "${SOURCE_DIR}" ;;
    *.tar.bz2) tar -xjf "${WORK_DIR}/${archive}" -C "${SOURCE_DIR}" ;;
    *) echo "Unsupported archive: ${archive}" >&2; return 1 ;;
  esac
}

download_and_extract \
  "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip" \
  "sqlite.zip"
download_and_extract \
  "https://github.com/OSGeo/PROJ/releases/download/${PROJ_VERSION}/proj-${PROJ_VERSION}.tar.gz" \
  "proj.tar.gz"
download_and_extract \
  "https://github.com/libgeos/geos/releases/download/${GEOS_VERSION}/geos-${GEOS_VERSION}.tar.bz2" \
  "geos.tar.bz2"
download_and_extract \
  "https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz" \
  "gdal.tar.gz"
download_and_extract \
  "https://github.com/libarchive/libarchive/archive/refs/tags/v${LIBARCHIVE_VERSION}.tar.gz" \
  "libarchive.tar.gz"

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

  xcrun --sdk "${sdk}" clang \
    -target "${clang_target}" \
    -isysroot "${sdk_path}" \
    -O2 -fPIC -DSQLITE_OMIT_LOAD_EXTENSION=1 \
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
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DBUILD_SHARED_LIBS=OFF
    "-DCMAKE_INSTALL_PREFIX=${prefix}"
    "-DCMAKE_PREFIX_PATH=${prefix}"
    "-DSQLite3_INCLUDE_DIR=${prefix}/include"
    "-DSQLite3_LIBRARY=${prefix}/lib/libsqlite3.a"
  )

  cmake -S "${SOURCE_DIR}/proj-${PROJ_VERSION}" -B "${build_root}/proj" \
    "${common_cmake[@]}" \
    -DBUILD_APPS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_PROJSYNC=OFF \
    -DENABLE_CURL=OFF \
    -DENABLE_TIFF=OFF \
    -DEXE_SQLITE3=/usr/bin/sqlite3
  cmake --build "${build_root}/proj" --target install --parallel

  cmake -S "${SOURCE_DIR}/geos-${GEOS_VERSION}" -B "${build_root}/geos" \
    "${common_cmake[@]}" \
    -DBUILD_TESTING=OFF \
    -DBUILD_GEOSOP=OFF
  cmake --build "${build_root}/geos" --target install --parallel
  libtool -static \
    -o "${prefix}/lib/libgeos_combined.a" \
    "${prefix}/lib/libgeos.a" \
    "${prefix}/lib/libgeos_c.a"

  cmake -S "${SOURCE_DIR}/libarchive-${LIBARCHIVE_VERSION}" -B "${build_root}/libarchive" \
    "${common_cmake[@]}" \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -DENABLE_TEST=OFF \
    -DENABLE_TAR=OFF \
    -DENABLE_CPIO=OFF \
    -DENABLE_CAT=OFF \
    -DENABLE_UNZIP=OFF \
    -DENABLE_OPENSSL=OFF \
    -DENABLE_MBEDTLS=OFF \
    -DENABLE_NETTLE=OFF \
    -DENABLE_LIBXML2=OFF \
    -DENABLE_EXPAT=OFF \
    -DENABLE_LZMA=OFF \
    -DENABLE_BZip2=OFF \
    -DENABLE_LZ4=OFF \
    -DENABLE_ZSTD=OFF \
    -DENABLE_LZO=OFF
  cmake --build "${build_root}/libarchive" --target install --parallel

  cmake -S "${SOURCE_DIR}/gdal-${GDAL_VERSION}" -B "${build_root}/gdal" \
    "${common_cmake[@]}" \
    -DBUILD_APPS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_JAVA_BINDINGS=OFF \
    -DBUILD_CSHARP_BINDINGS=OFF \
    -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
    -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
    -DOGR_ENABLE_DRIVER_OPENFILEGDB=ON \
    -DOGR_ENABLE_DRIVER_GPKG=ON \
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

create_xcframework() {
  local name="$1"
  local library="$2"
  local headers="$3"
  xcodebuild -create-xcframework \
    -library "${WORK_DIR}/install/ios-arm64/lib/${library}" \
    -headers "${WORK_DIR}/install/ios-arm64/${headers}" \
    -library "${WORK_DIR}/install/ios-arm64-simulator/lib/${library}" \
    -headers "${WORK_DIR}/install/ios-arm64-simulator/${headers}" \
    -output "${OUTPUT_DIR}/${name}.xcframework"
}

create_xcframework SQLite libsqlite3.a include
create_xcframework PROJ libproj.a include
create_xcframework GEOS libgeos_combined.a include
create_xcframework GDAL libgdal.a include
create_xcframework Archive libarchive.a include

mkdir -p "${OUTPUT_DIR}/Resources"
cp -R "${WORK_DIR}/install/ios-arm64/share/proj" "${OUTPUT_DIR}/Resources/proj"
cp -R "${WORK_DIR}/install/ios-arm64/share/gdal" "${OUTPUT_DIR}/Resources/gdal"

echo "Native XCFrameworks created in ${OUTPUT_DIR}"
