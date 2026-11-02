% SYNTAX:
% [summary, chanTable] = ba_preprocess_subject(subj, task, params)
%
%
% DESCRIPTION:
% Preprocesses ONE subject for ONE task ("video" or "SART") with Brain
% AnalyzIR and saves the outputs used by ba_video_isc / ba_sart_glm.
%
%
% INPUTS:
% subj   - struct with fields ID, Group, Folder, Snirf, Tri, Probe, Log.
% task   - "video" or "SART".
% params - struct from create_params_ba().
%
%
% OUTPUTS (written to outdir/<task>/<Group>/<ID>/):
%     <ID>_<task>_BA.mat      - hb (and hbClean for video), channels, events,
%                               trim info, QC tables
%     <ID>_<task>_channels.csv- per-channel QC and keep/drop decision
%     <ID>_<task>_events.csv  - event table used for the analysis
%     video: <ID>_<Video>_<HbO|HbR>_BA.csv - one z-scored block per video
%     SART:  <ID>_SART_<HbO|HbR>_BA.csv    - full segment + 0/1 event columns
%     figures/ - before/after TDDR signals and motion-clean per channel
%
% summary   - one-row table for the batch manifest.
% chanTable - per-channel QC table (also saved to CSV).
%
%
% PREPROCESSING STEPS:
% 1. Load SNIRF, probeInfo and .tri; trim with the task's trigger rule
% 2. Build events (video pairs or SART code-5 + log)
% 3. QC on raw intensity at native fs (QT-NIRS SCI/PSP windows, saturation)
% 4. Resample to params.prep.resample_fs (4 Hz)
% 5. Intensity -> optical density
% 6. Motion check BEFORE TDDR, TDDR, motion check AFTER TDDR
% 7. Optical density -> HbO/HbR (modified Beer-Lambert, Brain AnalyzIR PPF)
% 8. Mark bad channels: failed QC, saturated, < min_clean motion-free
%    (if enabled), or excluded by label
% 9. Short channels:
%       video - AR-IRLS short-separation regression (ShortDistanceFilter)
%               BEFORE any correlation; then bad + short channels -> NaN
%       SART  - short channels kept and labelled for the GLM
% 10. Export and save
%
%
% NOTES:
%     - Times stay on the ORIGINAL recording clock (data is trimmed, not
%       re-zeroed), so .tri samples map to time(sample) at every step.
%     - No band-pass filter is applied to the analysis signal.
function [summary, chanTable] = ba_preprocess_subject(subj, task, params)

task = string(task);
outDir = fullfile(params.paths.outdir, char(task), char(subj.Group), char(subj.ID));
figDir = fullfile(outDir, 'figures');
if ~isfolder(figDir), mkdir(figDir); end

%% ===============================
%% 1. LOAD + TRIM
%% ===============================
[raw, channels] = ba_load_subject(subj.Snirf, subj.Probe, params);
tri = ba_read_tri(subj.Tri);
fsNative = raw.Fs;
timeNative = raw.time;

[firstSample, lastSample] = ba_trim_window(tri, params.trim.(task), fsNative, numel(timeNative));
raw.data = raw.data(firstSample:lastSample, :);
raw.time = raw.time(firstSample:lastSample);
fprintf('%s %s: trimmed samples %d-%d (%.1f s)\n', subj.ID, task, ...
    firstSample, lastSample, raw.time(end) - raw.time(1));

%% ===============================
%% 2. EVENTS
%% ===============================
unmatched = table();
if task == "video"
    [events, unmatched] = ba_video_events(tri, timeNative, params.video);
    nEvents = height(events);
else
    assert(strlength(subj.Log) > 0, 'No SART log found for %s.', subj.ID);
    events = ba_sart_events(tri, timeNative, subj.Log, params.sart);
    nEvents = sum(events.Event ~= "preprobe" & ~events.IsPractice);
end

%% ===============================
%% 3. QC (raw intensity, native fs)
%% ===============================
qc = ba_channel_qc(raw, channels, params.qc);

%% ===============================
%% 4-6. RESAMPLE -> OD -> TDDR
%% ===============================
job = nirs.modules.Resample();
job.Fs = params.prep.resample_fs;
raw4 = job.run(raw);

job = nirs.modules.OpticalDensity();
od = job.run(raw4);
channels.Cols = ba_channel_cols(od, channels);   % columns are unchanged, re-checked

cleanBefore = ba_motion_clean(od, channels, params.qc.motion);

switch lower(params.prep.motion_correction)
    case "tddr"
        job = nirs.modules.TDDR();
        odMC = job.run(od);
    case "none"
        odMC = od;
    otherwise
        error('Unknown motion_correction: %s', params.prep.motion_correction);
end
cleanAfter = ba_motion_clean(odMC, channels, params.qc.motion);

%% ===============================
%% 7. BEER-LAMBERT
%% ===============================
job = nirs.modules.BeerLambertLaw();
job.PPF = params.prep.PPF;
hb = job.run(odMC);
hb.demographics('subject') = char(subj.ID);
hb.demographics('group')   = char(subj.Group);
hb.demographics('task')    = char(task);

%% ===============================
%% 8. CHANNEL DECISIONS
%% ===============================
lowMotion = cleanBefore < params.qc.motion.min_clean;
Bad = ~qc.PassQuality | qc.Saturated | channels.Excluded;
if params.qc.motion.use_for_exclusion
    Bad = Bad | lowMotion;
end
Reason = strings(height(channels), 1);
Reason(~qc.PassQuality) = Reason(~qc.PassQuality) + "quality;";
Reason(qc.Saturated)    = Reason(qc.Saturated) + "saturated;";
Reason(lowMotion)       = Reason(lowMotion) + "motion<" + params.qc.motion.min_clean + ";";
Reason(channels.Excluded) = Reason(channels.Excluded) + "excluded_by_label;";

isLong = ~channels.IsShort;
UsedAsShortRegressor = channels.ShortUsed & ~Bad;
KeepForAnalysis = isLong & ~Bad;
propBadLong = mean(Bad(isLong));
badSubject = propBadLong >= params.qc.bad_subject_threshold;

chanTable = [table(repmat(string(subj.ID), height(channels), 1), ...
    repmat(task, height(channels), 1), 'VariableNames', {'Subject', 'Task'}), ...
    channels(:, {'Index', 'Label', 'IsShort'}), ...
    qc(:, {'SCI_mean', 'PSP_mean', 'QualityFraction', 'PassQuality', 'Saturated'}), ...
    table(cleanBefore, cleanAfter, lowMotion, channels.Excluded, Bad, Reason, ...
    UsedAsShortRegressor, KeepForAnalysis, 'VariableNames', {'MotionCleanBefore', ...
    'MotionCleanAfter', 'LowMotionClean', 'ExcludedByLabel', 'Bad', 'Reason', ...
    'UsedAsShortRegressor', 'KeepForAnalysis'})];

% ---- Short-separation flags = good short channels kept as regressors ----
hb = ba_set_short_flags(hb, channels, UsedAsShortRegressor);
nShortUsed = sum(UsedAsShortRegressor);

%% ===============================
%% 9-10. TASK-SPECIFIC + EXPORT
%% ===============================
saveVars = struct('channels', channels, 'chanTable', chanTable, 'events', events, ...
    'unmatched', unmatched, 'firstSample', firstSample, 'lastSample', lastSample, ...
    'fsNative', fsNative, 'subj', subj, 'params', params);

if task == "video"
    if params.shortsep.video.use && nShortUsed > 0
        job = advanced.nirs.modules.ShortDistanceFilter();
        job.maxnumcomp = params.shortsep.video.maxnumcomp;
        job.splittypes = params.shortsep.video.splittypes;
        hbClean = job.run(hb);
    else
        if params.shortsep.video.use
            warning('BA:NoShort', '%s: no usable short channel; no regression.', subj.ID);
        end
        hbClean = hb;
    end
    hbClean = ba_mask_channels(hbClean, channels, ~KeepForAnalysis);
    blocks = ba_export_video_blocks(hbClean, events, channels, params, outDir, subj.ID);
    saveVars.hbClean = hbClean;
    saveVars.blocks = blocks;
else
    hb = ba_add_sart_stimuli(hb, events);
    if params.output.save_csv
        ba_export_sart_csv(hb, events, channels, KeepForAnalysis, outDir, subj.ID);
    end
end
saveVars.hb = hb;

if params.output.save_mat
    save(fullfile(outDir, sprintf('%s_%s_BA.mat', subj.ID, task)), '-struct', 'saveVars', '-v7.3');
end
writetable(chanTable, fullfile(outDir, sprintf('%s_%s_channels.csv', subj.ID, task)));
writetable(events, fullfile(outDir, sprintf('%s_%s_events.csv', subj.ID, task)));

if params.output.plot_subject
    ba_plot_subject_qc(od, odMC, channels, chanTable, params, ...
        fullfile(figDir, sprintf('%s_%s', subj.ID, task)));
end

%% ===============================
%% SUMMARY ROW
%% ===============================
summary = table(string(subj.ID), string(subj.Group), task, "complete", "", ...
    raw.time(end) - raw.time(1), fsNative, hb.Fs, nEvents, sum(isLong), ...
    sum(KeepForAnalysis), nShortUsed, propBadLong, badSubject, ...
    mean(cleanBefore(isLong), 'omitnan'), mean(cleanAfter(isLong), 'omitnan'), ...
    sum(lowMotion & isLong), height(unmatched), ...
    'VariableNames', {'Subject', 'Group', 'Task', 'Status', 'Message', ...
    'DurationSec', 'FsNative', 'FsAnalysis', 'NEvents', 'NLong', 'NLongKept', ...
    'NShortUsed', 'PropBadLong', 'BadSubject', 'MeanMotionCleanBefore', ...
    'MeanMotionCleanAfter', 'NLongLowMotion', 'NUnmatchedVideoPairs'});
end

%% =========================================================================
%% LOCAL FUNCTIONS
%% =========================================================================
function cols = ba_channel_cols(data, channels)
link = data.probe.link;
cols = cell(height(channels), 1);
for c = 1:height(channels)
    cols{c} = find(link.source == channels.Source(c) & ...
        link.detector == channels.Detector(c))';
end
end

function hb = ba_set_short_flags(hb, channels, useAsShort)
% Short-separation flag = good short channels only, so the regression never
% uses a bad or dropped short channel.
link = hb.probe.link;
flag = false(height(link), 1);
for c = find(useAsShort)'
    flag(link.source == channels.Source(c) & link.detector == channels.Detector(c)) = true;
end
link.ShortSeperation = flag;
hb.probe.link = link;
end

function hb = ba_mask_channels(hb, channels, maskChannel)
link = hb.probe.link;
for c = find(maskChannel)'
    rows = link.source == channels.Source(c) & link.detector == channels.Detector(c);
    hb.data(:, rows) = NaN;
end
end

function hb = ba_add_sart_stimuli(hb, events)
% Main-block events only (practice removed); one condition per label.
ev = events(~events.IsPractice, :);
conds = unique(ev.Condition);
conds = conds(conds ~= "Other");
for i = 1:numel(conds)
    e = ev(ev.Condition == conds(i), :);
    st = nirs.design.StimulusEvents(char(conds(i)), e.OnsetSec, e.DurationSec, ones(height(e), 1));
    hb.stimulus(char(conds(i))) = st;
end
end

function blocks = ba_export_video_blocks(hb, events, channels, params, outDir, subjectID)
% Window = [onset, offset] + HRF shift (HbO 4.5 s, HbR 6 s), measured offset.
blocks = struct();
types = ["HbO", "HbR"];
for v = 1:height(events)
    name = matlab.lang.makeValidName(char(events.Video(v)));
    for t = types
        tf = char(t);
        shift = params.video.hrf_shift_sec.(tf);
        t0 = events.OnsetSec(v) + shift;
        t1 = events.OffsetSec(v) + shift;
        rows = hb.time >= t0 & hb.time <= t1;
        if ~any(rows)
            warning('BA:EmptyBlock', '%s %s %s: window outside the recording.', ...
                subjectID, name, t);
            continue
        end
        X = ba_hb_matrix(hb, channels, lower(t), rows);
        if params.video.zscore
            X = (X - mean(X, 1, 'omitnan')) ./ std(X, 0, 1, 'omitnan');
        end
        tt = hb.time(rows) - t0;
        blocks.(name).(tf).time = tt;
        blocks.(name).(tf).data = X;
        blocks.(name).(tf).labels = channels.Label;
        blocks.(name).(tf).Fs = hb.Fs;
        blocks.(name).(tf).shift = shift;
        if params.output.save_csv
            T = array2table([tt, X], 'VariableNames', [{'time'}, cellstr(channels.Label')]);
            writetable(T, fullfile(outDir, sprintf('%s_%s_%s_BA.csv', subjectID, name, t)));
        end
    end
end
end

function ba_export_sart_csv(hb, events, channels, keep, outDir, subjectID)
% Full SART segment with 0/1 columns per condition (for eye-tracking sync).
ev = events(~events.IsPractice & events.Event ~= "preprobe", :);
conds = setdiff(unique(ev.Condition), "Other");
flags = zeros(numel(hb.time), numel(conds));
for i = 1:numel(conds)
    e = ev(ev.Condition == conds(i), :);
    for k = 1:height(e)
        flags(hb.time >= e.OnsetSec(k) & hb.time < e.OnsetSec(k) + e.DurationSec(k), i) = 1;
    end
end
for t = ["hbo", "hbr"]
    X = ba_hb_matrix(hb, channels, t, true(numel(hb.time), 1));
    X(:, ~keep) = NaN;   % short + bad channels blanked in the export
    T = array2table([hb.time, X, flags], 'VariableNames', ...
        [{'time'}, cellstr(channels.Label'), cellstr(conds')]);
    tag = "HbO"; if t == "hbr", tag = "HbR"; end
    writetable(T, fullfile(outDir, sprintf('%s_SART_%s_BA.csv', subjectID, tag)));
end
end

function X = ba_hb_matrix(hb, channels, type, rows)
link = hb.probe.link;
linkType = lower(string(link.type));
X = nan(sum(rows), height(channels));
for c = 1:height(channels)
    col = find(link.source == channels.Source(c) & link.detector == channels.Detector(c) & linkType == type);
    if numel(col) == 1
        X(:, c) = hb.data(rows, col);
    end
end
end
