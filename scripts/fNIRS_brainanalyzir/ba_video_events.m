% SYNTAX:
% [events, unmatched] = ba_video_events(tri, time, videoParams)
%
%
% DESCRIPTION:
% Builds the video onset/offset table with the same pairing logic as
% scripts/fNIRS/run_postprocessing.m (cond.same = true):
%   - walk the .tri rows in order;
%   - a start code (1) stores/overwrites the current onset;
%   - an end code (3) pairs with the stored onset, then clears it.
% Only the LAST start code before each end code survives, which absorbs the
% 1,1 / 3,3 double pulses and the bursts of duplicate code-1 rows.
% Each pair is assigned to the video whose nominal duration is within
% tolerance_sec of the measured duration (offset - onset).
%
%
% INPUTS:
% tri         - table from ba_read_tri (untrimmed).
% time        - native SNIRF time vector (sec), untrimmed.
% videoParams - params.video.
%
%
% OUTPUTS:
% events    - table: Video, OnsetSample, OffsetSample, OnsetSec, OffsetSec,
%             MeasuredSec, NominalSec, DiffSec.
% unmatched - pairs that matched no video (reported, not used). The Homer3
%             pipeline dropped these silently.
%
% NOTES:
%     - Igloo (313 s), Winter (319 s) and Sun (325 s) are 6 s apart, so with
%       a 3 s tolerance their windows touch. A pair matching two videos is an
%       error rather than a silent double assignment.
function [events, unmatched] = ba_video_events(tri, time, videoParams)

onsetSamples  = zeros(0,1);
offsetSamples = zeros(0,1);
lastOnset = [];

% ---- Pair start/end codes ----
for k = 1:height(tri)
    code = tri.Code(k);
    if ismember(code, videoParams.start_trigger)
        lastOnset = tri.Sample(k);                 % remember the most recent 1
    elseif ismember(code, videoParams.end_trigger)
        if ~isempty(lastOnset)
            onsetSamples(end+1,1)  = lastOnset;    %#ok<AGROW>
            offsetSamples(end+1,1) = tri.Sample(k); %#ok<AGROW>
            lastOnset = [];                        % consume that 1
        end
    end
end

nSamples = numel(time);
inRange = onsetSamples >= 1 & offsetSamples <= nSamples;
onsetSamples  = onsetSamples(inRange);
offsetSamples = offsetSamples(inRange);

onsetSec  = time(onsetSamples);
offsetSec = time(offsetSamples);
measured  = offsetSec(:) - onsetSec(:);

% ---- Match each pair to a nominal duration ----
names = string(videoParams.names);
durations = videoParams.durations(:)';
Video = strings(numel(measured), 1);
Nominal = nan(numel(measured), 1);
for i = 1:numel(measured)
    hit = find(abs(measured(i) - durations) <= videoParams.tolerance_sec);
    if numel(hit) > 1
        error('BA:VideoAmbiguous', ...
            'Pair %d (%.2f s) matches more than one video: %s', ...
            i, measured(i), strjoin(names(hit), ', '));
    elseif numel(hit) == 1
        Video(i) = names(hit);
        Nominal(i) = durations(hit);
    end
end

allPairs = table(Video, onsetSamples(:), offsetSamples(:), onsetSec(:), ...
    offsetSec(:), measured, Nominal, measured - Nominal, ...
    'VariableNames', {'Video', 'OnsetSample', 'OffsetSample', 'OnsetSec', ...
    'OffsetSec', 'MeasuredSec', 'NominalSec', 'DiffSec'});

matched = strlength(allPairs.Video) > 0;
events = allPairs(matched, :);
unmatched = allPairs(~matched, :);

if height(unmatched) > 0
    warning('BA:VideoUnmatched', '%d onset/offset pair(s) matched no video: %s s', ...
        height(unmatched), mat2str(round(unmatched.MeasuredSec', 1)));
end
if numel(unique(events.Video)) < height(events)
    warning('BA:VideoRepeated', 'A video appears more than once in this session.');
end
end
