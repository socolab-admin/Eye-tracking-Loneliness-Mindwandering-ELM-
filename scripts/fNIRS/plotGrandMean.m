function plotGrandMean(data, epochWindow, baselineWindow)

% ============================================================
% plotGrandMean
%
% Plots grand mean HbO and HbR timecourses
% overlaid by condition.
%
% Example:
%   plotGrandMean(data, [-5 20], [-5 0])
%
%
% HbO = solid line
% HbR = dashed line
%
% ============================================================

figure;
hold on;

nCond = length(data{1}.stim);

colors = lines(nCond);

legendNames = {};

% ============================================================
% LOOP CONDITIONS
% ============================================================

for c = 1:nCond

    condName = data{1}.stim(c).name;

    fprintf('Processing condition: %s\n', condName);

    % ========================================================
    % HbO + HbR subject storage
    % ========================================================

    HbO_subjectMeans = {};
    HbR_subjectMeans = {};

    commonTime = [];

    % ========================================================
    % LOOP SUBJECTS
    % ========================================================

    for s = 1:numel(data)

        if isempty(data{s})
            continue;
        end

        if ~isfield(data{s}, 'HbO') || ...
           ~isfield(data{s}, 'HbR') || ...
           ~isfield(data{s}, 't') || ...
           ~isfield(data{s}, 'stim')

            continue;
        end

        if length(data{s}.stim) < c
            continue;
        end

        HbO = data{s}.HbO;
        HbR = data{s}.HbR;

        t = data{s}.t(:);

        stimData = data{s}.stim(c).data;

        if isempty(stimData)
            continue;
        end

        onsetTimes = stimData(:,1);

        % ----------------------------------------------------
        % Relative epoch time
        % ----------------------------------------------------

        dt = median(diff(t));

        relTime = epochWindow(1):dt:epochWindow(2);

        baselineIdx = ...
            relTime >= baselineWindow(1) & ...
            relTime <= baselineWindow(2);

        HbO_eventEpochs = [];
        HbR_eventEpochs = [];

        % ====================================================
        % LOOP EVENTS
        % ====================================================

        for e = 1:numel(onsetTimes)

            absTime = onsetTimes(e) + relTime;

            % ------------------------------------------------
            % Extract epochs
            % ------------------------------------------------

            epochHbO = interp1(t, HbO, ...
                               absTime, ...
                               'linear', NaN);

            epochHbR = interp1(t, HbR, ...
                               absTime, ...
                               'linear', NaN);

            if all(isnan(epochHbO(:)))
                continue;
            end

            % ------------------------------------------------
            % Baseline correction
            % ------------------------------------------------

            baselineHbO = ...
                mean(epochHbO(baselineIdx,:), ...
                1, 'omitnan');

            baselineHbR = ...
                mean(epochHbR(baselineIdx,:), ...
                1, 'omitnan');

            epochHbO = epochHbO - baselineHbO;
            epochHbR = epochHbR - baselineHbR;

            % ------------------------------------------------
            % Mean across channels
            % ------------------------------------------------

            epochMeanHbO = ...
                mean(epochHbO, 2, 'omitnan');

            epochMeanHbR = ...
                mean(epochHbR, 2, 'omitnan');

            HbO_eventEpochs(:,end+1) = epochMeanHbO;
            HbR_eventEpochs(:,end+1) = epochMeanHbR;

        end

        % ----------------------------------------------------
        % Skip empty
        % ----------------------------------------------------

        if isempty(HbO_eventEpochs)
            continue;
        end

        % ----------------------------------------------------
        % Subject means
        % ----------------------------------------------------

        subjMeanHbO = ...
            mean(HbO_eventEpochs, ...
            2, 'omitnan');

        subjMeanHbR = ...
            mean(HbR_eventEpochs, ...
            2, 'omitnan');

        if isempty(commonTime)
            commonTime = relTime(:);
        end

        HbO_subjectMeans{end+1} = subjMeanHbO(:);
        HbR_subjectMeans{end+1} = subjMeanHbR(:);

    end

    % ========================================================
    % Skip empty conditions
    % ========================================================

    if isempty(HbO_subjectMeans)
        continue;
    end

    % ========================================================
    % Build matrices
    % ========================================================

    X_HbO = cat(2, HbO_subjectMeans{:});
    X_HbR = cat(2, HbR_subjectMeans{:});

    % ========================================================
    % Grand means
    % ========================================================

    grandMeanHbO = mean(X_HbO, 2, 'omitnan');
    grandMeanHbR = mean(X_HbR, 2, 'omitnan');

    semHbO = std(X_HbO, 0, 2, 'omitnan') ./ ...
             sqrt(size(X_HbO,2));

    semHbR = std(X_HbR, 0, 2, 'omitnan') ./ ...
             sqrt(size(X_HbR,2));

    % ========================================================
    % HbO shading
    % ========================================================

    fill([commonTime; flipud(commonTime)], ...
         [grandMeanHbO + semHbO; ...
          flipud(grandMeanHbO - semHbO)], ...
         colors(c,:), ...
         'FaceAlpha', 0.20, ...
         'EdgeColor', 'none');

    % ========================================================
    % HbR shading
    % ========================================================

    fill([commonTime; flipud(commonTime)], ...
         [grandMeanHbR + semHbR; ...
          flipud(grandMeanHbR - semHbR)], ...
         colors(c,:), ...
         'FaceAlpha', 0.10, ...
         'EdgeColor', 'none');

    % ========================================================
    % Plot HbO
    % ========================================================

    plot(commonTime, grandMeanHbO, ...
         '-', ...
         'Color', colors(c,:), ...
         'LineWidth', 2);

    % ========================================================
    % Plot HbR
    % ========================================================

    plot(commonTime, grandMeanHbR, ...
         '--', ...
         'Color', colors(c,:), ...
         'LineWidth', 2);

    % ========================================================
    % Legend labels
    % ========================================================

    legendNames{end+1} = sprintf('%s HbO', condName);
    legendNames{end+1} = sprintf('%s HbR', condName);

end

% ============================================================
% Stimulus onset
% ============================================================

xline(0, '--k', ...
    'Stimulus Onset', ...
    'LineWidth', 1.5);

xlabel('Time (s)');
ylabel('\DeltaHb');

title('Grand Mean HbO / HbR Timecourses');

legend(legendNames, ...
       'Location', 'best');

grid on;
box off;

end