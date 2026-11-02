% SYNTAX:
% ba_qc_report(params)
%
%
% DESCRIPTION:
% Group-level QC tables and figures from processing_manifest.csv and
% channel_qc_all.csv (written by ba_run_preprocessing).
%
%
% OUTPUTS (params.paths.outdir/qc_report/):
%     qc_summary.xlsx with sheets
%         Processing        - manifest: per subject x task status, duration,
%                             events, channels kept, motion before/after
%         SubjectRetention  - long channels kept per subject and task
%         ChannelRetention  - per channel: % of subjects where it is kept,
%                             mean SCI / quality / motion-free %
%         LowMotionChannels - every channel with < min_clean motion-free signal
%                             before TDDR, with its value after TDDR
%         BadChannelReasons - counts of exclusion reasons
%     hist_channels_kept_<task>.png    - histogram: long channels kept per subject
%     channel_retention_<task>.png     - % subjects keeping each channel
%     motion_before_after_<task>.png   - motion-free % before vs after TDDR
function ba_qc_report(params)

outDir = fullfile(params.paths.outdir, 'qc_report');
if ~isfolder(outDir), mkdir(outDir); end

M = readtable(fullfile(params.paths.outdir, 'processing_manifest.csv'), 'TextType', 'string');
C = readtable(fullfile(params.paths.outdir, 'channel_qc_all.csv'), 'TextType', 'string');
minClean = params.qc.motion.min_clean;
xlsx = fullfile(outDir, 'qc_summary.xlsx');
if isfile(xlsx), delete(xlsx); end

writetable(M, xlsx, 'Sheet', 'Processing');

long = C(~C.IsShort, :);

% ---- Subject retention ----
S = groupsummary(long, {'Subject', 'Task'}, {'sum', 'mean'}, {'KeepForAnalysis', 'MotionCleanBefore', 'MotionCleanAfter'});
S = renamevars(S, {'GroupCount', 'sum_KeepForAnalysis'}, {'NLong', 'NLongKept'});
writetable(S, xlsx, 'Sheet', 'SubjectRetention');

% ---- Channel retention ----
R = groupsummary(long, {'Task', 'Label'}, 'mean', ...
    {'KeepForAnalysis', 'SCI_mean', 'QualityFraction', 'MotionCleanBefore', 'MotionCleanAfter'});
R.PercentSubjectsKept = 100 * R.mean_KeepForAnalysis;
writetable(R, xlsx, 'Sheet', 'ChannelRetention');

% ---- Low-motion channels ----
L = C(C.MotionCleanBefore < minClean, {'Subject', 'Task', 'Label', 'IsShort', ...
    'MotionCleanBefore', 'MotionCleanAfter', 'Bad', 'Reason'});
L.StillBelowAfterTDDR = L.MotionCleanAfter < minClean;
writetable(L, xlsx, 'Sheet', 'LowMotionChannels');

% ---- Exclusion reasons ----
reasons = ["quality", "saturated", "motion", "excluded_by_label"];
counts = arrayfun(@(r) sum(contains(long.Reason, r)), reasons)';
writetable(table(reasons', counts, 'VariableNames', {'Reason', 'NChannelRows'}), ...
    xlsx, 'Sheet', 'BadChannelReasons');

% ---- Figures per task ----
for task = unique(long.Task)'
    St = S(S.Task == task, :);
    Rt = R(R.Task == task, :);
    Lt = long(long.Task == task, :);

    f = figure('Visible', 'off', 'Position', [100 100 700 450]);
    histogram(St.NLongKept, 'BinMethod', 'integers', 'FaceColor', [0.10 0.35 0.75]);
    xlabel(sprintf('Long channels kept (of %d)', max(St.NLong)));
    ylabel('Subjects');
    title(sprintf('%s: channels kept per subject (n = %d)', task, height(St)), 'FontWeight', 'normal');
    exportgraphics(f, fullfile(outDir, sprintf('hist_channels_kept_%s.png', task)), 'Resolution', 120);
    close(f);

    f = figure('Visible', 'off', 'Position', [100 100 1200 450]);
    bar(Rt.PercentSubjectsKept, 'FaceColor', [0.10 0.55 0.35]);
    set(gca, 'XTick', 1:height(Rt), 'XTickLabel', Rt.Label, 'XTickLabelRotation', 90, 'FontSize', 7);
    ylabel('% of subjects where channel is kept'); ylim([0 100]);
    title(sprintf('%s: channel retention across subjects', task), 'FontWeight', 'normal');
    exportgraphics(f, fullfile(outDir, sprintf('channel_retention_%s.png', task)), 'Resolution', 120);
    close(f);

    f = figure('Visible', 'off', 'Position', [100 100 550 500]);
    scatter(100 * Lt.MotionCleanBefore, 100 * Lt.MotionCleanAfter, 12, 'filled', 'MarkerFaceAlpha', 0.4);
    hold on
    plot([0 100], [0 100], 'k:');
    xline(100 * minClean, 'r--'); yline(100 * minClean, 'r--');
    xlabel('Motion-free % before TDDR'); ylabel('Motion-free % after TDDR');
    axis([0 100 0 100]); axis square
    title(sprintf('%s: motion correction check (each dot = channel x subject)', task), 'FontWeight', 'normal');
    exportgraphics(f, fullfile(outDir, sprintf('motion_before_after_%s.png', task)), 'Resolution', 120);
    close(f);
end

fprintf('QC report written to %s\n', outDir);
end
