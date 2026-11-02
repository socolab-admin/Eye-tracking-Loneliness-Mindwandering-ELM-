% SYNTAX:
% events = ba_sart_events(tri, time, logFile, sartParams)
%
%
% DESCRIPTION:
% Builds the SART event table. Every code-5 trigger is one SART event
% (trial or probe), matched IN ORDER to the PsychoPy log rows that have a
% trialType (same matching as scripts/fNIRS/SART_stim_builder.m).
%
% Event labels:
%   NonTarget      - frequent go trials (any response)
%   TargetCorrect  - target (digit 3) correctly withheld (key_resp.corr = 1)
%   TargetError    - commission error on a target (key_resp.corr = 0)
%   ProbeMW        - thought probe answered "Yes, mind-wandering" (Right)
%   ProbeOnTask    - thought probe answered "No" (Left)
% plus pre-probe windows (PreProbeMW / PreProbeOnTask) of
% preprobe_window_sec seconds ending at each probe onset.
%
%
% INPUTS:
% tri        - table from ba_read_tri (untrimmed).
% time       - native SNIRF time vector (sec), untrimmed.
% logFile    - PsychoPy SART log (.csv).
% sartParams - params.sart.
%
%
% OUTPUTS:
% events - table: Event, Condition, OnsetSec, DurationSec, IsPractice,
%          TrialType, KeyCorr, ProbeKey, LogRow.
%
% NOTES:
%     - The number of code-5 triggers must equal the number of log rows with
%       a trialType, otherwise the subject is skipped (error).
%     - Practice uses the log column blocks.thisN == 0 by default, the same
%       definition as the eye-tracking side (blockId == "Practice").
function events = ba_sart_events(tri, time, logFile, sartParams)

% ---- Read log (keeps dotted PsychoPy names, e.g. key_resp.corr) ----
opts = detectImportOptions(logFile, 'VariableNamingRule', 'preserve', ...
    'Encoding', 'UTF-8');
opts = setvartype(opts, opts.VariableNames, 'char');
T = readtable(logFile, opts);
T.Properties.VariableNames = erase(T.Properties.VariableNames, char(65279)); % BOM

trialType = string(getCol(T, 'trialType'));
valid = strlength(strtrim(trialType)) > 0;
T = T(valid, :);
trialType = lower(strtrim(trialType(valid)));
logRow = find(valid);

% ---- Code-5 onsets ----
onsetSamples = tri.Sample(tri.Code == sartParams.onset_trigger);
onsetSamples = onsetSamples(onsetSamples >= 1 & onsetSamples <= numel(time));

if numel(onsetSamples) ~= height(T)
    error('BA:SartCount', ...
        'Code-%d triggers (%d) do not match log rows with a trialType (%d).', ...
        sartParams.onset_trigger, numel(onsetSamples), height(T));
end
onsetSec = time(onsetSamples);
onsetSec = onsetSec(:);
n = numel(onsetSec);

% ---- Practice ----
switch lower(string(sartParams.practice_rule))
    case "log"
        blockN = str2double(string(getCol(T, 'blocks.thisN')));
        assert(~all(isnan(blockN)), 'blocks.thisN not found in %s.', logFile);
        isPractice = blockN == 0;
    case "first_n"
        isPractice = false(n,1);
        isPractice(1:min(sartParams.practice_n, n)) = true;
    otherwise
        error('Unknown practice_rule: %s', sartParams.practice_rule);
end
isPractice = isPractice(:);

% ---- Responses ----
keyCorr  = str2double(string(getCol(T, 'key_resp.corr')));
probeKey = lower(strtrim(string(getCol(T, 'probe1_resp.keys'))));
probeStart = str2double(string(getCol(T, 'probe1.started')));
probeStop  = str2double(string(getCol(T, 'probe1.stopped')));

isProbe     = contains(trialType, 'probe');
isNonTarget = contains(trialType, 'non');
isTarget    = ~isProbe & ~isNonTarget & contains(trialType, 'target');

Condition = strings(n,1);
Condition(isNonTarget) = "NonTarget";
Condition(isTarget & keyCorr == 1) = "TargetCorrect";
Condition(isTarget & keyCorr == 0) = "TargetError";
Condition(isProbe & probeKey == lower(sartParams.probe_mw_key)) = "ProbeMW";
Condition(isProbe & probeKey ~= lower(sartParams.probe_mw_key) & ...
    strlength(probeKey) > 0 & probeKey ~= "none") = "ProbeOnTask";
Condition(Condition == "") = "Other";

Duration = repmat(sartParams.stim_duration, n, 1);
probeDur = probeStop - probeStart;
useProbeDur = isProbe & isfinite(probeDur) & probeDur > 0;
Duration(useProbeDur) = probeDur(useProbeDur);

Event = repmat("trial", n, 1);
Event(isProbe) = "probe";

events = table(Event, Condition, onsetSec, Duration, isPractice, ...
    trialType, keyCorr, probeKey, logRow(:), ...
    'VariableNames', {'Event', 'Condition', 'OnsetSec', 'DurationSec', ...
    'IsPractice', 'TrialType', 'KeyCorr', 'ProbeKey', 'LogRow'});

% ---- Pre-probe windows (main block only) ----
probeRows = find(isProbe & ~isPractice & ...
    (Condition == "ProbeMW" | Condition == "ProbeOnTask"));
pre = events(probeRows, :);
pre.Event(:) = "preprobe";
pre.Condition = "Pre" + pre.Condition;          % PreProbeMW / PreProbeOnTask
pre.OnsetSec = pre.OnsetSec - sartParams.preprobe_window_sec;
pre.DurationSec(:) = sartParams.preprobe_window_sec;
events = [events; pre];
events = sortrows(events, 'OnsetSec');
end

function col = getCol(T, name)
names = T.Properties.VariableNames;
idx = find(strcmp(names, name), 1);
if isempty(idx)
    % readtable may rename "key_resp.corr" -> "key_resp_corr"
    idx = find(strcmp(names, strrep(name, '.', '_')), 1);
end
if isempty(idx)
    col = repmat({''}, height(T), 1);
else
    col = T{:, idx};
end
end
