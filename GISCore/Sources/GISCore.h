#pragma once

#ifdef __cplusplus
extern "C" {
#endif

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
int landclip_archive_extract_ppkx(const char *package_path,
                                  const char *destination_path,
                                  char **error_message);

#ifdef __cplusplus
}
#endif
