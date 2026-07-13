# ================================
# EyeLink ASC → Parsed CSV + RDS
# With automatic onset/offset trimming
# ================================

# --- Libraries ---
if (!requireNamespace("fs", quietly = TRUE))          install.packages("fs")
if (!requireNamespace("readr", quietly = TRUE))       install.packages("readr")
if (!requireNamespace("eyelinker", quietly = TRUE))   install.packages("eyelinker")
if (!requireNamespace("dplyr", quietly = TRUE))       install.packages("dplyr")
if (!requireNamespace("data.table", quietly = TRUE))  install.packages("data.table")
if (!requireNamespace("stringr", quietly = TRUE))     install.packages("stringr")

library(fs)
library(readr)
library(eyelinker)
library(dplyr)
library(data.table)
library(stringr)

# --- Root paths ---
ROOT_DIR <- normalizePath("/project2/elisab_1216/projects/ELM/", mustWork = TRUE)
RAW_DIR  <- file.path(ROOT_DIR, "raw")
OUT_DIR  <- file.path(ROOT_DIR, "parsed")
fs::dir_create(OUT_DIR)

# --- Find ASC files ---
asc_files <- fs::dir_ls(RAW_DIR, recurse = TRUE, type = "file", regexp = "(?i)\\.asc$")
asc_files <- unique(asc_files)
cat("Found", length(asc_files), "ASC file(s) anywhere under:", RAW_DIR, "\n")

# --- Helpers ---
`%||%` <- function(a, b) if (!is.null(a)) a else b

get_time_col <- function(df) {
  if (is.null(df) || !is.data.frame(df)) return(NA_character_)
  tc <- grep("^time$", names(df), ignore.case = TRUE, value = TRUE)
  if (length(tc)) tc[[1]] else NA_character_
}

read_msg_from_asc_fallback <- function(asc_path) {
  txt <- readLines(asc_path, warn = FALSE)
  m   <- regexec("^MSG\\s+(\\d+)\\s+(.*)$", txt)
  mat <- regmatches(txt, m)
  rows <- lapply(mat, function(v){
    if (length(v) == 3) data.frame(time = as.numeric(v[2]), msg = v[3], stringsAsFactors = FALSE)
  })
  msgs <- do.call(rbind, rows)
  if (!is.null(msgs) && nrow(msgs)) msgs[order(msgs$time), ] else NULL
}

# ================================
# Find onset + offset messages
# ================================
find_video_bounds <- function(parsed, verbose = TRUE) {
  msg <- parsed$msg
  if (is.null(msg) || nrow(msg) == 0) {
    if (verbose) cat("No MSG table found.\n")
    return(list(onset_time = NA, onset_src = NA, offset_time = NA, offset_src = NA))
  }

  tcol <- grep("^time$", names(msg), ignore.case = TRUE, value = TRUE)[1]
  mcol <- grep("^(msg|text)$", names(msg), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(tcol) || is.na(mcol)) {
    if (verbose) cat("MSG missing time/msg column.\n")
    return(list(onset_time = NA, onset_src = NA, offset_time = NA, offset_src = NA))
  }

  msgs <- msg %>% mutate(text = tolower(.data[[mcol]]))

  # ---- Find onset ----
  onset_rows <- grep("onset|start|display on|stimulus on|stim on", msgs$text)
  onset_row <- if (length(onset_rows)) onset_rows[1] else NA_integer_
  onset_time <- if (!is.na(onset_row)) msgs[[tcol]][onset_row] else NA_real_
  onset_src  <- if (!is.na(onset_row)) msgs[[mcol]][onset_row] else NA_character_

  # ---- Find offset ----
  offset_rows <- grep("offset|end|display off|stimulus off|stim off", msgs$text)
  if (length(offset_rows) == 0) {
    if (verbose) cat("No offset message found.\n")
    return(list(onset_time = onset_time, onset_src = onset_src,
                offset_time = NA, offset_src = NA))
  }

  if (verbose) cat("Found", length(offset_rows), "offset messages.\n")
  has_number <- str_detect(msgs[[mcol]][offset_rows], "\\d")
  chosen_row <- if (any(!has_number)) offset_rows[which(!has_number)[1]] else offset_rows[1]

  offset_time <- msgs[[tcol]][chosen_row]
  offset_src  <- msgs[[mcol]][chosen_row]
  if (verbose) cat(sprintf("Selected offset msg: '%s' at %.0f ms\n", offset_src, offset_time))

  list(onset_time = onset_time,
       onset_src  = onset_src,
       offset_time = offset_time,
       offset_src  = offset_src)
}

# ================================
# Stimulus label mapping
# ================================
extract_mp4_basename <- function(x) {
  x <- tolower(as.character(x))
  m  <- regexpr("([^[:space:]]+\\.mp4)", x, perl = TRUE)
  tok <- ifelse(m > 0, regmatches(x, m), NA_character_)
  b   <- ifelse(is.na(tok), NA_character_, sub("^.*[\\\\/]", "", tok))
  sub("\\.mp4$", "", b)
}

label_from_basename <- function(base) {
  out <- rep(NA_character_, length(base))
  set_if <- function(pattern, label) {
    hit <- !is.na(base) & grepl(pattern, base, fixed = TRUE)
    out[hit] <<- label
  }
  set_if("splitscreen", "Splitscreen")
  set_if("zima",        "Zima")
  set_if("hexagon",     "Hexagons")
  set_if("winter",      "Winter")
  set_if("turtle",      "Turtles")
  set_if("sun",         "Sun")
  set_if("igloo",       "Igloo")
  out
}

assign_stimulus_from_msg <- function(msg_df) {
  if (is.null(msg_df) || !nrow(msg_df)) {
    return(list(per_row = NULL, first_label = NA_character_, first_time = NA_real_))
  }
  tcol <- grep("^time$", names(msg_df), ignore.case = TRUE, value = TRUE)[1]
  mcol <- grep("^(msg|text)$", names(msg_df), ignore.case = TRUE, value = TRUE)[1]
  if (is.na(tcol) || is.na(mcol)) {
    return(list(per_row = NULL, first_label = NA_character_, first_time = NA_real_))
  }

  base  <- extract_mp4_basename(msg_df[[mcol]])
  labs  <- label_from_basename(base)
  ord <- order(as.numeric(msg_df[[tcol]]), na.last = TRUE)
  first_idx <- ord[which(!is.na(labs[ord]))[1]]
  first_lab <- if (length(first_idx)) labs[first_idx] else NA_character_
  first_tim <- if (length(first_idx)) as.numeric(msg_df[[tcol]][first_idx]) else NA_real_

  list(per_row = labs, first_label = first_lab, first_time = first_tim)
}

# ================================
# Parse a single ASC 
# ================================
parse_asc_save <- function(asc_path, out_dir = OUT_DIR,
                           save_csv = TRUE,
                           print_raw = TRUE) {

  asc_path <- fs::path_abs(asc_path)
  id       <- fs::path_ext_remove(fs::path_file(asc_path))
  out_rds  <- fs::path(out_dir, paste0(id, ".rds"))

  parsed <- eyelinker::read.asc(asc_path)

  # --- Rebuild msgs if missing ---
  if (is.null(parsed$msg) || !nrow(parsed$msg)) {
    fallback <- read_msg_from_asc_fallback(asc_path)
    parsed$msg <- fallback %||% data.frame(time = numeric(0), msg = character(0))
    cat("Reconstructed messages for:", id, "\n")
  }

  # --- Find onset/offset and trim raw ---
  bounds <- find_video_bounds(parsed, verbose = TRUE)
  if (!is.na(bounds$onset_time) && !is.na(bounds$offset_time)) {
    before_n <- nrow(parsed$raw)
    parsed$raw <- parsed$raw %>%
      filter(time >= bounds$onset_time & time <= bounds$offset_time)
    after_n <- nrow(parsed$raw)
    cat(sprintf("Trimmed %s: kept %d/%d (%.1f%%)\n",
                id, after_n, before_n, 100 * after_n / before_n))
    duration_ms <- bounds$offset_time - bounds$onset_time
    cat(sprintf("Movie duration: %.0f ms (%.2f s); samples kept: %d\n",
                duration_ms,
                duration_ms / 1000,
                after_n))
  } else if (!is.na(bounds$onset_time)) {
    parsed$raw <- parsed$raw %>% filter(time >= bounds$onset_time)
    cat("Trimmed from onset only (no offset).\n")
  } else {
    cat("No onset/offset trimming applied.\n")
  }

  # --- Join with MSG + Stimulus ---
  raw <- parsed$raw
  tcol <- get_time_col(raw)
  names(raw)[names(raw) == tcol] <- "time"
  raw <- raw %>% mutate(id = id, time = as.numeric(time))

  msg_tbl <- parsed$msg
  mcol <- if ("text" %in% names(msg_tbl)) "text" else if ("msg" %in% names(msg_tbl)) "msg" else NA_character_
  msg_tbl <- msg_tbl %>% mutate(time = as.numeric(time))

  msg_by_time <- msg_tbl %>%
    arrange(time) %>%
    group_by(time) %>%
    summarise(msg = paste(.data[[mcol]], collapse = " | "), .groups = "drop")

  raw_with_id_msg <- raw %>%
    left_join(msg_by_time, by = "time")

  msg_df <- parsed$msg
  if (!is.null(msg_df) && nrow(msg_df)) {
    tcol0 <- grep("^time$", names(msg_df), ignore.case = TRUE, value = TRUE)[1]
    mcol0 <- grep("^(msg|text)$", names(msg_df), ignore.case = TRUE, value = TRUE)[1]
    msg_df <- msg_df[, c(tcol0, mcol0)]
    names(msg_df) <- c("time", "msg")
  }
  lab_info <- assign_stimulus_from_msg(msg_df)
  raw_with_id_msg$stimulus <- lab_info$first_label
  cat("Stimulus:", lab_info$first_label, "\n")
  
  # --- Save all outputs (FIXED to include blink) ---
  if (save_csv) {
    if (!is.null(parsed$raw))   write_csv(parsed$raw,  fs::path(out_dir, paste0(id, "_raw.csv")))
    if (!is.null(parsed$fix))   write_csv(parsed$fix,  fs::path(out_dir, paste0(id, "_fix.csv")))
    if (!is.null(parsed$sac))   write_csv(parsed$sac,  fs::path(out_dir, paste0(id, "_sac.csv")))
    if (!is.null(parsed$blink)) write_csv(parsed$blink,fs::path(out_dir, paste0(id, "_blink.csv")))
    if (!is.null(parsed$msg))   write_csv(parsed$msg,  fs::path(out_dir, paste0(id, "_msg.csv")))
    write_csv(raw_with_id_msg,  fs::path(out_dir, paste0(id, "_raw_with_id_msg.csv")))
  }

  # --- Build summary row ---
  hz_est <- 1000 / stats::median(diff(raw_with_id_msg$time), na.rm = TRUE)
  per_file <- data.frame(
    id          = id,
    n_raw       = nrow(parsed$raw),
    n_fix       = nrow(parsed$fix   %||% data.frame()),
    n_sac       = nrow(parsed$sac   %||% data.frame()),
    n_blink     = nrow(parsed$blink %||% data.frame()),
    n_msg       = nrow(parsed$msg),
    onset_ms    = bounds$onset_time,
    onset_src   = bounds$onset_src,
    offset_ms   = bounds$offset_time,
    offset_src  = bounds$offset_src,
    hz          = round(hz_est, 2),
    stringsAsFactors = FALSE
  )

  saveRDS(parsed, out_rds)
  per_file
}

# ================================
# Batch run
# ================================
REPARSE_IF_ASC_NEWER <- FALSE
asc_id <- function(p) fs::path_ext_remove(fs::path_file(p))
expected_outputs <- function(id, out_dir = OUT_DIR) {
  c(fs::path(out_dir, paste0(id, ".rds")),
    fs::path(out_dir, paste0(id, "_raw_with_id_msg.csv")))
}

should_parse <- function(asc_path, out_dir = OUT_DIR) {
  id <- asc_id(asc_path)
  outs <- expected_outputs(id, out_dir)
  if (!all(fs::file_exists(outs))) return(TRUE)
  if (REPARSE_IF_ASC_NEWER) {
    asc_time <- fs::file_info(asc_path)$modification_time
    outs_time <- max(fs::file_info(outs)$modification_time, na.rm = TRUE)
    return(isTRUE(asc_time > outs_time))
  }
  FALSE
}

to_parse <- vapply(asc_files, should_parse, logical(1), out_dir = OUT_DIR)
asc_todo <- asc_files[to_parse]

cat(sprintf("Total: %d | To parse: %d\n", length(asc_files), length(asc_todo)))

summaries <- lapply(asc_todo, function(f) {
  cat("Parsing:", f, "\n")
  tryCatch(parse_asc_save(f, OUT_DIR, save_csv = TRUE),
           error = function(e) {
             message("Error parsing ", f, ": ", e$message)
             NULL
           })
})

ok <- Filter(Negate(is.null), summaries)
if (length(ok)) {
  df_summary <- do.call(rbind, ok)
  write_csv(df_summary, file.path(OUT_DIR, "_summary.csv"))
  cat("Summary written to:", file.path(OUT_DIR, "_summary.csv"), "\n")
}

