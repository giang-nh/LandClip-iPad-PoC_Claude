#include "GISCore.h"

#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>

#ifndef LANDCLIP_WITH_GDAL
#define LANDCLIP_WITH_GDAL 0
#endif

#if LANDCLIP_WITH_GDAL
#include <archive.h>
#include <archive_entry.h>
#include <gdal/cpl_conv.h>
#include <gdal/gdal.h>
#include <gdal/ogr_api.h>
#include <gdal/ogr_srs_api.h>
#endif

namespace {
char *copy_string(const std::string &value) {
    auto *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result != nullptr) {
        std::memcpy(result, value.c_str(), value.size() + 1);
    }
    return result;
}

std::string json_string(const char *value) {
    std::ostringstream output;
    output << '"';
    for (const unsigned char character : std::string(value == nullptr ? "" : value)) {
        switch (character) {
        case '"': output << "\\\""; break;
        case '\\': output << "\\\\"; break;
        case '\b': output << "\\b"; break;
        case '\f': output << "\\f"; break;
        case '\n': output << "\\n"; break;
        case '\r': output << "\\r"; break;
        case '\t': output << "\\t"; break;
        default:
            if (character < 0x20) {
                const char hex[] = "0123456789abcdef";
                output << "\\u00" << hex[character >> 4] << hex[character & 0x0f];
            } else {
                output << character;
            }
        }
    }
    output << '"';
    return output.str();
}

bool is_safe_archive_path(const char *path) {
    if (path == nullptr || path[0] == '\0' || path[0] == '/' || path[0] == '\\') return false;
    std::string normalized(path);
    for (char &character : normalized) {
        if (character == '\\') character = '/';
    }
    std::istringstream components(normalized);
    std::string component;
    while (std::getline(components, component, '/')) {
        if (component == "..") return false;
    }
    return normalized.find(':') == std::string::npos;
}

#if LANDCLIP_WITH_GDAL
const char *geometry_type_name(OGRwkbGeometryType type) {
    switch (wkbFlatten(type)) {
    case wkbPoint: return "Point";
    case wkbLineString: return "LineString";
    case wkbPolygon: return "Polygon";
    case wkbMultiPoint: return "MultiPoint";
    case wkbMultiLineString: return "MultiLineString";
    case wkbMultiPolygon: return "MultiPolygon";
    case wkbGeometryCollection: return "GeometryCollection";
    case wkbNone: return "None";
    default: return "Unknown";
    }
}
#endif
}

const char *landclip_gis_engine_version(void) {
#if LANDCLIP_WITH_GDAL
    return GDALVersionInfo("RELEASE_NAME");
#else
    return "poc-no-gdal";
#endif
}

int landclip_gis_has_gdal(void) {
#if LANDCLIP_WITH_GDAL
    return 1;
#else
    return 0;
#endif
}

void landclip_gis_configure_data_paths(const char *gdal_data_path,
                                       const char *proj_data_path) {
#if LANDCLIP_WITH_GDAL
    if (gdal_data_path != nullptr && gdal_data_path[0] != '\0') {
        CPLSetConfigOption("GDAL_DATA", gdal_data_path);
    }
    if (proj_data_path != nullptr && proj_data_path[0] != '\0') {
        const char *paths[] = {proj_data_path, nullptr};
        OSRSetPROJSearchPaths(paths);
    }
#else
    (void)gdal_data_path;
    (void)proj_data_path;
#endif
}

char *landclip_gis_copy_gdb_catalog_json(const char *gdb_path,
                                         char **error_message) {
    if (error_message != nullptr) {
        *error_message = nullptr;
    }
#if LANDCLIP_WITH_GDAL
    if (gdb_path == nullptr || gdb_path[0] == '\0') {
        if (error_message != nullptr) {
            *error_message = copy_string("Geodatabase path is empty.");
        }
        return nullptr;
    }

    GDALAllRegister();
    const char *allowed_drivers[] = {"OpenFileGDB", nullptr};
    GDALDatasetH dataset = GDALOpenEx(gdb_path, GDAL_OF_VECTOR | GDAL_OF_READONLY,
                                     allowed_drivers, nullptr, nullptr);
    if (dataset == nullptr) {
        if (error_message != nullptr) {
            *error_message = copy_string("OpenFileGDB could not open the dataset.");
        }
        return nullptr;
    }

    std::ostringstream json;
    json << "{\"engineVersion\":" << json_string(GDALVersionInfo("RELEASE_NAME"))
         << ",\"layers\":[";
    const int layer_count = GDALDatasetGetLayerCount(dataset);
    bool emitted_layer = false;
    for (int index = 0; index < layer_count; ++index) {
        OGRLayerH layer = GDALDatasetGetLayer(dataset, index);
        if (layer == nullptr) continue;
        if (emitted_layer) json << ',';
        emitted_layer = true;
        OGRFeatureDefnH definition = OGR_L_GetLayerDefn(layer);
        const OGRwkbGeometryType geometry = OGR_FD_GetGeomType(definition);
        const GIntBig feature_count = OGR_L_GetFeatureCount(layer, false);
        char *spatial_reference_wkt = nullptr;
        OGRSpatialReferenceH spatial_reference = OGR_L_GetSpatialRef(layer);
        if (spatial_reference != nullptr) {
            OSRExportToWkt(spatial_reference, &spatial_reference_wkt);
        }
        json << "{\"name\":" << json_string(OGR_FD_GetName(definition))
             << ",\"geometryType\":" << json_string(geometry_type_name(geometry))
             << ",\"featureCount\":";
        if (feature_count < 0) json << "null"; else json << feature_count;
        json << ",\"crs\":";
        if (spatial_reference_wkt == nullptr) json << "null";
        else json << json_string(spatial_reference_wkt);
        json << '}';
        CPLFree(spatial_reference_wkt);
    }
    json << "]}";
    GDALClose(dataset);
    return copy_string(json.str());
#else
    (void)gdb_path;
    if (error_message != nullptr) {
        *error_message = copy_string("GISCore was built without GDAL.");
    }
    return nullptr;
#endif
}

void landclip_gis_free_string(char *value) {
    std::free(value);
}

int landclip_archive_extract_ppkx(const char *package_path,
                                  const char *destination_path,
                                  char **error_message) {
    if (error_message != nullptr) *error_message = nullptr;
#if LANDCLIP_WITH_GDAL
    if (package_path == nullptr || destination_path == nullptr) {
        if (error_message != nullptr) *error_message = copy_string("Archive path is empty.");
        return 0;
    }
    archive *input = archive_read_new();
    archive *output = archive_write_disk_new();
    archive_read_support_filter_all(input);
    archive_read_support_format_zip(input);
    archive_write_disk_set_options(
        output,
        ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_NODOTDOT |
            ARCHIVE_EXTRACT_SECURE_SYMLINKS
    );
    if (archive_read_open_filename(input, package_path, 64 * 1024) != ARCHIVE_OK) {
        const char *message = archive_error_string(input);
        if (error_message != nullptr) {
            *error_message = copy_string(message == nullptr ? "Could not open PPKX." : message);
        }
        archive_write_free(output);
        archive_read_free(input);
        return 0;
    }

    archive_entry *entry = nullptr;
    int result = ARCHIVE_OK;
    while ((result = archive_read_next_header(input, &entry)) == ARCHIVE_OK) {
        const char *relative_path = archive_entry_pathname(entry);
        if (!is_safe_archive_path(relative_path) || archive_entry_symlink(entry) != nullptr ||
            archive_entry_hardlink(entry) != nullptr) {
            result = ARCHIVE_FATAL;
            archive_set_error(output, ARCHIVE_FATAL, "Unsafe archive entry path");
            break;
        }
        std::string full_path(destination_path);
        full_path += '/';
        full_path += relative_path == nullptr ? "" : relative_path;
        archive_entry_set_pathname(entry, full_path.c_str());
        result = archive_write_header(output, entry);
        if (result < ARCHIVE_OK) break;
        const void *buffer = nullptr;
        size_t size = 0;
        la_int64_t offset = 0;
        while ((result = archive_read_data_block(input, &buffer, &size, &offset)) == ARCHIVE_OK) {
            result = archive_write_data_block(output, buffer, size, offset);
            if (result < ARCHIVE_OK) break;
        }
        if (result != ARCHIVE_EOF && result < ARCHIVE_OK) break;
        result = archive_write_finish_entry(output);
        if (result < ARCHIVE_OK) break;
    }
    const bool succeeded = result == ARCHIVE_EOF;
    if (!succeeded && error_message != nullptr) {
        const char *message = archive_error_string(output);
        if (message == nullptr) message = archive_error_string(input);
        *error_message = copy_string(message == nullptr ? "Could not extract PPKX." : message);
    }
    archive_write_close(output);
    archive_write_free(output);
    archive_read_close(input);
    archive_read_free(input);
    return succeeded ? 1 : 0;
#else
    (void)package_path;
    (void)destination_path;
    if (error_message != nullptr) *error_message = copy_string("GISCore was built without archive support.");
    return 0;
#endif
}
