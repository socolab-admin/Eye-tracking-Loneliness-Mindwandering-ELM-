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
ROOT_DIR   <- normalizePath("/project2/elisab_1216/projects/ELM/", mustWork = TRUE)
OUT_DIR    <- file.path(ROOT_DIR, "outputs")
PRE_DIR    <- file.path(OUT_DIR, "pre_processed_step1")
INPUT_DIR  <- file.path(OUT_DIR, "pre_processed_step1/data")
POST_DIR   <- file.path(OUT_DIR, "pre_processed_step3")
DATA_DIR   <- file.path(OUT_DIR, "pre_processed_step3/data")
UNTRIMMED_DIR <- file.path(OUT_DIR, "pre_processed_step3/untrimmed_data")

SUM_FILE   <- file.path(PRE_DIR, "summary_interp.csv")
ALIGN_FILE <- file.path(OUT_DIR, "pre_processed_step2/align_summary.csv")

dir.create(POST_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(DATA_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(UNTRIMMED_DIR, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------
# Load summary_interp
# ------------------------------------------------------
summary_interp <- read_csv(SUM_FILE, show_col_types = FALSE)

# ------------------------------------------------------
# Discover preprocessed qc files
# ------------------------------------------------------
pre_files <- fs::dir_ls(INPUT_DIR, type = "file", glob = "*qc_preprocessed_*.csv")
cat("🔍 Found", length(pre_files), "preprocessed files\n")

# ------------------------------------------------------
# Helpers
# ------------------------------------------------------
extract_file_id <- function(path) {
  base <- fs::path_file(path)
  str_match(base, "^qc_preprocessed_(.*)\\.csv$")[,2]
}

extract_id <- function(path) {
  base <- fs::path_file(path)
  id <- str_match(base, "^qc_preprocessed_([0-9]+)[A-Za-z]*_")[,2]
  if (is.na(id)) stop("❌ Could not extract ID from filename: ", base)
  id
}

file_ids <- extract_file_id(pre_files)

# ------------------------------------------------------
# Determine valid IDs
# ------------------------------------------------------
drop_threshold <- 0.2

# Aggressive Filtering
#valid_ids_raw <- summary_interp %>%
  #filter(prop_interp_any < drop_threshold) %>%
  #pull(id)

# Liberal Filtering, accounts for binocular fallback approach in preprocessing
valid_ids_raw <- summary_interp %>%
  filter(!(prop_interp_psl >= drop_threshold &
           prop_interp_psr >= drop_threshold)) %>%
  pull(id)

# Explicit exclusion (timestamp-style ID)
valid_ids <- setdiff(valid_ids_raw, "01_2025_02_14_15_18")

valid_files <- pre_files[file_ids %in% valid_ids]

cat("✅ Valid subjects:", length(unique(map_chr(valid_files, extract_id))), "\n")
cat("📂 Valid files:", length(valid_files), "\n")

if (length(valid_files) == 0) {
  stop("❌ No valid files found — check ID matching")
}

# ------------------------------------------------------
# Load and validate alignment summary
# ------------------------------------------------------
align_summary <- read_csv(ALIGN_FILE, show_col_types = FALSE)

align_valid <- align_summary %>%
  filter(id %in% valid_ids)

# ------------------------------------------------------
# Compute common usable end per stimulus
# ------------------------------------------------------
stim_trim <- align_valid %>%
  group_by(stimulus) %>%
  summarize(
    common_usable_start = if (all(is.na(usable_start))) NA_real_ else max(usable_start, na.rm = TRUE),
    common_usable_end   = if (all(is.na(usable_end)))   NA_real_ else min(usable_end, na.rm = TRUE),
    n_subjects = n_distinct(id),
    .groups = "drop"
  )

if (any(is.na(stim_trim$common_usable_end))) {
  stop("❌ At least one stimulus has no usable_end across subjects")
}

write_csv(
  stim_trim,
  file.path(POST_DIR, "stimulus_common_usable_end.csv")
)

cat("📝 Saved stimulus_common_usable_end.csv\n")

# ------------------------------------------------------
# Load, validate, and trim data
# ------------------------------------------------------
valid_df_index <- tibble(
  path = valid_files,
  id   = map_chr(valid_files, extract_id)
) %>%
  mutate(
    df = map(path, ~ read_csv(.x, show_col_types = FALSE)),
    stimulus = map_chr(df, ~ {
      s <- unique(.x$stimulus)
      if (length(s) != 1) stop("❌ Multiple stimulus labels in file")
      s
    })
  ) %>%
  left_join(stim_trim, by = "stimulus")

if (any(is.na(valid_df_index$common_usable_end))) {
  stop("❌ Missing common usable end after join — stimulus mismatch")
}

if (any(is.na(valid_df_index$common_usable_start))) {
  stop("Missing common usable start after join — stimulus mismatch")
}


# Write untrimmed valid files
cat("Writing untrimmed valid files...\n")

for (i in seq_len(nrow(valid_df_index))) {

  df_out <- valid_df_index$df[[i]]
  id     <- valid_df_index$id[[i]]
  stim   <- valid_df_index$stimulus[[i]]

  out_name <- paste0(id, "_", stim, ".csv")
  out_path <- file.path(UNTRIMMED_DIR, out_name)

  write_csv(df_out, out_path)
}

cat("Finished writing untrimmed valid files\n")

# Write trimmed valid files
trimmed_df_index <- valid_df_index %>%
  mutate(
    df_trimmed = pmap(list(df, common_usable_start, common_usable_end), 
                       function(df, start, end) {
                         if (!"t_rel_ms" %in% names(df)) stop("Missing t_rel_ms column")
                         filter(df, t_rel_ms >= start, t_rel_ms <= end)
                       }),
    original_start_time = map_dbl(df, ~ min(.x$t_rel_ms, na.rm = TRUE)),
    original_end_time   = map_dbl(df, ~ max(.x$t_rel_ms, na.rm = TRUE)),
    trimmed_start_time  = map_dbl(df_trimmed, ~ min(.x$t_rel_ms, na.rm = TRUE)),
    trimmed_end_time    = map_dbl(df_trimmed, ~ max(.x$t_rel_ms, na.rm = TRUE)),
    time_removed_start  = trimmed_start_time - original_start_time,
    time_removed_end    = original_end_time - trimmed_end_time
  )
  
  trimmed_df_index <- trimmed_df_index %>%
  mutate(trimmed_duration = trimmed_end_time - trimmed_start_time)
# ------------------------------------------------------
# Diagnostics
# ------------------------------------------------------
trim_diag <- trimmed_df_index %>%
  select(
    id,
    stimulus,
    original_start_time,
    common_usable_start,
    trimmed_start_time,
    time_removed_start,
    original_end_time,
    common_usable_end,
    trimmed_end_time,
    time_removed_end
  )

write_csv(
  trim_diag,
  file.path(POST_DIR, "trim_diagnostic_by_subject.csv")
)

cat("📝 Saved trim_diagnostic_by_subject.csv\n")

# ------------------------------------------------------
# Write trimmed files
# ------------------------------------------------------
cat("📂 Writing trimmed files to DATA_DIR...\n")

for (i in seq_len(nrow(trimmed_df_index))) {
  
  df_out <- trimmed_df_index$df_trimmed[[i]]
  id     <- trimmed_df_index$id[[i]]
  stim   <- trimmed_df_index$stimulus[[i]]
  
  out_name <- paste0(id, "_", stim, ".csv")
  out_path <- file.path(DATA_DIR, out_name)
  
  if (file.exists(out_path)) {
    warning("⚠️ Overwriting existing file: ", out_name)
  }
  
  write_csv(df_out, out_path)
}

cat("✅ Finished writing trimmed files\n")
cat("🎉 DONE — trimming successful and verified\n")

# ------------------------------------------------------
# Create mapping ONLY for trimmed valid files
# ------------------------------------------------------

output_files <- fs::dir_ls(DATA_DIR, type = "file", glob = "*.csv")

extract_id_from_output <- function(path) {
  base <- fs::path_file(path)
  str_match(base, "^([0-9]+)_")[,2]
}

extract_stim_from_output <- function(path) {
  base <- fs::path_file(path)
  str_match(base, "^[0-9]+_(.*)\\.csv$")[,2]
}

id_map <- tibble(
  output_filename = fs::path_file(output_files),
  extracted_id    = extract_id_from_output(output_files),
  stimulus        = extract_stim_from_output(output_files)
)

# Sanity check
if (any(is.na(id_map$extracted_id)) | any(is.na(id_map$stimulus))) {
  stop("❌ Failed to extract id or stimulus from trimmed filenames")
}

write_csv(
  id_map,
  file.path(POST_DIR, "original_id_map.csv")
)

cat("📝 Saved original_id_map.csv (trimmed valid files only)\n")

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
# Count subjects per stimulus
# ------------------------------------------------------

stim_summary <- id_map %>%
  distinct(extracted_id, stimulus) %>%
  count(stimulus, name = "n_subjects")

write_csv(
  stim_summary,
  file.path(POST_DIR, "subjects_by_stimulus.csv")
)

# ------------------------------------------------------
# Final reporting
# ------------------------------------------------------

cat("Saved summary CSVs:\n")
cat("  - original_id_map.csv\n")
cat("  - inclusion_summary.csv\n")
cat("  - subjects_by_stimulus.csv\n")

cat("\n🎉 DONE — trimmed, aligned, and summarized outputs saved in:\n")
cat("   ", POST_DIR, "\n")

