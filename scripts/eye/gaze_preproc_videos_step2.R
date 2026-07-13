#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(fs)
  library(readr)
  library(dplyr)
})

# -----------------------
# CONFIG DIRECTORIES
# -----------------------
ROOT_DIR        <- normalizePath("/project2/elisab_1216/projects/ELM/", mustWork = TRUE)
PREPROCESS1_DIR <- file.path(ROOT_DIR, "outputs/pre_processed_step1")
INPUT_DIR       <- file.path(PREPROCESS1_DIR, "data")
OUTPUT_DIR      <- file.path(ROOT_DIR, "outputs/pre_processed_step2")
DATA_DIR        <- file.path(OUTPUT_DIR, "data")
VIDEO_DUR_FILE  <- file.path(ROOT_DIR, "videos/video_durations.csv")
DIAG_FILE       <- file.path(OUTPUT_DIR, "align_summary.csv")

# ensure dirs exist
dir.create(INPUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(DATA_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ========================================================
# DISCOVER INPUT FILES
# ========================================================
all_files <- fs::dir_ls(INPUT_DIR, type = "file")
files <- all_files[grepl("^qc_preprocessed_.*\\.csv$", fs::path_file(all_files))]
if (!length(files)) stop("No qc_preprocessed_*.csv files found in ", INPUT_DIR)

id_from <- function(p) {
  base <- fs::path_file(p)
  sub("^qc_preprocessed_", "", base) %>% sub("\\.csv$", "", .)
}
ids <- id_from(files)
ord <- order(ids)
files <- files[ord]
ids   <- ids[ord]

cat("📦 Found", length(files), "qc_preprocessed files\n")

# ==========
# SLURM / TASK ID
# ==========
args <- commandArgs(trailingOnly = TRUE)
task_id <- if (length(args)) as.integer(args[1]) else NA_integer_

if (!is.finite(task_id) || task_id < 1 || task_id > length(ids)) {
  cat("No work for task_id =", task_id, " (total =", length(ids), ")\n")
  quit(save="no", status=0)
}

id   <- ids[task_id]
path <- files[task_id]
cat("👉 Processing ID:", id, "\n")

# ========================================================
# LOAD VIDEO DURATIONS
# ========================================================
video_durations <- read_csv(VIDEO_DUR_FILE, show_col_types = FALSE)

# ========================================================
# LOAD QC DATA
# ========================================================
df <- read_csv(path, show_col_types = FALSE)
stim <- unique(df$stimulus)
if (length(stim) != 1) stop("Multiple stimuli in file: ", path)

video_duration <- video_durations$duration_ms[video_durations$stimulus == stim]
if (!length(video_duration)) stop("Missing video duration for ", stim)

# ========================================================
# HELPER — usable start/end & invalids
# ========================================================
priority_cols <- intersect(c("ps","xp","yp"), names(df))
valid_rows <- apply(df[priority_cols], 1, function(x) all(is.finite(x)))

usable_start <- if (any(valid_rows)) df$t_rel_ms[which(valid_rows)[1]] else NA
usable_end   <- if (any(valid_rows)) df$t_rel_ms[tail(which(valid_rows), 1)] else NA
usable_duration <- if (!is.na(usable_start) && !is.na(usable_end)) usable_end - usable_start else NA

n_rows <- nrow(df)
has_leading_invalid  <- !all(valid_rows[1:min(10, length(valid_rows))])
has_trailing_invalid <- !all(valid_rows[max(1, length(valid_rows)-9):length(valid_rows)])
can_trim <- !is.na(usable_start) && !is.na(usable_end)

# ========================================================
# SAVE DIAGNOSTIC REPORT
# ========================================================
diag_row <- tibble(
  id = id,
  stimulus = stim,
  video_duration_ms = video_duration,
  n_rows = n_rows,
  usable_start = usable_start,
  usable_end = usable_end,
  usable_duration = usable_duration,
  can_trim = can_trim,
  has_leading_invalid = has_leading_invalid,
  has_trailing_invalid = has_trailing_invalid
)
write_csv(diag_row, DIAG_FILE, append=file.exists(DIAG_FILE))

# ========================================================
# MUTATE QC DATA WITH ALIGNED TIME
# ========================================================
if (can_trim) {
  scale_b <- video_duration / usable_duration
  df <- df %>% mutate(aligned_time = (t_rel_ms - usable_start) * scale_b)
} else {
  df <- df %>% mutate(aligned_time = NA_real_)
}

# ========================================================
# SAVE OUTPUT
# ========================================================
outfile <- file.path(DATA_DIR, paste0("aligned_preprocessed_", id, ".csv"))
write_csv(df, outfile)

cat("\n✔ Finished ID:", id, "\n")
cat("✔ Diagnostics appended →", DIAG_FILE, "\n")
cat("✔ Output written →", outfile, "\n")

