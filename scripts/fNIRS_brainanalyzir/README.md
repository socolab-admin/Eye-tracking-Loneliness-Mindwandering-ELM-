# ELM Brain AnalyzIR pipeline

Brain AnalyzIR (nirs-toolbox) version of the ELM fNIRS pipeline, for **video ISC** and **SART GLM**.
The Homer3 pipeline in `scripts/fNIRS/` is unchanged.

Run in MATLAB:

```matlab
run_main_ba          % uses create_params_ba.m
```

## Steps

| Step | What | Function |
|---|---|---|
| 1 | Parameters (all options in one struct); saved to `params_summary_BA.xlsx` + `params_BA.mat` in the output folder | `create_params_ba`, `save_params_to_excel_ba` |
| 2 | Find `G*/S*` subjects; batch with a manifest (a failing subject is logged, batch continues) | `ba_find_subjects`, `ba_run_preprocessing` |
| 3 | Trim with the same trigger rule as Homer3 (video 1→4, no buffer; SART 5→8, 10 s buffer) | `ba_read_tri`, `ba_trim_window` |
| 4 | Events: video 1→3 pairs matched by duration (±3 s); SART code 5 matched to the PsychoPy log, practice from `blocks.thisN == 0` | `ba_video_events`, `ba_sart_events` |
| 5 | QC on raw intensity at native fs: QT-NIRS SCI/PSP windows, saturation | `ba_channel_qc` |
| 6 | Resample to 4 Hz → optical density → motion check → **TDDR** → motion check | `ba_preprocess_subject`, `ba_motion_clean` |
| 7 | Beer-Lambert (HbO/HbR) | `ba_preprocess_subject` |
| 8 | Bad channels: failed quality, saturated, < 60% motion-free, or excluded by S-D label | `ba_preprocess_subject` |
| 9 | Video: AR-IRLS short-channel regression (`ShortDistanceFilter`) **before** correlation; HRF-shifted (HbO 4.5 s, HbR 6 s), z-scored block per video | `ba_preprocess_subject` |
| 10 | SART: short channels kept as GLM regressors; CSV with 0/1 event columns | `ba_preprocess_subject` |
| 11 | QC report: channels kept per subject (histogram), channel retention, low-motion table, before/after TDDR | `ba_qc_report`, `ba_plot_subject_qc` |
| 12 | Video dyadic ISC with `nirs.sFC.ar_corr` (AR-prewhitened robust r, Fisher z) | `ba_video_isc` |
| 13 | SART first-level AR-IRLS GLM + mixed-effects group model and contrasts | `ba_sart_glm` |

## SART GLM regressors

One regressor per event type; comparisons are contrasts:

- `NonTarget` (frequent go trials), `TargetCorrect` (withheld), `TargetError` (commission error)
- `ProbeMW` / `ProbeOnTask` (probe screen, "Were you mindwandering just before the probe?")
- optional (`params.glm.model = "preprobe"`): `PreProbeMW` / `PreProbeOnTask` windows before each probe

Default contrasts: `TargetCorrect-NonTarget`, `TargetError-TargetCorrect`, `TargetError-NonTarget`
(+ `PreProbeMW-PreProbeOnTask` for the pre-probe model).

## Outputs (`params.paths.outdir`)

```
params_summary_BA.xlsx, params_BA.mat
processing_manifest.csv, channel_qc_all.csv
qc_report/        qc_summary.xlsx + PNG figures
video/G*/S*/      <S>_video_BA.mat, <S>_<Video>_<HbO|HbR>_BA.csv, channels/events CSV, figures/
SART/G*/S*/       <S>_SART_BA.mat, <S>_SART_<HbO|HbR>_BA.csv, channels/events CSV, figures/
isc/              dyad_video_channel_ar_isc.csv
glm_events/       subject_betas.csv, group_conditions.csv, group_contrasts.csv
```

## Removing channels

- Long channels: `params.channels.exclude = ["S3-D7"];` (labels from `probeInfo.probes.index_c`)
- Short channels: `params.channels.short_drop = ["S1-D15"];` (default: all 8 used)
