# Libraries
if (!requireNamespace("fs", quietly = TRUE))          install.packages("fs")
if (!requireNamespace("readr", quietly = TRUE))       install.packages("readr")
if (!requireNamespace("eyelinker", quietly = TRUE)) install.packages("eyelinker")
if (!requireNamespace("dplyr", quietly = TRUE))       install.packages("dplyr")
if (!requireNamespace("data.table", quietly = TRUE))  install.packages("data.table")
if (!requireNamespace("stringr", quietly = TRUE))  install.packages("stringr")
if (!requireNamespace("zoo", quietly = TRUE)) install.packages("zoo")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
if (!requireNamespace("tidyr",    quietly = TRUE)) install.packages("tidyr")
if (!requireNamespace("patchwork",quietly = TRUE)) install.packages("patchwork")
if (!requireNamespace("purrr",quietly = TRUE)) install.packages("purrr")

library(fs)
library(readr)
library(eyelinker)
library(dplyr)
library(data.table)
library(stringr)
library(zoo)
library(ggplot2)
library(tidyr)
library(patchwork)
library(purrr)

# Config Directories
# ---- Root paths (edit if needed) ----
ROOT_DIR   <- normalizePath("/project2/elisab_1216/projects/ELM/", mustWork = TRUE)
PARSE_DIR  <- file.path(ROOT_DIR, "parsed")
OUT_DIR    <- file.path(ROOT_DIR, "outputs/pre_processed_step1")
POST_DATA_DIR <- file.path(OUT_DIR, "data")  # define first

# ensure dirs exist
if (!dir.exists(OUT_DIR))       dir.create(OUT_DIR, recursive = TRUE)
if (!dir.exists(POST_DATA_DIR)) dir.create(POST_DATA_DIR, recursive = TRUE)

# Config Array Index per ID (subject x stimuli file)
# get array index (1-based)
args <- commandArgs(trailingOnly = TRUE)
task_id <- if (length(args)) as.integer(args[1]) else NA_integer_
cat("SLURM task_id:", task_id, "\n")

# discover raw files and map to IDs
raw_files <- fs::dir_ls(PARSE_DIR, regexp = "_raw_with_id_msg\\.csv$", type = "file")
if (!length(raw_files)) stop("No *_raw_with_id_msg.csv in ", PARSE_DIR)

id_from <- function(p) {
  base <- fs::path_file(p)
  stem <- sub("\\.csv$", "", base)
  sub("(_raw_with_id_msg|_blink)$", "", stem)
}
ids <- id_from(raw_files)

# --- Debugging output ---
cat("📦 Total raw files discovered:", length(raw_files), "\n")
cat("🧩 Total extracted IDs:", length(ids), "\n")


# sort deterministically so task 1 == first ID, etc.
ord <- order(ids)
raw_files <- raw_files[ord]
ids       <- ids[ord]

# guard: if array index is out of range, exit gracefully
if (!is.finite(task_id) || task_id < 1 || task_id > length(ids)) {
  cat("No work for task_id =", task_id, "(N files =", length(ids), "). Exiting.\n")
  quit(save = "no", status = 0)
}

# select this task’s file/id only
id       <- ids[task_id]
raw_path <- raw_files[task_id]
cat("Processing ID:", id, "\n")

# ------------------------------------------------------------
# Load Raw data
# ------------------------------------------------------------
raw <- suppressMessages(readr::read_csv(raw_path, show_col_types = FALSE))
if (!nrow(raw)) {
  cat("Empty raw for id:", id, "— exiting.\n")
  quit(save = "no", status = 0)
}

# ------------------------------------------------------------
# Normalizing time + resampling for ONE id
# ------------------------------------------------------------
# 1) Add relative time
t0 <- raw$time[which.min(raw$time)]
raw$t_rel_ms <- as.numeric(raw$time) - as.numeric(t0)

estimate_hz <- function(tms) {
  dt <- diff(as.numeric(tms))
  1000 / stats::median(dt[is.finite(dt) & dt > 0], na.rm = TRUE)
}

resample_1khz <- function(df, id, blink_cols = c("blink_L","blink_R")) {
  t0 <- min(df$time, na.rm = TRUE); t1 <- max(df$time, na.rm = TRUE)
  grid <- seq(ceiling(t0), floor(t1), by = 1)  # 1 ms grid
  
  step_cols <- intersect(blink_cols, names(df))
  num_cols  <- names(df)[vapply(df, is.numeric, logical(1))]
  num_cols  <- setdiff(num_cols, c("time", step_cols))  # we'll create new time; keep others numeric
  
  out <- data.frame(time = grid, stringsAsFactors = FALSE)
  
  # numeric columns -> linear interpolation (clamped ends)
  for (nm in num_cols) {
    v <- df[[nm]]; ok <- is.finite(df$time) & is.finite(v)
    out[[nm]] <- if (sum(ok) >= 2) stats::approx(df$time[ok], v[ok], xout = grid, rule = 2, ties = "ordered")$y else NA_real_
  }
  
  # blink flags -> step interpolation then threshold
  for (nm in step_cols) {
    v <- as.numeric(df[[nm]]); ok <- is.finite(df$time) & is.finite(v)
    out[[nm]] <- if (sum(ok) >= 1) {
      stats::approxfun(df$time[ok], v[ok], method = "constant", f = 1, rule = 2)(grid) > 0.5
    } else FALSE
  }
  
  # carry id, msg/stimulus if present (nearest-back)
  out$id <- id
  if ("msg" %in% names(df)) {
    m <- df %>% dplyr::arrange(time) %>% dplyr::select(time, msg)
    idx <- findInterval(out$time, m$time, left.open = TRUE)
    out$msg <- ifelse(idx > 0, m$msg[idx], NA_character_)
  }
  if ("stimulus" %in% names(df)) out$stimulus <- df$stimulus[1]
  
  # rebuild relative time
  out$t_rel_ms <- out$time - min(out$time, na.rm = TRUE)
  out
}

hz <- estimate_hz(raw$time)
if (is.finite(hz) && abs(hz - 1000) <= 1) {
  kept_ids       <- id
  resampled_ids  <- character(0)
  raw          <- raw
  cat(sprintf("ID %s: already ~1000 Hz (%.3f Hz)\n", id, hz))
} else {
  resampled_ids  <- id
  kept_ids       <- character(0)
  raw          <- resample_1khz(raw, id)
  cat(sprintf("ID %s: resampled to 1000 Hz (was %.3f Hz)\n", id, hz))
}

cat("\n=== Resampling summary (this task) ===\n")
cat("Resampled to 1000 Hz:", length(resampled_ids), "ID(s)\n")
if (length(resampled_ids)) cat("  IDs:", paste(resampled_ids, collapse = ", "), "\n")
cat("Already ~1000 Hz:", length(kept_ids), "ID(s)\n")

# ------------------------------------------------------------
# 1) Trim offset to video duration (using VIDEO_DUR_FILE)
# ------------------------------------------------------------
#VIDEO_DUR_FILE <- file.path(ROOT_DIR, "videos/video_durations.csv")  
#if (!fs::file_exists(VIDEO_DUR_FILE)) stop("VIDEO_DUR_FILE not found: ", VIDEO_DUR_FILE)

#video_durations <- readr::read_csv(VIDEO_DUR_FILE, show_col_types = FALSE)

# Ensure stimulus column exists
#stim <- if ("stimulus" %in% names(raw)) raw$stimulus[1] else NA_character_
#if (is.na(stim)) stop("No stimulus found in raw data for ID: ", id)

#video_duration <- video_durations$duration_ms[video_durations$stimulus == stim]
#if (!length(video_duration)) stop("Missing video duration for stimulus: ", stim)

#cat("Trimming resampled data to video duration (ms):", video_duration, "\n")

# Trim dataframe
#raw <- raw %>% dplyr::filter(t_rel_ms <= (video_duration-1))

#cat("Post-trim samples for ID", id, ":", nrow(raw), "\n")
#cat("Video Duration for stim", stim, ":", video_duration, "\n")

# ------------------------------------------------------------
# Blink & Off-Screen mapping for ONE id
#   * only pad blinks (±100 ms) from blink file
#   * off-screen flags collected, NOT padded or used for interpolation
#   * track invalid samples (non-finite) for psl/psr/xpl/xpr/ypl/ypr
#   * interpolate pupil on blink padding OR invalid pupil samples
#   * interpolate gaze on blink padding OR invalid gaze samples
# ------------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b

flag_times_in_intervals <- function(time_vec, st, et) {
  if (length(st) == 0L) return(rep(FALSE, length(time_vec)))
  ord <- order(st); st <- st[ord]; et <- et[ord]
  out <- rep(FALSE, length(time_vec))
  for (i in seq_along(st)) out <- out | (time_vec >= st[i] & time_vec <= et[i])
  out
}

cat("\n=== Annotating:", id, "===\n")

blink_path <- fs::path(PARSE_DIR, paste0(id, "_blink.csv"))

# 2) Blink flags from blink file (if present)
blink_L <- rep(FALSE, nrow(raw))
blink_R <- rep(FALSE, nrow(raw))
if (fs::file_exists(blink_path)) {
  b <- suppressMessages(readr::read_csv(blink_path, show_col_types = FALSE))
  names(b) <- tolower(names(b))
  if (!"stime" %in% names(b)) b$stime <- b$start %||% b$st %||% b$stime
  if (!"etime" %in% names(b)) b$etime <- b$end   %||% b$et %||% b$etime
  if (!"eye"   %in% names(b)) b$eye   <- b$eye   %||% b$Eye %||% b$EYE
  b  <- b %>% dplyr::filter(is.finite(stime), is.finite(etime), stime <= etime)
  bL <- b %>% dplyr::filter(toupper(eye) == "L")
  bR <- b %>% dplyr::filter(toupper(eye) == "R")
  if (nrow(bL)) blink_L <- flag_times_in_intervals(raw$time, bL$stime, bL$etime)
  if (nrow(bR)) blink_R <- flag_times_in_intervals(raw$time, bR$stime, bR$etime)
} else {
  cat("  (No blink file for", id, "— assuming no labeled blinks.)\n")
}

# 3) Pupil validity per sample (invalid = missing or <= 0)
if (!all(c("psl","psr") %in% names(raw))) {
  stop("For id ", id, ": columns 'psl' and 'psr' not found in raw file.")
}
invalid_psl <- is.na(raw$psl) | (raw$psl <= 0) | !is.finite(raw$psl)
invalid_psr <- is.na(raw$psr) | (raw$psr <= 0) | !is.finite(raw$psr)

# 4) Missed vs false blinks (per-eye)
missed_L <- sum(invalid_psl & !blink_L, na.rm = TRUE)
missed_R <- sum(invalid_psr & !blink_R, na.rm = TRUE)
valid_L  <- !invalid_psl
valid_R  <- !invalid_psr
false_L  <- sum(blink_L & valid_L, na.rm = TRUE)
false_R  <- sum(blink_R & valid_R, na.rm = TRUE)

# 5) Proportions of time in blink
prop_blink_L   <- mean(blink_L, na.rm = TRUE)
prop_blink_R   <- mean(blink_R, na.rm = TRUE)
blink_any      <- (blink_L | blink_R)
prop_blink_any <- mean(blink_any, na.rm = TRUE)

# 6) Attach blink flags
raw$blink_L <- blink_L
raw$blink_R <- blink_R

# 7) Screen fixation validity per sample (off-screen detection is collected but NOT padded)
screen_x_min <- 0
screen_x_max <- 1919
screen_y_min <- 0
screen_y_max <- 1079
invalid_code <- -32768

onscreen <- function(x, y) {
  is.finite(x) & is.finite(y) &
    x >= screen_x_min & x <= screen_x_max &
    y >= screen_y_min & y <= screen_y_max &
    x != invalid_code & y != invalid_code
}

# Per-eye full validity (onscreen as TRUE/FALSE)
valid_L_screen <- onscreen(raw$xpl, raw$ypl)
valid_R_screen <- onscreen(raw$xpr, raw$ypr)

# Per-axis off-screen flags (dimension-specific reasons) — recorded, NOT used for interpolation padding
off_Lx <- !( is.finite(raw$xpl) &
               raw$xpl >= screen_x_min &
               raw$xpl <= screen_x_max &
               raw$xpl != invalid_code )
off_Ly <- !( is.finite(raw$ypl) &
               raw$ypl >= screen_y_min &
               raw$ypl <= screen_y_max &
               raw$ypl != invalid_code )
off_Rx <- !( is.finite(raw$xpr) &
               raw$xpr >= screen_x_min &
               raw$xpr <= screen_x_max &
               raw$xpr != invalid_code )
off_Ry <- !( is.finite(raw$ypr) &
               raw$ypr >= screen_y_min &
               raw$ypr <= screen_y_max &
               raw$ypr != invalid_code )

raw$offbounds_Lx <- off_Lx
raw$offbounds_Ly <- off_Ly
raw$offbounds_Rx <- off_Rx
raw$offbounds_Ry <- off_Ry

# 8) Off-screen summary metrics (for reporting only)
prop_off_Lx <- mean(off_Lx, na.rm = TRUE)
prop_off_Rx <- mean(off_Rx, na.rm = TRUE)
prop_off_Ly <- mean(off_Ly, na.rm = TRUE)
prop_off_Ry <- mean(off_Ry, na.rm = TRUE)

off_any      <- (off_Lx | off_Rx | off_Ly | off_Ry)
prop_off_any <- mean(off_any, na.rm = TRUE)

# 9) combined proportion (blink OR off-screen) for reporting
blink_or_off      <- (blink_any | off_any)
prop_blink_or_off <- mean(blink_or_off, na.rm = TRUE)

message(sprintf("  ID %s — prop(blink OR off-screen)=%.4f", id, prop_blink_or_off))

# 10) One-row summary for THIS id (reporting)
summary_df <- tibble::tibble(
  id = id,
  n_samples = nrow(raw),
  prop_blink_L   = prop_blink_L,
  prop_blink_R   = prop_blink_R,
  prop_blink_any = prop_blink_any,
  missed_L_count = missed_L,
  missed_R_count = missed_R,
  false_L_count  = false_L,
  false_R_count  = false_R,
  prop_off_Lx    = prop_off_Lx,
  prop_off_Rx    = prop_off_Rx,
  prop_off_Ly    = prop_off_Ly,
  prop_off_Ry    = prop_off_Ry,
  prop_off_any   = prop_off_any,
  prop_blink_or_off = prop_blink_or_off
)

combined_summary <- file.path(OUT_DIR, "raw_pre_summary.csv")
first_write <- !file.exists(combined_summary)
readr::write_csv(summary_df, combined_summary, append = !first_write, col_names = first_write)
cat("Appended raw preprocessed summary for", id, "to:", combined_summary, "\n")

message(sprintf("Raw data kept: %s", id))

# If later stages expect lists, make one-element lists:
raws_pre <- list(); raws_pre[[id]] <- raw

# ------------------------------------------------------------
# Masking (ONE id) — Option A behavior
#   * only pad blinks (±100 ms) using expand_mask on blink flags
#   * do NOT pad or use off-screen flags for interpolation
#   * compute invalid_* flags for ps/x/y (non-finite etc.)
#   * interp_ps* = pad_blink_eye OR invalid_ps*
#   * interp_x*/y* = pad_blink_eye OR invalid_x*/y*
# ------------------------------------------------------------
expand_mask <- function(t, mask, pad_ms = 100L) {
  if (!length(mask) || !any(mask)) return(rep(FALSE, length(mask)))
  r <- rle(mask); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1
  out <- rep(FALSE, length(t))
  for (i in seq_along(r$values)) if (r$values[i]) {
    s <- starts[i]; e <- ends[i]
    out <- out | (t >= (t[s] - pad_ms) & t <= (t[e] + pad_ms))
  }
  out
}

stopifnot(exists("raws_pre"), is.list(raws_pre), id %in% names(raws_pre))
df <- raws_pre[[id]]
tcol <- if ("t_rel_ms" %in% names(df)) "t_rel_ms" else "time"
if (!tcol %in% names(df)) stop("No time column for id: ", id)
n <- nrow(df)

# ensure blink flags exist
ensure <- function(nm) { if (!nm %in% names(df)) df[[nm]] <<- FALSE }
ensure("blink_L"); ensure("blink_R")
# offbounds columns are kept as-is (recorded earlier) but NOT padded/used for interpolation

# blink pads only (±100 ms)
pad_blink_L <- expand_mask(df[[tcol]], df$blink_L, 100L)
pad_blink_R <- expand_mask(df[[tcol]], df$blink_R, 100L)

# track invalid numeric samples (Option A: invalid defined as non-finite OR pupil <= 0 for ps)
invalid_psl <- if ("psl" %in% names(df)) (is.na(df$psl) | (df$psl <= 0) | !is.finite(df$psl)) else rep(FALSE, n)
invalid_psr <- if ("psr" %in% names(df)) (is.na(df$psr) | (df$psr <= 0) | !is.finite(df$psr)) else rep(FALSE, n)

# invalid for gaze coordinates (x/y): non-finite OR equal to EyeLink invalid code
invalid_xpl <- if ("xpl" %in% names(df)) (!is.finite(df$xpl) | df$xpl == invalid_code) else rep(FALSE, n)
invalid_ypl <- if ("ypl" %in% names(df)) (!is.finite(df$ypl) | df$ypl == invalid_code) else rep(FALSE, n)
invalid_xpr <- if ("xpr" %in% names(df)) (!is.finite(df$xpr) | df$xpr == invalid_code) else rep(FALSE, n)
invalid_ypr <- if ("ypr" %in% names(df)) (!is.finite(df$ypr) | df$ypr == invalid_code) else rep(FALSE, n)

has <- function(nm) nm %in% names(df)

# ---------- Build per-variable interpolate booleans (Option A) ----------
# Pupil: interpolate where blink padding OR invalid pupil samples
df$interp_psl <- if (has("psl")) (pad_blink_L | invalid_psl) else rep(FALSE, n)
df$interp_psr <- if (has("psr")) (pad_blink_R | invalid_psr) else rep(FALSE, n)

# Gaze: interpolate where blink padding OR invalid gaze samples
# NOTE: Off-screen flags are NOT used here (per Option A)
df$interp_xpl <- if (has("xpl")) (pad_blink_L | invalid_xpl) else rep(FALSE, n)
df$interp_ypl <- if (has("ypl")) (pad_blink_L | invalid_ypl) else rep(FALSE, n)
df$interp_xpr <- if (has("xpr")) (pad_blink_R | invalid_xpr) else rep(FALSE, n)
df$interp_ypr <- if (has("ypr")) (pad_blink_R | invalid_ypr) else rep(FALSE, n)

# ---------- Apply masking: set values to NA where interp_* is TRUE ----------
if (has("psl")) df$psl[df$interp_psl] <- NA
if (has("psr")) df$psr[df$interp_psr] <- NA
if (has("xpl")) df$xpl[df$interp_xpl] <- NA
if (has("ypl")) df$ypl[df$interp_ypl] <- NA
if (has("xpr")) df$xpr[df$interp_xpr] <- NA
if (has("ypr")) df$ypr[df$interp_ypr] <- NA

raws_masked <- list(); raws_masked[[id]] <- df

cat("Masking complete for id ", id,
    ": created interp_* booleans and set those samples to NA (blink±100ms OR invalid samples for ps/x/y). \n", sep="")

# -------------------------------
# Per-ID interpolation summary CSV
# -------------------------------
prop <- function(v) if (!length(v)) NA_real_ else mean(v, na.rm = TRUE)

interp_cols <- intersect(
  c("interp_psl","interp_psr","interp_xpl","interp_ypl","interp_xpr","interp_ypr"),
  names(df)
)
value_cols  <- intersect(c("psl","psr","xpl","ypl","xpr","ypr"), names(df))

# per-row OR across interp_* flags (TRUE if any channel flagged at that sample)
interp_any <- if (length(interp_cols)) {
  Reduce(`|`, lapply(interp_cols, function(nm) as.logical(df[[nm]])))
} else rep(NA, n)

# per-row OR across NA in any value column (TRUE if any channel is NA at that sample)
na_any <- if (length(value_cols)) {
  Reduce(`|`, lapply(value_cols, function(nm) is.na(df[[nm]])))
} else rep(NA, n)

summary_interp_na <- data.frame(
  id = id,
  n_samples = n,
  prop_interp_psl = if ("interp_psl" %in% names(df)) prop(df$interp_psl) else NA_real_,
  prop_interp_psr = if ("interp_psr" %in% names(df)) prop(df$interp_psr) else NA_real_,
  prop_interp_xpl = if ("interp_xpl" %in% names(df)) prop(df$interp_xpl) else NA_real_,
  prop_interp_ypl = if ("interp_ypl" %in% names(df)) prop(df$interp_ypl) else NA_real_,
  prop_interp_xpr = if ("interp_xpr" %in% names(df)) prop(df$interp_xpr) else NA_real_,
  prop_interp_ypr = if ("interp_ypr" %in% names(df)) prop(df$interp_ypr) else NA_real_,
  prop_interp_any = prop(interp_any),
  prop_na_psl = if ("psl" %in% names(df)) prop(is.na(df$psl)) else NA_real_,
  prop_na_psr = if ("psr" %in% names(df)) prop(is.na(df$psr)) else NA_real_,
  prop_na_xpl = if ("xpl" %in% names(df)) prop(is.na(df$xpl)) else NA_real_,
  prop_na_ypl = if ("ypl" %in% names(df)) prop(is.na(df$ypl)) else NA_real_,
  prop_na_xpr = if ("xpr" %in% names(df)) prop(is.na(df$xpr)) else NA_real_,
  prop_na_ypr = if ("ypr" %in% names(df)) prop(is.na(df$ypr)) else NA_real_,
  prop_na_any = prop(na_any),
  stringsAsFactors = FALSE
)

combined_interp <- file.path(OUT_DIR, "summary_interp.csv")
first_write <- !file.exists(combined_interp)
readr::write_csv(summary_interp_na, combined_interp, append = !first_write, col_names = first_write)
cat("Appended interpolation summary for", id, "to:", combined_interp, "\n")

# ------------------------------------------------------------
# Interpolation for ONE id (linear fill only at positions flagged)
# ------------------------------------------------------------
fill_only_where <- function(x, t, mask) {
  if (!length(x) || !length(mask) || !any(mask)) return(x)  # nothing to do
  x_work <- x
  # mark masked locations as NA (we already set them above, but ensure non-finite invalids are NA for interpolation)
  x_work[mask] <- NA
  # Linear interpolation across whole vector (no extrapolation at ends)
  x_lin <- tryCatch(zoo::na.approx(x_work, x = t, na.rm = FALSE), error = function(e) x_work)
  # Keep original values everywhere except masked indices
  x_out <- x
  x_out[mask] <- x_lin[mask]
  x_out
}

stopifnot(exists("raws_masked"), is.list(raws_masked), id %in% names(raws_masked))
df <- raws_masked[[id]]
tcol <- if ("t_rel_ms" %in% names(df)) "t_rel_ms" else "time"
if (!tcol %in% names(df)) stop("No time column for id: ", id)
t <- df[[tcol]]

pairs <- list(
  psl = "interp_psl",
  psr = "interp_psr",
  xpl = "interp_xpl",
  ypl = "interp_ypl",
  xpr = "interp_xpr",
  ypr = "interp_ypr"
)

filled_counts <- c()

for (nm in names(pairs)) {
  mask_nm <- pairs[[nm]]
  if (!(nm %in% names(df)) || !(mask_nm %in% names(df))) next
  mask <- as.logical(df[[mask_nm]])
  out_nm <- paste0(nm, "_i")       # interpolated output column
  df[[out_nm]] <- fill_only_where(df[[nm]], t, mask)
  filled_counts[out_nm] <- sum(mask, na.rm = TRUE)
}

raws_interp <- list(); raws_interp[[id]] <- df

if (length(filled_counts)) {
  msg <- paste(sprintf("%s:%d", names(filled_counts), filled_counts), collapse = ", ")
  message(sprintf("ID %s — interpolated (linear) counts: %s", id, msg))
} else {
  message(sprintf("ID %s — no interp_* flags/variables found to interpolate.", id))
}

cat("Linear interpolation complete. Results in *_i columns inside raws_interp[[id]].\n")

# ------------------------------------------------------------
# Binocular Aggregation (prefer interpolated *_i columns)
# ------------------------------------------------------------
stopifnot(exists("raws_interp"), is.list(raws_interp), id %in% names(raws_interp))
df <- raws_interp[[id]]
n  <- nrow(df)

has  <- function(nm) nm %in% names(df)
best <- function(base) {
  col_i <- paste0(base, "_i")
  if (has(col_i)) df[[col_i]]
  else if (has(base)) df[[base]]
  else rep(NA_real_, n)
}

psl <- best("psl"); psr <- best("psr")
xpl <- best("xpl"); xpr <- best("xpr")
ypl <- best("ypl"); ypr <- best("ypr")

fin_psL <- is.finite(psl); fin_psR <- is.finite(psr)
fin_xL  <- is.finite(xpl); fin_xR  <- is.finite(xpr)
fin_yL  <- is.finite(ypl); fin_yR  <- is.finite(ypr)

both_ps <- fin_psL & fin_psR
both_x  <- fin_xL  & fin_xR
both_y  <- fin_yL  & fin_yR

ps <- rep(NA_real_, n)
ps[both_ps] <- (psl[both_ps] + psr[both_ps]) / 2
ps[!both_ps &  fin_psL] <- psl[!both_ps &  fin_psL]
ps[!both_ps & !fin_psL & fin_psR] <- psr[!both_ps & !fin_psL & fin_psR]

xp <- rep(NA_real_, n)
xp[both_x] <- (xpl[both_x] + xpr[both_x]) / 2
xp[!both_x &  fin_xL] <- xpl[!both_x &  fin_xL]
xp[!both_x & !fin_xL & fin_xR] <- xpr[!both_x & !fin_xL & fin_xR]

yp <- rep(NA_real_, n)
yp[both_y] <- (ypl[both_y] + ypr[both_y]) / 2
yp[!both_y &  fin_yL] <- ypl[!both_y &  fin_yL]
yp[!both_y & !fin_yL & fin_yR] <- ypr[!both_y & !fin_yL & fin_yR]

df$ps <- ps; df$xp <- xp; df$yp <- yp
df$fallback_ps <- xor(fin_psL, fin_psR)
df$fallback_x  <- xor(fin_xL,  fin_xR)
df$fallback_y  <- xor(fin_yL,  fin_yR)

raws_bino <- list(); raws_bino[[id]] <- df

message(sprintf(
  "ID %s — fallbacks used (ps/x/y): %d / %d / %d",
  id,
  sum(df$fallback_ps, na.rm = TRUE),
  sum(df$fallback_x,  na.rm = TRUE),
  sum(df$fallback_y,  na.rm = TRUE)
))

cat("Binocular aggregation done: ps/xp/yp + fallback_* columns added in raws_bino[[id]].\n")

# write final preprocessed CSV for this id
if (!dir.exists(POST_DATA_DIR)) dir.create(POST_DATA_DIR, recursive = TRUE)
safe <- function(x) gsub("[^A-Za-z0-9._-]+", "_", x)
fp <- file.path(POST_DATA_DIR, paste0("qc_preprocessed_", safe(id), ".csv"))
readr::write_csv(df, fp)
cat("Wrote:", fp, "\n")
