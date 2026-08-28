#include "GISCore.h"

#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>

#ifndef LANDCLIP_WITH_GDAL
#define LANDCLIP_WITH_GDAL 0
#endif

#if LANDCLIP_WITH_GDAL
#include <archive.h>
#include <archive_entry.h>
#include <cpl_conv.h>
#include <cpl_string.h>
#include <cpl_vsi.h>
#include <gdal.h>
#include <gdal_utils.h>
#include <ogr_api.h>
#include <ogr_srs_api.h>
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

/// Invokes the progress callback if present. Returns true when the caller asked
/// to cancel.
bool report_progress(landclip_progress_callback callback, void *context,
                     const std::string &event_json) {
    if (callback == nullptr) return false;
    return callback(context, event_json.c_str()) != 0;
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

/// One of the six 2D families the PoC supports, or empty for anything else
/// (annotation, 3D-only surfaces, unknown).
std::string geometry_family(OGRwkbGeometryType type) {
    switch (wkbFlatten(type)) {
    case wkbPoint:
    case wkbMultiPoint: return "Point";
    case wkbLineString:
    case wkbMultiLineString: return "Line";
    case wkbPolygon:
    case wkbMultiPolygon: return "Polygon";
    default: return "";
    }
}

/// RAII wrappers keep the OGR C handles exception- and early-return-safe.
struct GeometryGuard {
    OGRGeometryH handle = nullptr;
    ~GeometryGuard() { if (handle != nullptr) OGR_G_DestroyGeometry(handle); }
    OGRGeometryH release() { OGRGeometryH h = handle; handle = nullptr; return h; }
};

struct DatasetGuard {
    GDALDatasetH handle = nullptr;
    ~DatasetGuard() { if (handle != nullptr) GDALClose(handle); }
};

std::string csv_cell(const std::string &value) {
    if (value.find_first_of(",\"\n\r") == std::string::npos) return value;
    std::string escaped = "\"";
    for (char character : value) {
        if (character == '"') escaped += '"';
        escaped += character;
    }
    escaped += '"';
    return escaped;
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
                                  landclip_progress_callback progress,
                                  void *progress_context,
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
    // ArcGIS packages are usually ZIP but older ones are 7z; accept both.
    archive_read_support_format_zip(input);
    archive_read_support_format_7zip(input);
    archive_write_disk_set_options(
        output,
        ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_NODOTDOT |
            ARCHIVE_EXTRACT_SECURE_SYMLINKS
    );
    if (archive_read_open_filename(input, package_path, 256 * 1024) != ARCHIVE_OK) {
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
    bool cancelled = false;
    std::int64_t entries_done = 0;
    std::int64_t bytes_done = 0;
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
            const la_ssize_t written = archive_write_data_block(output, buffer, size, offset);
            if (written < ARCHIVE_OK) { result = static_cast<int>(written); break; }
            bytes_done += static_cast<std::int64_t>(size);
        }
        if (result != ARCHIVE_EOF && result < ARCHIVE_OK) break;
        result = archive_write_finish_entry(output);
        if (result < ARCHIVE_OK) break;

        entries_done += 1;
        if ((entries_done % 16) == 0) {
            std::ostringstream event;
            event << "{\"event\":\"extract\",\"entriesDone\":" << entries_done
                  << ",\"bytesDone\":" << bytes_done << "}";
            if (report_progress(progress, progress_context, event.str())) {
                cancelled = true;
                break;
            }
        }
    }
    bool succeeded = !cancelled && result == ARCHIVE_EOF;
    if (cancelled && error_message != nullptr) {
        *error_message = copy_string("Extraction cancelled.");
    } else if (!succeeded && error_message != nullptr) {
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
    (void)progress;
    (void)progress_context;
    if (error_message != nullptr) *error_message = copy_string("GISCore was built without archive support.");
    return 0;
#endif
}

#if LANDCLIP_WITH_GDAL
namespace {

/// Splits a JSON array of strings (`["/a","/b"]`) without pulling in a JSON
/// parser. The values come from our own Swift code so the shape is trusted; only
/// basic escapes are handled.
std::vector<std::string> parse_json_string_array(const char *json) {
    std::vector<std::string> values;
    if (json == nullptr) return values;
    const std::string text(json);
    size_t index = 0;
    while (index < text.size()) {
        if (text[index] != '"') { ++index; continue; }
        std::string value;
        ++index;
        while (index < text.size() && text[index] != '"') {
            if (text[index] == '\\' && index + 1 < text.size()) {
                ++index;
                switch (text[index]) {
                case 'n': value += '\n'; break;
                case 't': value += '\t'; break;
                case 'r': value += '\r'; break;
                default: value += text[index];
                }
            } else {
                value += text[index];
            }
            ++index;
        }
        ++index;
        values.push_back(value);
    }
    return values;
}

/// Parses the string array that follows `"<key>"` in a small JSON object.
std::vector<std::string> parse_json_array_after_key(const char *json, const char *key) {
    if (json == nullptr) return {};
    const std::string text(json);
    const std::string needle = std::string("\"") + key + "\"";
    const size_t at = text.find(needle);
    if (at == std::string::npos) return {};
    const size_t open = text.find('[', at);
    if (open == std::string::npos) return {};
    const size_t close = text.find(']', open);
    if (close == std::string::npos) return {};
    return parse_json_string_array(text.substr(open, close - open + 1).c_str());
}

bool set_contains(const std::vector<std::string> &values, const std::string &value) {
    for (const std::string &existing : values) {
        if (existing == value) return true;
    }
    return false;
}

/// Rough AOI area (m²) and perimeter (m): reproject the AOI to the UTM zone under
/// its centroid, like the Windows tool's estimate_utm_crs(). Returns 0 on any
/// failure — the value is informational only.
double compute_aoi_metrics(OGRGeometryH aoi, OGRSpatialReferenceH srs, double *perimeter) {
    *perimeter = 0.0;
    if (aoi == nullptr || srs == nullptr) return 0.0;

    OGRSpatialReferenceH wgs = OSRNewSpatialReference(nullptr);
    OSRImportFromEPSG(wgs, 4326);
    OSRSetAxisMappingStrategy(wgs, OAMS_TRADITIONAL_GIS_ORDER);

    double lon = 105.0, lat = 16.0;
    {
        GeometryGuard g;
        g.handle = OGR_G_Clone(aoi);
        if (!OSRIsSame(srs, wgs)) {
            OGRCoordinateTransformationH t = OCTNewCoordinateTransformation(srs, wgs);
            if (t != nullptr) { OGR_G_Transform(g.handle, t); OCTDestroyCoordinateTransformation(t); }
        }
        OGRGeometryH centroid = OGR_G_CreateGeometry(wkbPoint);
        if (OGR_G_Centroid(g.handle, centroid) == OGRERR_NONE) {
            lon = OGR_G_GetX(centroid, 0);
            lat = OGR_G_GetY(centroid, 0);
        }
        OGR_G_DestroyGeometry(centroid);
    }

    int zone = static_cast<int>(std::floor((lon + 180.0) / 6.0)) + 1;
    if (zone < 1) zone = 1;
    if (zone > 60) zone = 60;
    const int epsg = (lat >= 0.0 ? 32600 : 32700) + zone;

    OGRSpatialReferenceH utm = OSRNewSpatialReference(nullptr);
    OSRImportFromEPSG(utm, epsg);
    OSRSetAxisMappingStrategy(utm, OAMS_TRADITIONAL_GIS_ORDER);

    double area = 0.0;
    {
        GeometryGuard g;
        g.handle = OGR_G_Clone(aoi);
        OGRCoordinateTransformationH t = OCTNewCoordinateTransformation(srs, utm);
        if (t != nullptr) {
            if (OGR_G_Transform(g.handle, t) == OGRERR_NONE) {
                area = OGR_G_Area(g.handle);
                OGRGeometryH boundary = OGR_G_Boundary(g.handle);
                if (boundary != nullptr) {
                    *perimeter = OGR_G_Length(boundary);
                    OGR_G_DestroyGeometry(boundary);
                }
            }
            OCTDestroyCoordinateTransformation(t);
        }
    }

    OSRDestroySpatialReference(wgs);
    OSRDestroySpatialReference(utm);
    return area;
}

struct LayerOutcome {
    std::string gdb;
    std::string source_layer;
    std::string output_layer;
    std::string geometry_type;
    long long source_count = -1;
    long long candidate_count = 0;
    long long output_count = 0;
    std::string status;
    std::string message;
};

std::string sanitize_layer_name(const std::string &gdb_stem, const std::string &layer,
                                std::vector<std::string> &used) {
    std::string base;
    for (char character : (gdb_stem + "_" + layer)) {
        base += (std::isalnum(static_cast<unsigned char>(character)) || character == '_')
                    ? character
                    : '_';
    }
    while (base.size() > 1 && base.front() == '_') base.erase(base.begin());
    while (!base.empty() && base.back() == '_') base.pop_back();
    if (base.empty()) base = "layer";
    if (base.size() > 55) base.resize(55);
    std::string candidate = base;
    int suffix = 2;
    auto taken = [&](const std::string &name) {
        for (const std::string &existing : used) {
            if (existing.size() == name.size()) {
                bool equal = true;
                for (size_t i = 0; i < name.size(); ++i) {
                    if (std::tolower(static_cast<unsigned char>(existing[i])) !=
                        std::tolower(static_cast<unsigned char>(name[i]))) { equal = false; break; }
                }
                if (equal) return true;
            }
        }
        return false;
    };
    while (taken(candidate)) {
        candidate = base + "_" + std::to_string(suffix++);
    }
    used.push_back(candidate);
    return candidate;
}

/// Reads every polygon from the AOI file, unions them and returns the geometry
/// AutoCAD DXF carries no CRS of its own, but survey exports often embed the
/// coordinate system WKT (`PROJCS[...]`) as text. Pull it out with a bracket
/// scan, matching the Windows tool's behaviour.
OGRSpatialReferenceH read_embedded_dxf_srs(const char *path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) return nullptr;
    std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    const size_t start = text.find("PROJCS[");
    if (start == std::string::npos) return nullptr;
    int depth = 0;
    bool quoted = false;
    for (size_t index = start; index < text.size(); ++index) {
        const char character = text[index];
        if (character == '"') quoted = !quoted;
        else if (!quoted && character == '[') depth += 1;
        else if (!quoted && character == ']') {
            depth -= 1;
            if (depth == 0) {
                const std::string wkt = text.substr(start, index - start + 1);
                OGRSpatialReferenceH srs = OSRNewSpatialReference(nullptr);
                if (OSRSetFromUserInput(srs, wkt.c_str()) == OGRERR_NONE) return srs;
                OSRDestroySpatialReference(srs);
                return nullptr;
            }
        }
    }
    return nullptr;
}

/// Reads every polygon from the AOI file (GeoJSON / GeoPackage / DXF), unions
/// them and returns the geometry plus its spatial reference (both owned by the
/// caller). Closed polylines (as produced by DXF) are treated as polygons.
bool load_aoi(const char *aoi_path, OGRGeometryH *out_geometry,
              OGRSpatialReferenceH *out_srs, std::string *error) {
    *out_geometry = nullptr;
    *out_srs = nullptr;
    DatasetGuard dataset;
    dataset.handle = GDALOpenEx(aoi_path, GDAL_OF_VECTOR | GDAL_OF_READONLY, nullptr, nullptr, nullptr);
    if (dataset.handle == nullptr) { *error = "Could not open the AOI file."; return false; }
    OGRLayerH layer = GDALDatasetGetLayer(dataset.handle, 0);
    if (layer == nullptr) { *error = "The AOI file has no layers."; return false; }

    OGRSpatialReferenceH owned_srs = nullptr;
    OGRSpatialReferenceH srs = OGR_L_GetSpatialRef(layer);
    if (srs == nullptr) {
        owned_srs = read_embedded_dxf_srs(aoi_path);
        srs = owned_srs;
    }
    if (srs == nullptr) {
        *error = "The AOI file has no CRS (for DXF, embed the PROJCS WKT).";
        return false;
    }

    GeometryGuard accumulated;
    OGR_L_ResetReading(layer);
    OGRFeatureH feature = nullptr;
    long long polygon_count = 0;
    while ((feature = OGR_L_GetNextFeature(layer)) != nullptr) {
        OGRGeometryH geometry = OGR_F_GetGeometryRef(feature);
        if (geometry != nullptr) {
            const OGRwkbGeometryType flat = wkbFlatten(OGR_G_GetGeometryType(geometry));
            OGRGeometryH candidate = nullptr;
            if (flat == wkbPolygon || flat == wkbMultiPolygon) {
                candidate = OGR_G_Clone(geometry);
            } else if (flat == wkbLineString || flat == wkbMultiLineString ||
                       flat == wkbLinearRing) {
                // A closed polyline drawn as an AOI: force it to a polygon.
                candidate = OGR_G_ForceToPolygon(OGR_G_Clone(geometry));
            }
            if (candidate != nullptr) {
                OGRGeometryH part = OGR_G_IsValid(candidate) ? candidate
                                                            : OGR_G_MakeValid(candidate);
                if (part != candidate) OGR_G_DestroyGeometry(candidate);
                if (part != nullptr && !OGR_G_IsEmpty(part)) {
                    polygon_count += 1;
                    if (accumulated.handle == nullptr) {
                        accumulated.handle = part;
                    } else {
                        OGRGeometryH merged = OGR_G_Union(accumulated.handle, part);
                        OGR_G_DestroyGeometry(part);
                        if (merged != nullptr) {
                            OGR_G_DestroyGeometry(accumulated.handle);
                            accumulated.handle = merged;
                        }
                    }
                } else if (part != nullptr) {
                    OGR_G_DestroyGeometry(part);
                }
            }
        }
        OGR_F_Destroy(feature);
    }
    if (polygon_count == 0 || accumulated.handle == nullptr) {
        if (owned_srs != nullptr) OSRDestroySpatialReference(owned_srs);
        *error = "The AOI file has no polygon (or closed polyline) features.";
        return false;
    }

    *out_srs = (owned_srs != nullptr) ? owned_srs : OSRClone(srs);
    *out_geometry = accumulated.release();
    return true;
}

} // namespace
#endif

char *landclip_clip_package_json(const char *gdb_paths_json,
                                 const char *aoi_path,
                                 const char *out_gpkg_path,
                                 const char *out_csv_path,
                                 const char *options_json,
                                 landclip_progress_callback progress,
                                 void *progress_context,
                                 char **error_message) {
    if (error_message != nullptr) *error_message = nullptr;
#if LANDCLIP_WITH_GDAL
    if (gdb_paths_json == nullptr || aoi_path == nullptr || out_gpkg_path == nullptr ||
        out_csv_path == nullptr) {
        if (error_message != nullptr) *error_message = copy_string("Clip arguments are incomplete.");
        return nullptr;
    }

    GDALAllRegister();
    const std::vector<std::string> gdb_paths = parse_json_string_array(gdb_paths_json);
    if (gdb_paths.empty()) {
        if (error_message != nullptr) *error_message = copy_string("No geodatabase paths supplied.");
        return nullptr;
    }
    const std::vector<std::string> only_layers = parse_json_array_after_key(options_json, "layers");
    const std::vector<std::string> skip_layers = parse_json_array_after_key(options_json, "skipLayers");

    report_progress(progress, progress_context,
                    "{\"event\":\"phase\",\"phase\":\"aoi\"}");
    GeometryGuard aoi;
    OGRSpatialReferenceH aoi_srs = nullptr;
    std::string load_error;
    if (!load_aoi(aoi_path, &aoi.handle, &aoi_srs, &load_error)) {
        if (error_message != nullptr) *error_message = copy_string(load_error.c_str());
        return nullptr;
    }
    struct SrsGuard {
        OGRSpatialReferenceH h = nullptr;
        ~SrsGuard() { if (h != nullptr) OSRDestroySpatialReference(h); }
    } aoi_srs_guard;
    aoi_srs_guard.h = aoi_srs;

    double aoi_perimeter_m = 0.0;
    const double aoi_area_m2 = compute_aoi_metrics(aoi.handle, aoi_srs, &aoi_perimeter_m);

    GDALDriverH gpkg_driver = GDALGetDriverByName("GPKG");
    if (gpkg_driver == nullptr) {
        if (error_message != nullptr) *error_message = copy_string("The GPKG driver is unavailable.");
        return nullptr;
    }
    // Resume: when some layers are being skipped and the output already exists,
    // append to it instead of starting over.
    VSIStatBufL out_stat;
    const bool resuming = !skip_layers.empty() && VSIStatL(out_gpkg_path, &out_stat) == 0;
    DatasetGuard out_dataset;
    if (resuming) {
        out_dataset.handle = GDALOpenEx(out_gpkg_path, GDAL_OF_VECTOR | GDAL_OF_UPDATE,
                                        nullptr, nullptr, nullptr);
    }
    if (out_dataset.handle == nullptr) {
        VSIUnlink(out_gpkg_path);
        out_dataset.handle = GDALCreate(gpkg_driver, out_gpkg_path, 0, 0, 0, GDT_Unknown, nullptr);
    }
    if (out_dataset.handle == nullptr) {
        if (error_message != nullptr) *error_message = copy_string("Could not create the output GeoPackage.");
        return nullptr;
    }

    std::vector<LayerOutcome> outcomes;
    std::vector<std::string> used_names;
    bool cancelled = false;

    report_progress(progress, progress_context,
                    "{\"event\":\"phase\",\"phase\":\"process\"}");

    for (const std::string &gdb_path : gdb_paths) {
        if (cancelled) break;
        std::string gdb_stem = gdb_path;
        const size_t slash = gdb_stem.find_last_of("/\\");
        if (slash != std::string::npos) gdb_stem = gdb_stem.substr(slash + 1);
        const size_t dot = gdb_stem.find_last_of('.');
        if (dot != std::string::npos) gdb_stem = gdb_stem.substr(0, dot);

        const char *allowed[] = {"OpenFileGDB", nullptr};
        DatasetGuard source;
        source.handle = GDALOpenEx(gdb_path.c_str(), GDAL_OF_VECTOR | GDAL_OF_READONLY,
                                   allowed, nullptr, nullptr);
        if (source.handle == nullptr) {
            LayerOutcome outcome;
            outcome.gdb = gdb_stem;
            outcome.status = "error";
            outcome.message = "Could not open geodatabase.";
            outcomes.push_back(outcome);
            continue;
        }

        const int layer_count = GDALDatasetGetLayerCount(source.handle);
        for (int index = 0; index < layer_count && !cancelled; ++index) {
            OGRLayerH layer = GDALDatasetGetLayer(source.handle, index);
            if (layer == nullptr) continue;
            OGRFeatureDefnH defn = OGR_L_GetLayerDefn(layer);
            const std::string layer_name = OGR_FD_GetName(defn);
            const OGRwkbGeometryType geom_type = OGR_FD_GetGeomType(defn);
            const std::string family = geometry_family(geom_type);

            const std::string layer_key = gdb_stem + "::" + layer_name;
            if (!only_layers.empty() && !set_contains(only_layers, layer_key)) {
                continue;  // deselected — omit from the summary entirely
            }

            LayerOutcome outcome;
            outcome.gdb = gdb_stem;
            outcome.source_layer = layer_name;
            outcome.geometry_type = geometry_type_name(geom_type);
            outcome.source_count = OGR_L_GetFeatureCount(layer, false);
            // Reserve the deterministic output name for every layer we keep, so
            // resumed runs name their new layers exactly as the first run did.
            outcome.output_layer = sanitize_layer_name(gdb_stem, layer_name, used_names);

            if (set_contains(skip_layers, layer_key)) {
                outcome.status = "reused";
                outcome.message = "đã xử lý ở lần trước";
                outcomes.push_back(outcome);
                continue;
            }

            {
                std::ostringstream event;
                event << "{\"event\":\"layer_start\",\"gdb\":" << json_string(gdb_stem.c_str())
                      << ",\"layer\":" << json_string(layer_name.c_str())
                      << ",\"geometryType\":" << json_string(outcome.geometry_type.c_str())
                      << ",\"sourceCount\":" << outcome.source_count << "}";
                if (report_progress(progress, progress_context, event.str())) { cancelled = true; break; }
            }

            OGRSpatialReferenceH layer_srs = OGR_L_GetSpatialRef(layer);
            if (family.empty() || layer_srs == nullptr) {
                outcome.status = "skipped";
                outcome.message = family.empty()
                    ? "không phải Point/Line/Polygon (annotation, bảng, hoặc 3D đặc thù)"
                    : "layer không có CRS";
                outcomes.push_back(outcome);
                std::ostringstream event;
                event << "{\"event\":\"layer_done\",\"gdb\":" << json_string(gdb_stem.c_str())
                      << ",\"layer\":" << json_string(layer_name.c_str())
                      << ",\"status\":" << json_string(outcome.status.c_str())
                      << ",\"candidateCount\":0,\"outputCount\":0}";
                if (report_progress(progress, progress_context, event.str())) { cancelled = true; break; }
                continue;
            }

            GeometryGuard local_aoi;
            local_aoi.handle = OGR_G_Clone(aoi.handle);
            if (!OSRIsSame(aoi_srs, layer_srs)) {
                OGRCoordinateTransformationH transform =
                    OCTNewCoordinateTransformation(aoi_srs, layer_srs);
                if (transform == nullptr) {
                    outcome.status = "skipped";
                    outcome.message = "no transform to layer CRS";
                    outcomes.push_back(outcome);
                    continue;
                }
                const OGRErr err = OGR_G_Transform(local_aoi.handle, transform);
                OCTDestroyCoordinateTransformation(transform);
                if (err != OGRERR_NONE) {
                    outcome.status = "skipped";
                    outcome.message = "AOI transform failed";
                    outcomes.push_back(outcome);
                    continue;
                }
            }

            OGR_L_SetSpatialFilter(layer, local_aoi.handle);
            OGR_L_ResetReading(layer);

            const std::string &output_name = outcome.output_layer;
            OGRLayerH out_layer = nullptr;
            const bool is_point = (family == "Point");

            OGRFeatureH feature = nullptr;
            while ((feature = OGR_L_GetNextFeature(layer)) != nullptr) {
                outcome.candidate_count += 1;
                OGRGeometryH geometry = OGR_F_GetGeometryRef(feature);
                if (geometry == nullptr || !OGR_G_Intersects(geometry, local_aoi.handle)) {
                    OGR_F_Destroy(feature);
                    continue;
                }
                GeometryGuard result_geometry;
                if (is_point) {
                    result_geometry.handle = OGR_G_Clone(geometry);
                } else {
                    GeometryGuard repaired;
                    OGRGeometryH usable = geometry;
                    if (!OGR_G_IsValid(geometry)) {
                        repaired.handle = OGR_G_MakeValid(geometry);
                        usable = repaired.handle;
                    }
                    if (usable != nullptr) {
                        result_geometry.handle = OGR_G_Intersection(usable, local_aoi.handle);
                    }
                }
                if (result_geometry.handle == nullptr || OGR_G_IsEmpty(result_geometry.handle)) {
                    OGR_F_Destroy(feature);
                    continue;
                }

                if (out_layer == nullptr) {
                    out_layer = GDALDatasetCreateLayer(out_dataset.handle, output_name.c_str(),
                                                       layer_srs, wkbUnknown, nullptr);
                    if (out_layer == nullptr) {
                        outcome.status = "error";
                        outcome.message = "could not create output layer";
                        OGR_F_Destroy(feature);
                        break;
                    }
                    for (int f = 0; f < OGR_FD_GetFieldCount(defn); ++f) {
                        OGR_L_CreateField(out_layer, OGR_FD_GetFieldDefn(defn, f), TRUE);
                    }
                }

                OGRFeatureH out_feature = OGR_F_Create(OGR_L_GetLayerDefn(out_layer));
                OGR_F_SetFrom(out_feature, feature, TRUE);
                OGR_F_SetGeometryDirectly(out_feature, result_geometry.release());
                if (OGR_L_CreateFeature(out_layer, out_feature) == OGRERR_NONE) {
                    outcome.output_count += 1;
                }
                OGR_F_Destroy(out_feature);
                OGR_F_Destroy(feature);
            }
            OGR_L_SetSpatialFilter(layer, nullptr);

            if (outcome.status.empty()) {
                outcome.status = outcome.output_count > 0 ? "written" : "empty";
            }
            outcomes.push_back(outcome);

            std::ostringstream event;
            event << "{\"event\":\"layer_done\",\"gdb\":" << json_string(gdb_stem.c_str())
                  << ",\"layer\":" << json_string(layer_name.c_str())
                  << ",\"status\":" << json_string(outcome.status.c_str())
                  << ",\"candidateCount\":" << outcome.candidate_count
                  << ",\"outputCount\":" << outcome.output_count << "}";
            if (report_progress(progress, progress_context, event.str())) { cancelled = true; }
        }
    }

    // Flush the GeoPackage before anyone reads it back.
    GDALClose(out_dataset.handle);
    out_dataset.handle = nullptr;

    // On cancel we keep the GeoPackage: every cancel lands on a layer boundary,
    // so it only holds fully-written layers — a later run resumes from here.

    std::ofstream csv(out_csv_path, std::ios::binary);
    csv << "gdb,source_layer,output_layer,geometry_type,source_count,candidate_count,"
           "output_count,status,message\n";
    long long written_layers = 0;
    std::ostringstream summary;
    summary << "{\"outputGeoPackage\":" << json_string(out_gpkg_path)
            << ",\"summaryCsv\":" << json_string(out_csv_path)
            << ",\"cancelled\":" << (cancelled ? "true" : "false")
            << ",\"aoiAreaSqMeters\":" << aoi_area_m2
            << ",\"aoiPerimeterMeters\":" << aoi_perimeter_m
            << ",\"layers\":[";
    for (size_t i = 0; i < outcomes.size(); ++i) {
        const LayerOutcome &outcome = outcomes[i];
        if (outcome.status == "written") written_layers += 1;
        csv << csv_cell(outcome.gdb) << ',' << csv_cell(outcome.source_layer) << ','
            << csv_cell(outcome.output_layer) << ',' << csv_cell(outcome.geometry_type) << ','
            << (outcome.source_count < 0 ? std::string() : std::to_string(outcome.source_count)) << ','
            << outcome.candidate_count << ',' << outcome.output_count << ','
            << csv_cell(outcome.status) << ',' << csv_cell(outcome.message) << '\n';
        if (i > 0) summary << ',';
        summary << "{\"gdb\":" << json_string(outcome.gdb.c_str())
                << ",\"sourceLayer\":" << json_string(outcome.source_layer.c_str())
                << ",\"outputLayer\":" << json_string(outcome.output_layer.c_str())
                << ",\"geometryType\":" << json_string(outcome.geometry_type.c_str())
                << ",\"sourceCount\":" << outcome.source_count
                << ",\"candidateCount\":" << outcome.candidate_count
                << ",\"outputCount\":" << outcome.output_count
                << ",\"status\":" << json_string(outcome.status.c_str())
                << ",\"message\":" << json_string(outcome.message.c_str()) << '}';
    }
    summary << "],\"writtenLayerCount\":" << written_layers << "}";
    csv.close();

    report_progress(progress, progress_context,
                    cancelled ? "{\"event\":\"cancelled\"}" : "{\"event\":\"complete\"}");
    return copy_string(summary.str().c_str());
#else
    (void)gdb_paths_json;
    (void)aoi_path;
    (void)out_gpkg_path;
    (void)out_csv_path;
    (void)options_json;
    (void)progress;
    (void)progress_context;
    if (error_message != nullptr) *error_message = copy_string("GISCore was built without GDAL.");
    return nullptr;
#endif
}

char *landclip_read_layer_geojson(const char *dataset_path,
                                  const char *layer_name,
                                  int max_features,
                                  char **error_message) {
    if (error_message != nullptr) *error_message = nullptr;
#if LANDCLIP_WITH_GDAL
    if (dataset_path == nullptr || layer_name == nullptr) {
        if (error_message != nullptr) *error_message = copy_string("Layer preview arguments are incomplete.");
        return nullptr;
    }
    GDALAllRegister();
    GDALDatasetH source = GDALOpenEx(dataset_path, GDAL_OF_VECTOR | GDAL_OF_READONLY,
                                     nullptr, nullptr, nullptr);
    if (source == nullptr) {
        if (error_message != nullptr) *error_message = copy_string("Could not open the dataset.");
        return nullptr;
    }

    // RFC7946=YES makes the GeoJSON driver reproject to WGS 84 (CRS84) on its own.
    char **argv = nullptr;
    argv = CSLAddString(argv, "-f");
    argv = CSLAddString(argv, "GeoJSON");
    argv = CSLAddString(argv, "-lco");
    argv = CSLAddString(argv, "RFC7946=YES");
    if (max_features > 0) {
        argv = CSLAddString(argv, "-limit");
        argv = CSLAddString(argv, std::to_string(max_features).c_str());
    }
    argv = CSLAddString(argv, layer_name);

    GDALVectorTranslateOptions *options = GDALVectorTranslateOptionsNew(argv, nullptr);
    CSLDestroy(argv);
    if (options == nullptr) {
        GDALClose(source);
        if (error_message != nullptr) *error_message = copy_string("Invalid preview options.");
        return nullptr;
    }

    const char *memory_path = "/vsimem/landclip_preview.geojson";
    VSIUnlink(memory_path);
    int usage_error = FALSE;
    GDALDatasetH output = GDALVectorTranslate(memory_path, nullptr, 1, &source, options, &usage_error);
    GDALVectorTranslateOptionsFree(options);
    GDALClose(source);
    if (output == nullptr) {
        VSIUnlink(memory_path);
        if (error_message != nullptr) *error_message = copy_string("Could not export the layer.");
        return nullptr;
    }
    GDALClose(output);

    vsi_l_offset length = 0;
    GByte *buffer = VSIGetMemFileBuffer(memory_path, &length, FALSE);
    char *result = nullptr;
    if (buffer != nullptr) {
        result = static_cast<char *>(std::malloc(static_cast<size_t>(length) + 1));
        if (result != nullptr) {
            std::memcpy(result, buffer, static_cast<size_t>(length));
            result[length] = '\0';
        }
    }
    VSIUnlink(memory_path);
    if (result == nullptr && error_message != nullptr) {
        *error_message = copy_string("Empty layer export.");
    }
    return result;
#else
    (void)dataset_path;
    (void)layer_name;
    (void)max_features;
    if (error_message != nullptr) *error_message = copy_string("GISCore was built without GDAL.");
    return nullptr;
#endif
}
