% SYNTAX:
% params = create_params_ba()
%
%
% DESCRIPTION:
% Creates the parameter structure for the ELM Brain AnalyzIR (nirs-toolbox)
% pipeline. Every option used by run_main_ba and the ba_* functions is set
% here so a run is fully described by this one struct. run_main_ba saves the
% struct to params_summary_BA.xlsx and params_BA.mat in the output folder
% after each run, for methods reporting and reproducibility.
%
%
% OUTPUTS:
% params: Struct containing all pipeline configuration parameters.
%
% --- Paths ---
%   params.paths:
%       rawdir   - Folder with G*/S* subject folders. Each subject folder must
%                  contain *.snirf, *_lsl.tri and *_probeInfo.mat.
%       logdir   - Folder with PsychoPy SART logs named <N>_sart*.csv
%                  (N = subject number without leading zeros, e.g. S02 -> 2).
%       outdir   - Output root. Everything (per-subject files, QC tables,
%                  figures, ISC and GLM results, params) is written under it.
%       toolbox  - Brain AnalyzIR (nirs-toolbox) folder; added to the path.
%
% --- Subject selection ---
%   params.subjects:
%       include  - String array of subject IDs to run (e.g. ["S02","S70"]).
%                  Empty = all subjects found in rawdir.
%       exclude  - Subject IDs never run (e.g. subjects without a .tri).
%       skip_folder_pattern - Folders whose name contains this are skipped
%                  (same "x" exclusion convention used in the lab folders).
%
% --- Tasks ---
%   params.tasks: "video", "SART" or both. Each task is trimmed and
%                 preprocessed separately from the same SNIRF file.
%
% --- Trimming (same trigger logic as scripts/fNIRS/run_preprocessing.m) ---
%   params.trim.(task):
%       start_trigger - First occurrence marks the start of the segment.
%       end_trigger   - Last occurrence marks the end of the segment.
%       buffer        - Seconds kept before the start trigger.
%       ELM trigger codes: 1 video onset, 3 video offset, 4 end of video block,
%       5 SART event onset (every trial and probe), 8 last SART code.
%
% --- Video events (same pairing as scripts/fNIRS/run_postprocessing.m) ---
%   params.video:
%       start_trigger / end_trigger - 1 / 3. Walk the .tri rows in order, keep
%                       the LAST start code before each end code (absorbs double
%                       pulses and code-1 bursts).
%       names / durations - Nominal video lengths (sec). A pair is assigned to a
%                       video when |measured - nominal| <= tolerance_sec.
%       tolerance_sec - [DEFAULT 3] Matching window (sec).
%       hrf_shift_sec - Export window shift per chromophore: HbO 4.5 s, HbR 6 s
%                       (Huppert et al., 2006). Window = [onset, offset] + shift.
%       zscore        - Z-score each exported video block per channel.
%
% --- SART events ---
%   params.sart:
%       onset_trigger  - 5. Every code 5 is one SART event (trial or probe).
%       practice_rule  - "log" uses the PsychoPy column blocks.thisN == 0 to mark
%                        practice (preferred, matches the eye-tracking side);
%                        "first_n" drops the first practice_n events
%                        (old fNIRS rule).
%       stim_duration  - Duration (sec) of Target / NonTarget events (250 ms).
%       probe_mw_key   - probe1_resp.keys value meaning "Yes, mind-wandering"
%                        (the probe reads No [Left] / Yes [Right]).
%       preprobe_window_sec - Length of the pre-probe window used for the
%                        on-task vs mind-wandering regressors.
%
% --- Channel quality control (raw intensity, native sampling rate) ---
%   params.qc:
%       method     - "QT-NIRS": windowed SCI and PSP on the cardiac band
%                    (Hernandez & Pollonini, 2020). A window is good if
%                    SCI >= sci_threshold AND PSP >= psp_threshold; a channel
%                    passes if >= quality_threshold of its windows are good.
%       window_sec, cardiac_band - Window length (sec) and band (Hz).
%       motion.*   - Motion detection on optical density, same rule as Homer3
%                    hmrR_MotionArtifactByChannel: a sample is motion if the
%                    signal changes by more than STDEV*std or AMP within tMotion
%                    sec; +/- tMask sec around it is also marked.
%                    min_clean [DEFAULT 0.60] = a channel is flagged when less
%                    than 60% of its samples are motion-free.
%                    use_for_exclusion = also drop channels below min_clean
%                    (otherwise motion is only reported).
%       bad_subject_threshold - Subject flagged when this proportion of LONG
%                    channels is bad.
%
% --- Channels ---
%   params.channels:
%       short_index     - Rows of probeInfo.probes.index_c that are short-separation
%                         channels ([4,11,20,25,30,37,46,51]; detectors D15-D22).
%                         Their S-D labels are printed and checked at load time.
%       short_drop      - Short channels NOT used as regressors, by S-D label.
%                         Default empty = all 8 used.
%       exclude         - Long channels removed by S-D label before analysis
%                         (e.g. ["S3-D7"]). Labels follow probeInfo.probes.index_c.
%
% --- Preprocessing ---
%   params.prep:
%       resample_fs - [DEFAULT 4 Hz] Applied AFTER QC (QC needs the cardiac band).
%       motion_correction - "TDDR" (Fishburn et al., 2019) or "none".
%       PPF         - Brain AnalyzIR partial pathlength factor (toolbox default
%                     0.1). A common scale factor does not change correlations
%                     or z-scored exports.
%       bandpass    - Off. The AR-IRLS models handle serial correlation and
%                     slow drift; no filter is applied to the analysis signal.
%
% --- Short-separation regression ---
%   params.shortsep:
%       video - Applied BEFORE correlation with
%               advanced.nirs.modules.ShortDistanceFilter (AR-IRLS, separate
%               HbO/HbR models).
%       sart  - Not pre-regressed; short channels are added as regressors
%               inside the AR-IRLS GLM (AddShortSepRegressors = true).
%
% --- Outputs and figures ---
%   params.output: save_mat, save_csv, plot_subject, plot_channels.
%
% --- ISC (video) ---
%   params.isc: pairwise AR-prewhitened robust correlation (nirs.sFC.ar_corr)
%               between every pair of subjects that watched the same video.
%       roi_map          - ROI name -> S-D labels; ROI series = mean of the
%                          subject's valid channels in the ROI.
%       min_roi_channels - [DEFAULT 2] valid channels needed per subject/ROI.
%
% --- GLM (SART) ---
%   params.glm: first-level AR-IRLS GLM, group-level mixed effects.
%
function params = create_params_ba()

params = struct();

%% ===============================
%% PATHS
%% ===============================
params.paths.rawdir  = '/Users/evansalvarez/fNIRS/ELM/fNIRS_data';
params.paths.logdir  = '/Users/evansalvarez/fNIRS/ELM/SART_logs';
params.paths.outdir  = '/Users/evansalvarez/fNIRS/ELM_BA_outputs';
params.paths.toolbox = '/Users/evansalvarez/fNIRS/tools/nirs-toolbox';

params.prefix.group   = 'G';
params.prefix.subject = 'S';

%% ===============================
%% SUBJECTS
%% ===============================
params.subjects.include = ["S02", "S70"];  % test run; set to [] for all subjects
params.subjects.exclude = ["S49"];         % S49 has no .tri file
params.subjects.skip_folder_pattern = 'x';  % folders starting with x are skipped

%% ===============================
%% TASKS
%% ===============================
params.tasks = ["video", "SART"];

%% ===============================
%% TRIMMING
%% ===============================
params.trim.video.start_trigger = 1;
params.trim.video.end_trigger   = 4;
params.trim.video.buffer        = 0;

params.trim.SART.start_trigger  = 5;
params.trim.SART.end_trigger    = 8;
params.trim.SART.buffer         = 10;

%% ===============================
%% VIDEO EVENTS
%% ===============================
params.video.start_trigger = 1;
params.video.end_trigger   = 3;
params.video.names     = ["Zima", "Splitscreen", "Sun", "Turtles", "Hexagons", "Igloo", "Winter"];
params.video.durations = [ 508,    145,           325,   385,       373,        313,     319];
params.video.tolerance_sec = 3;
params.video.hrf_shift_sec.HbO = 4.5;
params.video.hrf_shift_sec.HbR = 6;
params.video.zscore = true;

%% ===============================
%% SART EVENTS
%% ===============================
params.sart.onset_trigger = 5;
params.sart.practice_rule = "log";   % "log" (blocks.thisN == 0) or "first_n"
params.sart.practice_n    = 19;      % used only when practice_rule = "first_n"
params.sart.stim_duration = 0.25;
params.sart.probe_mw_key  = "right"; % "Were you mindwandering?" No [Left] / Yes [Right]
params.sart.preprobe_window_sec = 10;

%% ===============================
%% CHANNEL QUALITY ASSESSMENT
%% ===============================
params.qc.method            = "QT-NIRS";
params.qc.window_sec        = 5;
params.qc.cardiac_band      = [0.5 2.5];
params.qc.sci_threshold     = 0.75;
params.qc.psp_threshold     = 0.10;
params.qc.quality_threshold = 0.70;

params.qc.motion.tMotion   = 1;
params.qc.motion.tMask     = 1;
params.qc.motion.STDEV     = 6;
params.qc.motion.AMP       = 5;
params.qc.motion.min_clean = 0.60;
params.qc.motion.use_for_exclusion = true;

params.qc.bad_subject_threshold = 0.50;

%% ===============================
%% CHANNELS
%% ===============================
params.channels.short_index = [4,11,20,25,30,37,46,51]; % rows of probeInfo.probes.index_c (same as create_params.m)
params.channels.short_drop  = strings(1,0);   % first run: use all 8; e.g. ["S1-D15"] drops that short channel
params.channels.exclude   = strings(1,0);                    % e.g. ["S3-D7"]

%% ===============================
%% PREPROCESSING
%% ===============================
params.prep.resample_fs       = 4;
params.prep.motion_correction = "TDDR";
params.prep.PPF               = 0.1;
params.prep.bandpass          = false;

%% ===============================
%% SHORT-SEPARATION REGRESSION
%% ===============================
params.shortsep.video.use          = true;
params.shortsep.video.maxnumcomp   = 6;
params.shortsep.video.splittypes   = true;
params.shortsep.sart.in_glm        = true;

%% ===============================
%% OUTPUTS
%% ===============================
params.output.save_mat      = true;
params.output.save_csv      = true;
params.output.plot_subject  = true;
params.output.plot_channels = 6;    % channels shown in the before/after TDDR plots

%% ===============================
%% ISC (VIDEO)
%% ===============================
params.isc.run          = true;
params.isc.chromophores = ["HbO", "HbR"];
params.isc.ar_order_xFs = 4;        % AR model order = 4 x Fs (as in CICI)
params.isc.robust       = true;
params.isc.min_overlap_sec = 60;    % dyad/channel kept only if >= 60 s overlap
params.isc.skip_bad_subjects = true;
% ROI map (same montage / channel labels as probeInfo.probes.index_c)
params.isc.roi_map.vmPFC  = ["S1-D1","S1-D8","S1-D9"];
params.isc.roi_map.dmPFC  = ["S9-D11","S9-D9","S9-D3","S2-D9","S10-D9"];
params.isc.roi_map.ldlPFC = ["S2-D2","S4-D2","S4-D3","S4-D5","S6-D2","S6-D5","S3-D2"];
params.isc.roi_map.rdlPFC = ["S10-D10","S10-D11","S12-D11","S12-D10","S12-D12","S14-D12","S14-D10","S11-D10"];
params.isc.roi_map.lTPJ   = ["S8-D7","S8-D6","S7-D7","S7-D6"];
params.isc.roi_map.rTPJ   = ["S15-D14","S15-D13","S16-D14","S16-D13"];
params.isc.min_roi_channels = 2;   % a subject needs >= 2 valid channels in the ROI

%% ===============================
%% GLM (SART)
%% ===============================
params.glm.run        = true;
params.glm.type       = 'AR-IRLS';
params.glm.model      = "events";   % "events" or "preprobe"
params.glm.group_formula = 'beta ~ -1 + cond + (1|subject)';
params.glm.contrasts  = ["TargetCorrect-NonTarget", ...
                         "TargetError-TargetCorrect", ...
                         "TargetError-NonTarget"];
params.glm.preprobe_contrasts = ["PreProbeMW-PreProbeOnTask"];
params.glm.skip_bad_subjects  = true;

end
