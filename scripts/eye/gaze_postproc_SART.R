#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(fs)
  library(dplyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(tidyr)
})

# ------------------------------------------------------
# Setup paths
# ------------------------------------------------------
ROOT_DIR <- normalizePath("/project2/elisab_1216/projects/ELM/", mustWork = TRUE)
OUT_DIR  <- file.path(ROOT_DIR, "outputs")

# SART preprocessing output from the earlier pipeline
INPUT_DIR <- file.path(OUT_DIR, "pre_processedSART")

# Where this script writes outputs
POST_DIR  <- file.path(OUT_DIR, "post_processedSART")
DATA_DIR  <- file.path(POST_DIR, "data")

SUM_FILE <- file.path(OUT_DIR, "summary_interp.csv")

dir.create(POST_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(DATA_DIR, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------
# Load interpolation summary
# ------------------------------------------------------
if (!file.exists(SUM_FILE)) {
  stop("Missing summary file: ", SUM_FILE)
}
summary_interp <- read_csv(SUM_FILE, show_col_types = FALSE)

if (!"id" %in% names(summary_interp)) {
  stop("summary_interp.csv must contain an id column")
}
if (!"prop_interp_any" %in% names(summary_interp)) {
  stop("summary_interp.csv must contain prop_interp_any")
}

# ------------------------------------------------------
# Discover preprocessed SART files
# ------------------------------------------------------
pre_files <- fs::dir_ls(INPUT_DIR, type = "file")
pre_files <- pre_files[str_detect(fs::path_file(pre_files), "^data_preprocessedSART_.*\\.csv$")]

cat("🔍 Found", length(pre_files), "preprocessed files\n")

if (!length(pre_files)) {
  cat("Contents of INPUT_DIR:\n")
  print(fs::dir_ls(INPUT_DIR, type = "file"))
  stop("❌ No data_preprocessedSART_*.csv files found in ", INPUT_DIR)
}

# ------------------------------------------------------
# Helpers
# ------------------------------------------------------
extract_file_id <- function(path) {
  base <- fs::path_file(path)
  str_match(base, "^data_preprocessedSART_(.*)\\.csv$")[, 2]
}

file_ids <- map_chr(pre_files, extract_file_id)

# ------------------------------------------------------
# Determine valid IDs by interpolation threshold
# ------------------------------------------------------
drop_threshold <- 0.20

# Aggressive Filtering
#valid_ids_raw <- summary_interp %>%
  #filter(prop_interp_any < drop_threshold) %>%
  #pull(id) %>%
  #as.character()

# Liberal Filtering, accounts for binocular fallback approach in preprocessing
valid_ids_raw <- summary_interp %>%
  filter(!(prop_interp_psl >= drop_threshold &
           prop_interp_psr >= drop_threshold)) %>%
  pull(id) %>%
  as.character()
  
# Optional explicit exclusion if you have a known bad file
exclude_ids <- character(0)
valid_ids <- setdiff(valid_ids_raw, exclude_ids)

valid_files <- pre_files[file_ids %in% valid_ids]

cat("✅ Valid IDs:", length(unique(valid_ids)), "\n")
cat("📂 Valid files:", length(valid_files), "\n")

if (length(valid_files) == 0) {
  stop("❌ No valid files found — check ID matching or threshold")
}

# ------------------------------------------------------
# Load, validate, and optionally safety-trim practice rows
# ------------------------------------------------------
valid_df_index <- tibble(
  path = valid_files,
  id   = map_chr(valid_files, extract_file_id)
) %>%
  mutate(
    df = map(path, ~ read_csv(.x, show_col_types = FALSE)),
    # safety: if Practice rows still exist, remove them here
    df_trimmed = map(df, ~ {
      if ("blockId" %in% names(.x)) {
        dplyr::filter(.x, is.na(blockId) | blockId != "Practice")
      } else {
        .x
      }
    }),
    n_rows_before = map_int(df, nrow),
    n_rows_after  = map_int(df_trimmed, nrow)
  )

# ------------------------------------------------------
# Diagnostics
# ------------------------------------------------------
trim_diag <- valid_df_index %>%
  transmute(
    id,
    n_rows_before,
    n_rows_after,
    rows_removed = n_rows_before - n_rows_after
  )

write_csv(
  trim_diag,
  file.path(POST_DIR, "trim_diagnostic_by_subject.csv")
)
cat("📝 Saved trim_diagnostic_by_subject.csv\n")

# ------------------------------------------------------
# Write retained files
# ------------------------------------------------------
cat("📂 Writing retained files to DATA_DIR...\n")

for (i in seq_len(nrow(valid_df_index))) {
  df_out <- valid_df_index$df_trimmed[[i]]
  id     <- valid_df_index$id[[i]]

  out_name <- paste0("data_preprocessedSART_", id, ".csv")
  out_path <- file.path(DATA_DIR, out_name)

  if (file.exists(out_path)) {
    warning("⚠️ Overwriting existing file: ", out_name)
  }

  write_csv(df_out, out_path)
}

cat("✅ Finished writing retained files\n")

# ------------------------------------------------------
# Create mapping for retained files
# ------------------------------------------------------
output_files <- fs::dir_ls(DATA_DIR, type = "file", regexp = "\\.csv$")

extract_id_from_output <- function(path) {
  base <- fs::path_file(path)
  str_match(base, "^data_preprocessedSART_(.*)\\.csv$")[, 2]
}

id_map <- tibble(
  output_filename = fs::path_file(output_files),
  extracted_id    = extract_id_from_output(output_files)
)

if (any(is.na(id_map$extracted_id))) {
  stop("❌ Failed to extract id from trimmed filenames")
}

write_csv(
  id_map,
  file.path(POST_DIR, "original_id_map.csv")
)
cat("📝 Saved original_id_map.csv\n")

# ------------------------------------------------------
# Build inclusion summary
# ------------------------------------------------------
included_subjects <- id_map$extracted_id %>% unique() %>% length()
included_trial_files <- nrow(id_map)

summary_df <- tibble(
  metric = c("n_subjects_included", "n_trial_files_included"),
  value  = c(included_subjects, included_trial_files)
)

write_csv(
  summary_df,
  file.path(POST_DIR, "inclusion_summary.csv")
)

# ------------------------------------------------------
# Count subjects retained
# ------------------------------------------------------
subject_summary <- id_map %>%
  distinct(extracted_id) %>%
  count(name = "n_subjects")

write_csv(
  subject_summary,
  file.path(POST_DIR, "subjects_retained.csv")
)

# ------------------------------------------------------
# Final reporting
# ------------------------------------------------------
cat("📊 Saved summary CSVs:\n")
cat("  - original_id_map.csv\n")
cat("  - inclusion_summary.csv\n")
cat("  - subjects_retained.csv\n")

cat("\n🎉 DONE — retention based on interpolation threshold completed.\n")
cat("   Output folder:\n")
cat("   ", POST_DIR, "\n")

