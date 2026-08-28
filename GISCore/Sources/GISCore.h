#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Progress and cooperative-cancellation callback shared by the long-running
/// operations below. `event_json` is a UTF-8 JSON object describing the current
/// step (always has an `"event"` key). Return a non-zero value to request
/// cancellation; the operation then stops at the next safe boundary, reports
/// failure and removes any partial output.
typedef int (*landclip_progress_callback)(void *context, const char *event_json);

const char *landclip_gis_engine_version(void);

/// Returns 1 when GISCore was linked with GDAL, otherwise 0.
int landclip_gis_has_gdal(void);

/// Configures runtime data directories copied into the application bundle.
void landclip_gis_configure_data_paths(const char *gdal_data_path,
                                       const char *proj_data_path);

/// Reads an unpacked File Geodatabase and returns a UTF-8 JSON catalog.
/// The returned string and error string (when present) must be released with
/// landclip_gis_free_string().
char *landclip_gis_copy_gdb_catalog_json(const char *gdb_path,
                                         char **error_message);

void landclip_gis_free_string(char *value);

/// Extracts a ZIP-compatible PPKX into an existing destination directory.
/// Returns 1 on success. The caller owns error_message when present.
/// `progress` may be NULL; when set it receives `{"event":"extract",...}` events
/// and can cancel the extraction.
int landclip_archive_extract_ppkx(const char *package_path,
                                  const char *destination_path,
                                  landclip_progress_callback progress,
                                  void *progress_context,
                                  char **error_message);

/// Clips every supported vector layer of the given File Geodatabases against a
/// polygonal AOI and writes one GeoPackage (a layer per source layer that has
/// results) plus a CSV summary.
///
/// - gdb_paths_json: JSON array of absolute `.gdb` directory paths.
/// - aoi_path: a GeoJSON, GeoPackage or DXF file holding one or more polygons
///   (or closed polylines); all are unioned. The file must carry a CRS.
/// - out_gpkg_path / out_csv_path: destinations, must not already exist.
/// - options_json: may be NULL. `{"layers":["gdb::name",...]}` restricts the run
///   to those source layers; `{"skipLayers":["gdb::name",...]}` marks layers as
///   already done (status "reused") for resume-after-stop.
/// - progress: may be NULL; receives `phase` / `layer_start` / `layer_done` /
///   `complete` events and can cancel at layer boundaries.
///
/// Returns a UTF-8 JSON summary string (owned by the caller) on success, or NULL
/// with `error_message` set. The summary carries `aoiAreaSqMeters`,
/// `aoiPerimeterMeters`, `writtenLayerCount` and a `layers` array. A failure in
/// one layer is recorded in the summary and does not abort the job.
char *landclip_clip_package_json(const char *gdb_paths_json,
                                 const char *aoi_path,
                                 const char *out_gpkg_path,
                                 const char *out_csv_path,
                                 const char *options_json,
                                 landclip_progress_callback progress,
                                 void *progress_context,
                                 char **error_message);

/// Exports up to `max_features` features of one layer (of a GeoPackage or File
/// Geodatabase) as a WGS-84 GeoJSON FeatureCollection string, for map preview.
/// `max_features <= 0` means no limit. Owned by the caller; NULL + error_message
/// on failure.
char *landclip_read_layer_geojson(const char *dataset_path,
                                  const char *layer_name,
                                  int max_features,
                                  char **error_message);

#ifdef __cplusplus
}
#endif
