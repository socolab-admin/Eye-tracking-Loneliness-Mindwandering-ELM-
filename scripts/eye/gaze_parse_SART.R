# ================================
# EyeLink ASC → Parsed CSV + RDS
# SART-only version
# ================================

# --- Libraries ---
if (!requireNamespace("fs", quietly = TRUE))          install.packages("fs")
if (!requireNamespace("readr", quietly = TRUE))       install.packages("readr")
if (!requireNamespace("eyelinker", quietly = TRUE))   install.packages("eyelinker")
if (!requireNamespace("dplyr", quietly = TRUE))       install.packages("dplyr")
if (!requireNamespace("data.table", quietly = TRUE))  install.packages("data.table")
if (!requireNamespace("stringr", quietly = TRUE))     install.packages("stringr")
if (!requireNamespace("tidyr", quietly = TRUE))       install.packages("tidyr")

library(fs)
library(readr)
library(eyelinker)
library(dplyr)
library(data.table)
library(stringr)
library(tidyr)

# --- Root paths ---
ROOT_DIR <- normalizePath("/project2/elisab_1216/projects/ELM/", mustWork = TRUE)
RAW_DIR  <- file.path(ROOT_DIR, "rawSART")
OUT_DIR  <- file.path(ROOT_DIR, "parsedSART")
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
  rows <- lapply(mat, function(v) {
    if (length(v) == 3) {
      data.frame(
        time = as.numeric(v[2]),
        msg  = v[3],
        stringsAsFactors = FALSE
      )
    }
  })
  msgs <- do.call(rbind, rows)
  if (!is.null(msgs) && nrow(msgs)) msgs[order(msgs$time), ] else NULL
}

# ================================
# Parse a single ASC
# ================================
parse_asc_save_sart <- function(asc_path, out_dir = OUT_DIR, save_csv = TRUE) {

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

  # --- Normalize raw table ---
  raw <- parsed$raw
  raw_time_col <- get_time_col(raw)
  if (!is.na(raw_time_col) && raw_time_col != "time") {
    names(raw)[names(raw) == raw_time_col] <- "time"
  }
  raw <- raw %>%
    mutate(
      id = id,
      time = as.numeric(time)
    )

  # --- Normalize msg table ---
  msg_tbl <- parsed$msg
  msg_time_col <- get_time_col(msg_tbl)
  msg_text_col <- if ("text" %in% names(msg_tbl)) "text" else if ("msg" %in% names(msg_tbl)) "msg" else NA_character_

  if (!is.na(msg_time_col) && msg_time_col != "time") {
    names(msg_tbl)[names(msg_tbl) == msg_time_col] <- "time"
  }
  if (!is.na(msg_text_col) && msg_text_col != "text") {
    names(msg_tbl)[names(msg_tbl) == msg_text_col] <- "text"
  }

  msg_tbl <- msg_tbl %>%
    mutate(
      time = as.numeric(time),
      text = as.character(text)
    )

  # --- Join raw gaze samples to messages by time ---
  msg_by_time <- msg_tbl %>%
    arrange(time) %>%
    group_by(time) %>%
    summarise(text = paste(text, collapse = " | "), .groups = "drop")

  raw_with_id_msg <- raw %>%
    left_join(msg_by_time, by = "time")

  # --- Extract SART metadata from TRIAL_VAR lines and tag event rows ---
  msg_clean <- msg_tbl %>%
    mutate(
      row_id = row_number(),

      blockId_val   = str_match(text, "^!V TRIAL_VAR blockId\\s+(.+)$")[, 2],
      trialType_val = str_match(text, "^!V TRIAL_VAR trialType\\s+(.+)$")[, 2],
      stimulus_val  = str_match(text, "^!V TRIAL_VAR stimulus\\s+(.+)$")[, 2],
      corrAns_val   = str_match(text, "^!V TRIAL_VAR corrAns\\s+(.+)$")[, 2],

      event_type = case_when(
        str_detect(text, "^0 number_ONSET$") ~ "number_onset",
        str_detect(text, "^0 number_OFFSET$|^-3 number_OFFSET$") ~ "number_offset",
        str_detect(text, "^0 fixation_ONSET$") ~ "fixation_onset",
        str_detect(text, "fixation_OFFSET") & !str_detect(text, "probe1_isi_fixation_OFFSET") ~ "fixation_offset",
        str_detect(text, "^0 probe_text_ONSET$") ~ "probe_onset",
        str_detect(text, "probe_text_OFFSET") ~ "probe_offset",
        str_detect(text, "^0 probe1_isi_fixation_ONSET$") ~ "probe_fixation_onset",
        str_detect(text, "probe1_isi_fixation_OFFSET") ~ "probe_fixation_offset",
        TRUE ~ NA_character_
      )
    ) %>%
    tidyr::fill(blockId_val, trialType_val, stimulus_val, corrAns_val, .direction = "down")

  # --- Counts ---
  n_number_onset         <- sum(msg_clean$event_type == "number_onset", na.rm = TRUE)
  n_number_offset        <- sum(msg_clean$event_type == "number_offset", na.rm = TRUE)
  n_fixation_onset       <- sum(msg_clean$event_type == "fixation_onset", na.rm = TRUE)
  n_fixation_offset      <- sum(msg_clean$event_type == "fixation_offset", na.rm = TRUE)
  n_probe_onset          <- sum(msg_clean$event_type == "probe_onset", na.rm = TRUE)
  n_probe_offset         <- sum(msg_clean$event_type == "probe_offset", na.rm = TRUE)
  n_probe_fixation_onset <- sum(msg_clean$event_type == "probe_fixation_onset", na.rm = TRUE)
  n_probe_fixation_off   <- sum(msg_clean$event_type == "probe_fixation_offset", na.rm = TRUE)

  cat("number_ONSET:", n_number_onset, "\n")
  cat("number_OFFSET:", n_number_offset, "\n")
  cat("fixation_ONSET:", n_fixation_onset, "\n")
  cat("fixation_OFFSET:", n_fixation_offset, "\n")
  cat("probe_text_ONSET:", n_probe_onset, "\n")
  cat("probe_text_OFFSET:", n_probe_offset, "\n")
  cat("probe_fixation_text_ONSET:", n_probe_fixation_onset, "\n")
  cat("probe_fixation_text_OFFSET:", n_probe_fixation_off, "\n")
  cat("Total behavioral events:", n_number_onset + n_probe_onset, "\n")

  # --- Build SART trial tables ---
  # Number trials
  sart_onsets <- msg_clean %>%
    filter(event_type == "number_onset") %>%
    mutate(sart_trial = row_number()) %>%
    transmute(
      sart_trial,
      onset_time = time,
      blockId = blockId_val,
      trialType = trialType_val,
      stimulus = stimulus_val,
      corrAns = corrAns_val,
      row_id,
      onset_text = text
    )

  sart_offsets <- msg_clean %>%
    filter(event_type == "number_offset") %>%
    mutate(sart_trial = row_number()) %>%
    transmute(
      sart_trial,
      offset_time = time,
      offset_text = text
    )

  sart_tbl <- sart_onsets %>%
    left_join(sart_offsets, by = "sart_trial") %>%
    mutate(
      duration_ms = offset_time - onset_time,
      event_family = "sart"
    )

  # Probe trials
  probe_onsets <- msg_clean %>%
    filter(event_type == "probe_onset") %>%
    mutate(probe_trial = row_number()) %>%
    transmute(
      probe_trial,
      onset_time = time,
      blockId = blockId_val,
      trialType = trialType_val,
      stimulus = stimulus_val,
      corrAns = corrAns_val,
      row_id,
      onset_text = text
    )

  probe_offsets <- msg_clean %>%
    filter(event_type == "probe_offset") %>%
    mutate(probe_trial = row_number()) %>%
    transmute(
      probe_trial,
      offset_time = time,
      offset_text = text
    )

  probe_tbl <- probe_onsets %>%
    left_join(probe_offsets, by = "probe_trial") %>%
    mutate(
      duration_ms = offset_time - onset_time,
      event_family = "probe"
    )

  # Combined behavioral table, ordered by onset time
  trial_tbl <- bind_rows(
    sart_tbl %>% mutate(probe_trial = NA_integer_),
    probe_tbl %>% mutate(sart_trial  = NA_integer_)
  ) %>%
    arrange(onset_time) %>%
    mutate(behavioral_trial = row_number()) %>%
    select(
      behavioral_trial,
      event_family,
      sart_trial,
      probe_trial,
      onset_time,
      offset_time,
      duration_ms,
      blockId,
      trialType,
      stimulus,
      corrAns,
      row_id,
      onset_text,
      offset_text
    )

  # --- Save outputs ---
  if (save_csv) {
    if (!is.null(parsed$raw))   write_csv(parsed$raw,   fs::path(out_dir, paste0(id, "_raw.csv")))
    if (!is.null(parsed$fix))   write_csv(parsed$fix,   fs::path(out_dir, paste0(id, "_fix.csv")))
    if (!is.null(parsed$sac))   write_csv(parsed$sac,   fs::path(out_dir, paste0(id, "_sac.csv")))
    if (!is.null(parsed$blink)) write_csv(parsed$blink, fs::path(out_dir, paste0(id, "_blink.csv")))
    if (!is.null(parsed$msg))   write_csv(parsed$msg,   fs::path(out_dir, paste0(id, "_msg.csv")))
    write_csv(raw_with_id_msg,   fs::path(out_dir, paste0(id, "_raw_with_id_msg.csv")))
    write_csv(msg_clean,         fs::path(out_dir, paste0(id, "_msg_clean.csv")))
    write_csv(sart_tbl,          fs::path(out_dir, paste0(id, "_sart_trials.csv")))
    write_csv(probe_tbl,         fs::path(out_dir, paste0(id, "_probe_trials.csv")))
    write_csv(trial_tbl,         fs::path(out_dir, paste0(id, "_trial_tbl.csv")))
  }

  saveRDS(
    list(
      raw = raw,
      msg = msg_tbl,
      msg_clean = msg_clean,
      raw_with_id_msg = raw_with_id_msg,
      sart_tbl = sart_tbl,
      probe_tbl = probe_tbl,
      trial_tbl = trial_tbl
    ),
    out_rds
  )

  # --- Summary row ---
  hz_est <- 1000 / stats::median(diff(raw_with_id_msg$time), na.rm = TRUE)

  per_file <- data.frame(
    id          = id,
    n_raw       = nrow(parsed$raw),
    n_fix       = nrow(parsed$fix   %||% data.frame()),
    n_sac       = nrow(parsed$sac   %||% data.frame()),
    n_blink     = nrow(parsed$blink %||% data.frame()),
    n_msg       = nrow(parsed$msg),
    n_number_onset  = n_number_onset,
    n_number_offset = n_number_offset,
    n_fixation_onset = n_fixation_onset,
    n_fixation_offset = n_fixation_offset,
    n_probe_onset   = n_probe_onset,
    n_probe_offset   = n_probe_offset,
    n_probe_fix_on  = n_probe_fixation_onset,
    n_probe_fix_off = n_probe_fixation_off,
    hz          = round(hz_est, 2),
    stringsAsFactors = FALSE
  )

  per_file
}

# ================================
# Batch run
# ================================
REPARSE_IF_ASC_NEWER <- FALSE

asc_id <- function(p) fs::path_ext_remove(fs::path_file(p))

expected_outputs <- function(id, out_dir = OUT_DIR) {
  c(
    fs::path(out_dir, paste0(id, ".rds")),
    fs::path(out_dir, paste0(id, "_raw_with_id_msg.csv"))
  )
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
  tryCatch(
    parse_asc_save_sart(f, OUT_DIR, save_csv = TRUE),
    error = function(e) {
      message("Error parsing ", f, ": ", e$message)
      NULL
    }
  )
})

ok <- Filter(Negate(is.null), summaries)

if (length(ok)) {
  df_summary <- do.call(rbind, ok)
  write_csv(df_summary, file.path(OUT_DIR, "_summary.csv"))
  cat("Summary written to:", file.path(OUT_DIR, "_summary.csv"), "\n")
}