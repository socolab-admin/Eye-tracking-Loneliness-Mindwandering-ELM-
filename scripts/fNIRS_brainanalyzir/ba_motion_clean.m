% SYNTAX:
% [cleanFrac, motionMask] = ba_motion_clean(od, channels, motionParams)
%
%
% DESCRIPTION:
% Motion detection on optical density, same rule as Homer3
% hmrR_MotionArtifactByChannel (used by scripts/fNIRS/run_preprocessing.m):
%   std_diff = std of the sample-to-sample change of each measurement;
%   a sample t is motion when, within the next tMotion sec,
%       max |d(t+j) - d(t)| > STDEV * std_diff   OR   > AMP;
%   +/- tMask sec around each motion sample is also marked.
% A channel's motion-clean fraction is the mean of its two wavelengths'
% motion-free proportions (same as the Homer3 pipeline).
% Run on OD before TDDR and again after TDDR to check the correction.
%
%
% INPUTS:
% od           - nirs.core.Data in optical density.
% channels     - channel table from ba_load_subject.
% motionParams - params.qc.motion.
%
%
% OUTPUTS:
% cleanFrac  - [nChannels x 1] proportion of motion-free samples (0-1).
% motionMask - [nSamples x nChannels] logical, true = motion.
function [cleanFrac, motionMask] = ba_motion_clean(od, channels, motionParams)

fs = od.Fs;
nLag  = max(1, round(motionParams.tMotion * fs));
nMask = round(motionParams.tMask * fs);
nT = size(od.data, 1);
nCh = height(channels);

cleanFrac = nan(nCh, 1);
motionMask = false(nT, nCh);

for c = 1:nCh
    cols = channels.Cols{c};
    fracs = nan(1, numel(cols));
    chMask = false(nT, 1);
    for k = 1:numel(cols)
        d = od.data(:, cols(k));
        if all(~isfinite(d))
            fracs(k) = 0;
            chMask(:) = true;
            continue
        end
        stdDiff = std(diff(d), 'omitnan');
        maxDiff = zeros(nT, 1);
        for j = 1:nLag
            dj = abs(d(1+j:end) - d(1:end-j));
            maxDiff(1:end-j) = max(maxDiff(1:end-j), dj);
        end
        motion = maxDiff > motionParams.STDEV * stdDiff | ...
                 maxDiff > motionParams.AMP;
        if nMask > 0
            motion = movmax(double(motion), [nMask nMask]) > 0;
        end
        fracs(k) = 1 - mean(motion);
        chMask = chMask | motion;
    end
    cleanFrac(c) = mean(fracs);
    motionMask(:, c) = chMask;
end
end
