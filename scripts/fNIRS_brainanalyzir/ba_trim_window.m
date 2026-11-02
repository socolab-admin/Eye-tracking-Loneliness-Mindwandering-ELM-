% SYNTAX:
% [firstSample, lastSample] = ba_trim_window(tri, trimParams, fs, nSamples)
%
%
% DESCRIPTION:
% Same trimming rule as scripts/fNIRS/run_preprocessing.m:
%   firstSample = FIRST start_trigger sample - round(buffer * fs)
%   lastSample  = LAST  end_trigger sample
% Unlike the Homer3 version, a missing trigger raises an error that the
% batch runner catches, so only this subject/task is skipped.
%
%
% INPUTS:
% tri        - table from ba_read_tri.
% trimParams - params.trim.video or params.trim.SART.
% fs         - native sampling rate (Hz).
% nSamples   - number of samples in the recording.
function [firstSample, lastSample] = ba_trim_window(tri, trimParams, fs, nSamples)

startIdx = find(tri.Code == trimParams.start_trigger, 1, 'first');
endIdx   = find(tri.Code == trimParams.end_trigger,   1, 'last');

if isempty(startIdx)
    error('BA:NoStartTrigger', 'Start trigger %d not found.', trimParams.start_trigger);
end
if isempty(endIdx)
    error('BA:NoEndTrigger', 'End trigger %d not found.', trimParams.end_trigger);
end

firstSample = tri.Sample(startIdx) - round(trimParams.buffer * fs);
lastSample  = tri.Sample(endIdx);

% ---- Keep inside the recording ----
firstSample = max(firstSample, 1);
lastSample  = min(lastSample, nSamples);

if lastSample <= firstSample
    error('BA:BadTrim', 'End trigger (%d) is before start trigger (%d).', ...
        lastSample, firstSample);
end
end
