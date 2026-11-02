% SYNTAX:
% isc = ba_video_isc(params)
%
%
% DESCRIPTION:
% Pairwise (dyadic) intersubject correlation for the videos, following the
% CICI Brain AnalyzIR approach:
%   - input = short-separation-regressed (AR-IRLS ShortDistanceFilter),
%     HRF-shifted, z-scored video blocks from ba_preprocess_subject;
%   - for every pair of subjects that watched the same video, and every
%     channel kept in BOTH subjects, the two time series are correlated with
%     nirs.sFC.ar_corr (AR-prewhitened, robust Pearson correlation);
%   - isc_z = atanh(isc_r) (Fisher z), computed per dyad.
% Group statistics are done in R (e.g. crossed random effects
% (1|sub1) + (1|sub2)); MATLAB stops at the dyad table.
%
%
% OUTPUTS (params.paths.outdir/isc/):
%     dyad_video_channel_ar_isc.csv - one row per video x dyad x chromophore x
%         channel: Video, sub1, sub2, Chromophore, Channel, isc_r, isc_z,
%         isc_p, n_overlap, n_channels, ar_order
%     dyad_video_roi_ar_isc.csv     - same per ROI (params.isc.roi_map): the
%         z-scored channels of each ROI are averaged WITHIN each subject
%         (>= params.isc.min_roi_channels valid channels), then correlated
%
% NOTES:
%     - Blocks of the two subjects are aligned from the video onset (+ shift)
%       and truncated to the shorter one.
%     - Dyads are not doubled here.
%     - Runtime grows with subjects^2; the full sample can take a while.
function isc = ba_video_isc(params)

outDir = fullfile(params.paths.outdir, 'isc');
if ~isfolder(outDir), mkdir(outDir); end

M = readtable(fullfile(params.paths.outdir, 'processing_manifest.csv'), 'TextType', 'string');
M = M(M.Task == "video" & M.Status == "complete", :);
if params.isc.skip_bad_subjects
    M = M(~M.BadSubject, :);
end

% ---- Load blocks ----
blocks = struct();
for i = 1:height(M)
    f = fullfile(params.paths.outdir, 'video', M.Group(i), M.Subject(i), ...
        sprintf('%s_video_BA.mat', M.Subject(i)));
    S = load(f, 'blocks');
    blocks.(char(M.Subject(i))) = S.blocks;
end
subs = string(fieldnames(blocks));

videos = matlab.lang.makeValidName(cellstr(params.video.names));
vars = {'Video', 'sub1', 'sub2', 'Chromophore', 'Unit', 'isc_r', 'isc_z', ...
    'isc_p', 'n_overlap', 'n_channels', 'ar_order'};
rowsCh  = cell(0, numel(vars));
rowsRoi = cell(0, numel(vars));
roiNames = fieldnames(params.isc.roi_map);

for v = 1:numel(videos)
    vid = videos{v};
    has = subs(arrayfun(@(s) isfield(blocks.(char(s)), vid), subs));
    fprintf('ISC %s: %d subjects, %d dyads\n', vid, numel(has), numel(has) * (numel(has) - 1) / 2);
    for a = 1:numel(has) - 1
        for b = a + 1:numel(has)
            for chrom = string(params.isc.chromophores)
                A = blocks.(char(has(a))).(vid).(char(chrom));
                B = blocks.(char(has(b))).(vid).(char(chrom));
                n = min(size(A.data, 1), size(B.data, 1));
                order = round(params.isc.ar_order_xFs * A.Fs);
                minRows = params.isc.min_overlap_sec * A.Fs;

                % ---- Channel level ----
                for c = 1:numel(A.labels)
                    [r, p, nOk] = pairCorr(A.data(1:n, c), B.data(1:n, c), order, params.isc.robust, minRows);
                    if isnan(r), continue, end
                    rowsCh(end+1, :) = {string(vid), has(a), has(b), chrom, A.labels(c), ...
                        r, atanh(r), p, nOk, 1, order}; %#ok<AGROW>
                end

                % ---- ROI level: average channels within subject, then correlate ----
                % (each subject needs >= min_roi_channels valid channels in the ROI)
                for k = 1:numel(roiNames)
                    inRoi = ismember(A.labels, string(params.isc.roi_map.(roiNames{k})));
                    [xa, na] = roiSeries(A.data(1:n, inRoi), params.isc.min_roi_channels);
                    [xb, nb] = roiSeries(B.data(1:n, inRoi), params.isc.min_roi_channels);
                    if isempty(xa) || isempty(xb), continue, end
                    [r, p, nOk] = pairCorr(xa, xb, order, params.isc.robust, minRows);
                    if isnan(r), continue, end
                    rowsRoi(end+1, :) = {string(vid), has(a), has(b), chrom, string(roiNames{k}), ...
                        r, atanh(r), p, nOk, min(na, nb), order}; %#ok<AGROW>
                end
            end
        end
    end
end

iscCh  = cell2table(rowsCh,  'VariableNames', vars);
iscRoi = cell2table(rowsRoi, 'VariableNames', vars);
iscCh  = renamevars(iscCh,  'Unit', 'Channel');
iscRoi = renamevars(iscRoi, 'Unit', 'ROI');
writetable(iscCh,  fullfile(outDir, 'dyad_video_channel_ar_isc.csv'));
writetable(iscRoi, fullfile(outDir, 'dyad_video_roi_ar_isc.csv'));
fprintf('ISC: %d channel rows, %d ROI rows written to %s\n', height(iscCh), height(iscRoi), outDir);
if height(iscCh) == 0
    warning('BA:NoDyads', 'No dyads: no two subjects share a video (normal for a small test run).');
end
isc = iscCh;
end

function [r, p, nOk] = pairCorr(x1, x2, order, robust, minRows)
x = [x1(:), x2(:)];
x = x(all(isfinite(x), 2), :);
nOk = size(x, 1);
r = NaN; p = NaN;
if nOk < minRows
    return
end
[R, P] = nirs.sFC.ar_corr(x, order, robust);
r = R(1, 2);
p = P(1, 2);
end

function [x, nValid] = roiSeries(X, minChannels)
valid = any(isfinite(X), 1);
nValid = sum(valid);
if nValid < minChannels
    x = [];
else
    x = mean(X(:, valid), 2, 'omitnan');
end
end
