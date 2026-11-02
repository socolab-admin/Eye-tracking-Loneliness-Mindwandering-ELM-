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
%         isc_p, n_overlap, ar_order
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
rows = {};
for v = 1:numel(videos)
    vid = videos{v};
    has = subs(arrayfun(@(s) isfield(blocks.(char(s)), vid), subs));
    fprintf('ISC %s: %d subjects, %d dyads\n', vid, numel(has), nchoosek(max(numel(has),2), 2) * (numel(has) > 1));
    for a = 1:numel(has) - 1
        for b = a + 1:numel(has)
            for chrom = string(params.isc.chromophores)
                A = blocks.(char(has(a))).(vid).(char(chrom));
                B = blocks.(char(has(b))).(vid).(char(chrom));
                n = min(size(A.data, 1), size(B.data, 1));
                order = round(params.isc.ar_order_xFs * A.Fs);
                for c = 1:numel(A.labels)
                    x = [A.data(1:n, c), B.data(1:n, c)];
                    x = x(all(isfinite(x), 2), :);
                    if size(x, 1) < params.isc.min_overlap_sec * A.Fs
                        continue
                    end
                    [R, P] = nirs.sFC.ar_corr(x, order, params.isc.robust);
                    r = R(1, 2);
                    rows(end+1, :) = {string(vid), has(a), has(b), chrom, A.labels(c), ...
                        r, atanh(r), P(1, 2), size(x, 1), order}; %#ok<AGROW>
                end
            end
        end
    end
end

isc = cell2table(rows, 'VariableNames', {'Video', 'sub1', 'sub2', 'Chromophore', ...
    'Channel', 'isc_r', 'isc_z', 'isc_p', 'n_overlap', 'ar_order'});
outFile = fullfile(outDir, 'dyad_video_channel_ar_isc.csv');
writetable(isc, outFile);
fprintf('ISC: %d rows written to %s\n', height(isc), outFile);
end
