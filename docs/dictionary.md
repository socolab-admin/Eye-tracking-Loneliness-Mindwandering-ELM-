# UCLA Loneliness Scores

This dataset contains participant-level scores from the 20-item UCLA Loneliness Scale. Each row corresponds to a single participant and summarizes questionnaire completion and the total UCLA Loneliness Scale score.

| Column Name  | Data Type | Description                                                                                  | Sample Value |
| :----------- | :-------- | :------------------------------------------------------------------------------------------- | :----------- |
| `pid`        | STRING    | Unique participant identifier.                                                               | `01`         |
| `n_answered` | INTEGER   | Number of UCLA Loneliness Scale items completed by the participant.                          | `20`         |
| `ucla_total` | INTEGER   | Total UCLA Loneliness Scale score, computed as the sum of all completed questionnaire items. | `16`         |

# fNIRS Video-Viewing

This dataset contains processed fNIRS recordings collected during the video-viewing task. Each CSV file contains time-series measurements of changes in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for a single participant and video stimulus. Rows correspond to fNIRS samples, and columns correspond to 51 fNIRS channels represented as source–detector pairs (e.g., `S1-D1`). The complete list of source–detector channels is provided in the repository's montage documentation.

| Column Name | Data Type | Description                                                                                                 | Sample Value |
| :---------- | :-------- | :---------------------------------------------------------------------------------------------------------- | :----------- |
| `time`      | FLOAT     | Recording time in seconds.                                                                                  | `125.31`     |
| `S1-D1`     | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 1–Detector 1 channel.   | `0.124`      |
| `...`       | FLOAT     | Additional source–detector channels included in the fNIRS montage.                                          | `...`        |
| `S16-D22`   | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 16–Detector 22 channel. | `0.055`      |

# fNIRS SART (`postprocessed_mat`)

This dataset contains processed fNIRS recordings collected during the Sustained Attention to Response Task (SART). Each MATLAB (`.mat`) file contains participant-level post-processed fNIRS data, including oxyhemoglobin (HbO), deoxyhemoglobin (HbR), and total hemoglobin (HbT) concentration time series, stimulus timing information, probe geometry, quality-control metrics, and additional metadata. These files serve as the primary input for event-related General Linear Model (GLM) analyses.

| Variable Name    | Data Type | Description                                                                            |
| :--------------- | :-------- | :------------------------------------------------------------------------------------- |
| `HbO`            | MATRIX    | Processed oxyhemoglobin (HbO) concentration time series for all fNIRS channels.        |
| `HbR`            | MATRIX    | Processed deoxyhemoglobin (HbR) concentration time series for all fNIRS channels.      |
| `HbT`            | MATRIX    | Processed total hemoglobin (HbT) concentration time series for all fNIRS channels.     |
| `t`              | VECTOR    | Recording time in seconds.                                                             |
| `fs`             | FLOAT     | Sampling frequency (Hz).                                                               |
| `stim`           | STRUCT    | Stimulus timing, duration, and condition information used for event-related analyses.  |
| `tri_raw`        | STRUCT    | Raw trigger information recorded during fNIRS acquisition.                             |
| `quality_report` | TABLE     | Channel- and participant-level quality-control metrics generated during preprocessing. |
| `idx_short`      | VECTOR    | Indices corresponding to short-separation channels.                                    |
| `probeInfo`      | STRUCT    | Source–detector geometry and channel layout information.                               |
| `SD`             | STRUCT    | fNIRS probe and measurement configuration information.                                 |
| `dhbFilt`        | STRUCT    | Filtered hemoglobin concentration signals generated during preprocessing.              |
| `subjectID`      | STRING    | Unique participant identifier.                                                         |

# fNIRS SART (`hbo_hbr_csv`)

This dataset contains processed fNIRS recordings collected during the Sustained Attention to Response Task (SART) and exported from the post-processed MATLAB files. Each CSV file contains time-series measurements of changes in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for a single participant. Additional columns identify the SART task condition (Target, Non-Target, or Probe) for each fNIRS sample to support synchronization with eye-tracking data and event-related analyses.

| Column Name      | Data Type | Description                                                                                                 | Sample Value |
| :--------------- | :-------- | :---------------------------------------------------------------------------------------------------------- | :----------- |
| `time`           | FLOAT     | Recording time in seconds.                                                                                  | `125.31`     |
| `S1-D1`          | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 1–Detector 1 channel.   | `0.124`      |
| `...`            | FLOAT     | Additional source–detector channels included in the fNIRS montage.                                          | `...`        |
| `S16-D22`        | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 16–Detector 22 channel. | `0.055`      |
| `SART_Target`    | BOOLEAN   | Indicates whether the fNIRS sample occurred during a SART target trial.                                     | `0`          |
| `SART_NonTarget` | BOOLEAN   | Indicates whether the fNIRS sample occurred during a SART non-target trial.                                 | `1`          |
| `SART_Probe`     | BOOLEAN   | Indicates whether the fNIRS sample occurred during a SART thought-probe trial.                              | `0`          |

# Eye-Tracking Video-Viewing/SART

This table describes the common data structure shared by both the Video-Viewing Eye-Tracking and the SART Eye-Tracking datasets. Each CSV file contains processed eye-tracking recordings for a single participant, including gaze position, pupil size, blink detection, interpolation flags, and derived binocular gaze measures. Task-specific variables (e.g., stimulus in the Video-Viewing dataset) are included where applicable. Rows correspond to eye-tracking samples, and columns correspond to recorded or derived eye-tracking variables.

| Column Name    | Data Type | Description                                                                                                                 | Sample Value          |
| :------------- | :-------- | :-------------------------------------------------------------------------------------------------------------------------- | :-------------------- |
| `block`        | INTEGER   | PsychoPy experimental block identifier.                                                                                     | `3`                   |
| `time`         | INTEGER   | Raw eye-tracking timestamp (ms).                                                                                            | `5726282`             |
| `xpl`          | FLOAT     | Raw left-eye horizontal gaze position (pixels).                                                                             | `961.3`               |
| `ypl`          | FLOAT     | Raw left-eye vertical gaze position (pixels).                                                                               | `508.0`               |
| `psl`          | FLOAT     | Raw left-eye pupil size.                                                                                                    | `3121`                |
| `xpr`          | FLOAT     | Raw right-eye horizontal gaze position (pixels).                                                                            | `945.1`               |
| `ypr`          | FLOAT     | Raw right-eye vertical gaze position (pixels).                                                                              | `525.7`               |
| `psr`          | FLOAT     | Raw right-eye pupil size.                                                                                                   | `2333`                |
| `input`        | INTEGER   | EyeLink input channel value.                                                                                                | `0`                   |
| `cr.info`      | STRING    | Corneal reflection information recorded by the EyeLink system.                                                              | `.....`               |
| `tx`           | FLOAT     | EyeLink target x-position.                                                                                                  | `5297`                |
| `ty`           | FLOAT     | EyeLink target y-position.                                                                                                  | `3256`                |
| `td`           | FLOAT     | EyeLink target distance.                                                                                                    | `557.4`               |
| `remote.info`  | STRING    | EyeLink remote-tracking metadata.                                                                                           | `.................`   |
| `id`           | STRING    | Unique participant identifier.                                                                                              | `03_2025_03_03_17_03` |
| `msg`*         | STRING    | Event message logged during recording.                                                                                      | `0 number_ONSET ...`  |
| `stimulus`     | STRING    | Video stimulus presented during the recording.                                                                              | `Hexagons`            |
| `t_rel_ms`     | FLOAT     | Time relative to stimulus onset (ms).                                                                                       | `0`                   |
| `blink_L`      | BOOLEAN   | Left-eye blink flag.                                                                                                        | `FALSE`               |
| `blink_R`      | BOOLEAN   | Right-eye blink flag.                                                                                                       | `FALSE`               |
| `offbounds_Lx` | BOOLEAN   | Left-eye horizontal gaze position outside screen bounds.                                                                    | `FALSE`               |
| `offbounds_Ly` | BOOLEAN   | Left-eye vertical gaze position outside screen bounds.                                                                      | `FALSE`               |
| `offbounds_Rx` | BOOLEAN   | Right-eye horizontal gaze position outside screen bounds.                                                                   | `FALSE`               |
| `offbounds_Ry` | BOOLEAN   | Right-eye vertical gaze position outside screen bounds.                                                                     | `FALSE`               |
| `interp_psl`   | BOOLEAN   | Left-eye pupil interpolation flag.                                                                                          | `FALSE`               |
| `interp_psr`   | BOOLEAN   | Right-eye pupil interpolation flag.                                                                                         | `FALSE`               |
| `interp_xpl`   | BOOLEAN   | Left-eye horizontal gaze interpolation flag.                                                                                | `FALSE`               |
| `interp_ypl`   | BOOLEAN   | Left-eye vertical gaze interpolation flag.                                                                                  | `FALSE`               |
| `interp_xpr`   | BOOLEAN   | Right-eye horizontal gaze interpolation flag.                                                                               | `FALSE`               |
| `interp_ypr`   | BOOLEAN   | Right-eye vertical gaze interpolation flag.                                                                                 | `FALSE`               |
| `psl_i`        | FLOAT     | Interpolated left-eye pupil size.                                                                                           | `3121`                |
| `psr_i`        | FLOAT     | Interpolated right-eye pupil size.                                                                                          | `2333`                |
| `xpl_i`        | FLOAT     | Interpolated left-eye horizontal gaze position.                                                                             | `961.3`               |
| `ypl_i`        | FLOAT     | Interpolated left-eye vertical gaze position.                                                                               | `508.0`               |
| `xpr_i`        | FLOAT     | Interpolated right-eye horizontal gaze position.                                                                            | `945.1`               |
| `ypr_i`        | FLOAT     | Interpolated right-eye vertical gaze position.                                                                              | `525.7`               |
| `ps`           | FLOAT     | Combined binocular pupil size.                                                                                              | `2727`                |
| `xp`           | FLOAT     | Combined binocular horizontal gaze position.                                                                                | `953.2`               |
| `yp`           | FLOAT     | Combined binocular vertical gaze position.                                                                                  | `516.85`              |
| `fallback_ps`  | BOOLEAN   | Indicates that the combined pupil size was computed using a single eye because the other eye was unavailable.               | `FALSE`               |
| `fallback_x`   | BOOLEAN   | Indicates that the combined horizontal gaze position was computed using a single eye because the other eye was unavailable. | `FALSE`               |
| `fallback_y`   | BOOLEAN   | Indicates that the combined vertical gaze position was computed using a single eye because the other eye was unavailable.   | `FALSE`               |

* In some processed datasets, this column may be named `text` instead of `msg`; both contain EyeLink event messages.


# Synchronized Eye–fNIRS Video-Viewing

This dataset contains time-aligned processed eye-tracking and fNIRS recordings collected during the video-viewing task. Eye-tracking and fNIRS data were synchronized using Lab Streaming Layer (LSL) timestamps acquired during data collection. Each CSV file contains one fNIRS sample per row, the corresponding synchronized eye-tracking measures aggregated within each fNIRS sampling interval, and the associated fNIRS channel measurements.

| Column Name  | Data Type | Description                                                                                                 | Sample Value |
| :----------- | :-------- | :---------------------------------------------------------------------------------------------------------- | :----------- |
| `time`       | FLOAT     | Original fNIRS recording time (seconds).                                                                    | `125.31`     |
| `S1-D1`      | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 1–Detector 1 channel.   | `0.124`      |
| `...`        | FLOAT     | Additional source–detector channels included in the fNIRS montage.                                          | `...`        |
| `S16-D22`    | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 16–Detector 22 channel. | `0.055`      |
| `t_rel_s`    | FLOAT     | Time relative to the start of the synchronized recording (seconds).                                         | `15.36`      |
| `eye_n`      | INTEGER   | Number of eye-tracking samples contributing to the synchronized fNIRS sample.                               | `102`        |
| `xp`         | FLOAT     | Mean binocular horizontal gaze position.                                                                    | `953.82`     |
| `yp`         | FLOAT     | Mean binocular vertical gaze position.                                                                      | `517.46`     |
| `ps`         | FLOAT     | Mean binocular pupil size.                                                                                  | `1284.67`    |
| `xpl_i`      | FLOAT     | Interpolated left-eye horizontal gaze position.                                                             | `951.24`     |
| `xpr_i`      | FLOAT     | Interpolated right-eye horizontal gaze position.                                                            | `956.40`     |
| `ypl_i`      | FLOAT     | Interpolated left-eye vertical gaze position.                                                               | `518.01`     |
| `ypr_i`      | FLOAT     | Interpolated right-eye vertical gaze position.                                                              | `516.91`     |
| `psl_i`      | FLOAT     | Interpolated left-eye pupil size.                                                                           | `1280.44`    |
| `psr_i`      | FLOAT     | Interpolated right-eye pupil size.                                                                          | `1288.90`    |
| `blink_prop` | FLOAT     | Proportion of eye-tracking samples classified as blinks within the synchronized fNIRS sampling interval.    | `0.00`       |

# Synchronized Eye–fNIRS SART 

This dataset contains time-aligned processed eye-tracking and fNIRS recordings collected during the Sustained Attention to Response Task (SART). Eye-tracking and fNIRS data were synchronized using Lab Streaming Layer (LSL) timestamps acquired during data collection. Each CSV file contains one fNIRS sample per row, synchronized eye-tracking measures, and SART event markers for multimodal analyses.

| Column Name      | Data Type | Description                                                                                                 | Sample Value |
| :--------------- | :-------- | :---------------------------------------------------------------------------------------------------------- | :----------- |
| `time`           | FLOAT     | Original fNIRS recording time (seconds).                                                                    | `125.31`     |
| `S1-D1`          | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 1–Detector 1 channel.   | `0.124`      |
| `...`            | FLOAT     | Additional source–detector channels included in the fNIRS montage.                                          | `...`        |
| `S16-D22`        | FLOAT     | Change in oxyhemoglobin (HbO) or deoxyhemoglobin (HbR) concentration for the Source 16–Detector 22 channel. | `0.055`      |
| `SART_Target`    | BOOLEAN   | Indicates whether the synchronized sample occurred during a SART target trial.                              | `0`          |
| `SART_NonTarget` | BOOLEAN   | Indicates whether the synchronized sample occurred during a SART non-target trial.                          | `1`          |
| `SART_Probe`     | BOOLEAN   | Indicates whether the synchronized sample occurred during a SART thought-probe trial.                       | `0`          |
| `t_rel_s`        | FLOAT     | Time relative to the start of the synchronized recording (seconds).                                         | `18.22`      |
| `eye_n`          | INTEGER   | Number of eye-tracking samples contributing to the synchronized fNIRS sample.                               | `101`        |
| `xp`             | FLOAT     | Mean binocular horizontal gaze position.                                                                    | `954.36`     |
| `yp`             | FLOAT     | Mean binocular vertical gaze position.                                                                      | `520.15`     |
| `ps`             | FLOAT     | Mean binocular pupil size.                                                                                  | `1291.82`    |
| `xpl_i`          | FLOAT     | Interpolated left-eye horizontal gaze position.                                                             | `953.11`     |
| `xpr_i`          | FLOAT     | Interpolated right-eye horizontal gaze position.                                                            | `955.62`     |
| `ypl_i`          | FLOAT     | Interpolated left-eye vertical gaze position.                                                               | `519.43`     |
| `ypr_i`          | FLOAT     | Interpolated right-eye vertical gaze position.                                                              | `520.87`     |
| `psl_i`          | FLOAT     | Interpolated left-eye pupil size.                                                                           | `1288.75`    |
| `psr_i`          | FLOAT     | Interpolated right-eye pupil size.                                                                          | `1294.89`    |
| `blink_prop`     | FLOAT     | Proportion of eye-tracking samples classified as blinks within the synchronized fNIRS sampling interval.    | `0.01`       |
