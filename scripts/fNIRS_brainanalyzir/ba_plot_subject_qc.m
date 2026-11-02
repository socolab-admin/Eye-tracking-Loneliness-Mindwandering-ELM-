% SYNTAX:
% ba_plot_subject_qc(od, odMC, channels, chanTable, params, filePrefix)
%
%
% DESCRIPTION:
% Saves two per-subject QC figures (PNG, figures not shown on screen):
%   <prefix>_TDDR_signals.png - optical density before (grey) and after
%       TDDR (colour) for the params.output.plot_channels long channels with
%       the LOWEST motion-clean fraction before correction (worst first),
%       one wavelength (first column) per channel.
%   <prefix>_channel_QC.png   - per channel: motion-free % before/after TDDR
%       with the min_clean line, and QT-NIRS quality fraction with the
%       quality_threshold line; bad channels marked.
function ba_plot_subject_qc(od, odMC, channels, chanTable, params, filePrefix)

isLong = ~channels.IsShort;
[~, order] = sort(chanTable.MotionCleanBefore + 10 * ~isLong);   % long channels, worst first
nShow = min(params.output.plot_channels, sum(isLong));
show = order(1:nShow);
t = od.time - od.time(1);

%% ---- Figure 1: before / after TDDR ----
f = figure('Visible', 'off', 'Position', [100 100 1200 180 * nShow]);
for i = 1:nShow
    c = show(i);
    col = channels.Cols{c}(1);
    subplot(nShow, 1, i);
    plot(t, od.data(:, col), 'Color', [0.6 0.6 0.6]); hold on
    plot(t, odMC.data(:, col), 'Color', [0.10 0.35 0.75]);
    ylabel('\DeltaOD');
    title(sprintf('%s  |  motion-free %.0f%% before, %.0f%% after TDDR', ...
        channels.Label(c), 100 * chanTable.MotionCleanBefore(c), ...
        100 * chanTable.MotionCleanAfter(c)), 'FontWeight', 'normal');
    if i == 1, legend({'before TDDR', 'after TDDR'}, 'Location', 'northeast'); end
    if i == nShow, xlabel('Time (s)'); end
end
exportgraphics(f, [filePrefix '_TDDR_signals.png'], 'Resolution', 110);
close(f);

%% ---- Figure 2: per-channel motion and quality ----
f = figure('Visible', 'off', 'Position', [100 100 1300 650]);
x = 1:height(chanTable);

subplot(2,1,1);
bar(x, 100 * [chanTable.MotionCleanBefore, chanTable.MotionCleanAfter]);
hold on
yline(100 * params.qc.motion.min_clean, 'r--', sprintf('%.0f%% threshold', 100 * params.qc.motion.min_clean));
ylabel('Motion-free signal (%)'); ylim([0 105]);
legend({'before TDDR', 'after TDDR'}, 'Location', 'southwest');
set(gca, 'XTick', x, 'XTickLabel', chanTable.Label, 'XTickLabelRotation', 90, 'FontSize', 7);
title('Motion-free signal per channel', 'FontWeight', 'normal');

subplot(2,1,2);
b = bar(x, 100 * chanTable.QualityFraction, 'FaceColor', 'flat');
b.CData = repmat([0.10 0.55 0.35], numel(x), 1);
b.CData(chanTable.Bad, :) = repmat([0.80 0.20 0.20], sum(chanTable.Bad), 1);
b.CData(chanTable.IsShort & ~chanTable.Bad, :) = repmat([0.55 0.55 0.55], sum(chanTable.IsShort & ~chanTable.Bad), 1);
hold on
yline(100 * params.qc.quality_threshold, 'k--', sprintf('%.0f%% good windows', 100 * params.qc.quality_threshold));
ylabel('Good QT-NIRS windows (%)'); ylim([0 105]);
set(gca, 'XTick', x, 'XTickLabel', chanTable.Label, 'XTickLabelRotation', 90, 'FontSize', 7);
title(sprintf('Channel quality: green kept, red bad (%d), grey short', sum(chanTable.Bad)), ...
    'FontWeight', 'normal');

exportgraphics(f, [filePrefix '_channel_QC.png'], 'Resolution', 110);
close(f);
end
