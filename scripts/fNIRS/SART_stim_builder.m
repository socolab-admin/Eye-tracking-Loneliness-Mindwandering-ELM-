matDir = 'fNIRS_processed_SART';
logDir = 'SART_logs';

matFiles = dir(fullfile(matDir,'*_postprocessed_SART.mat'));

for iSub = 1:length(matFiles)

    matFile = fullfile(matFiles(iSub).folder, ...
                       matFiles(iSub).name);

    fprintf('\nProcessing %s\n', matFiles(iSub).name);

    % -------------------------
    % Extract subject number
    % -------------------------

    tok = regexp(matFiles(iSub).name,...
                 'S(\d+)_postprocessed_SART',...
                 'tokens');

    if isempty(tok)
        fprintf('Could not parse subject number\n');
        continue
    end

    subjNum = str2double(tok{1}{1});

    % -------------------------
    % Find matching log
    % -------------------------

    logFiles = dir(fullfile(logDir,...
                     sprintf('%d_sart*.csv',subjNum)));

    if isempty(logFiles)
        fprintf('No log found for subject %d\n',subjNum);
        continue
    end

    logFile = fullfile(logFiles(1).folder,...
                       logFiles(1).name);

    fprintf('Using log: %s\n',logFiles(1).name);

    % -------------------------
    % Run your code
    % -------------------------

    S = load(matFile);
    subject = S.subject_postprocessed;

    stimNames = cell(length(subject.stim),1);

    for k = 1:length(subject.stim)
        stimNames{k} = subject.stim(k).GetName();
    end

    stimIdx = find(strcmp(stimNames,'SART'));

    if isempty(stimIdx)
        fprintf('No SART stim found\n');
        continue
    end

    oldStim = subject.stim(stimIdx);

    NonTarget = copy(oldStim);
    Target    = copy(oldStim);
    Probe     = copy(oldStim);

    onsets = oldStim.GetData();
    onsets = onsets(:,1);

    T = readtable(logFile);

    validRows = ~cellfun(@isempty,T.trialType);
    T = T(validRows,:);

    if length(onsets) ~= height(T)
        fprintf('Length mismatch. Skipping.\n');
        continue
    end

    % create masks
    nEvents = height(T);

    isPractice = false(nEvents,1);
    isPractice(1:19) = true;

    isMain = ~isPractice;

    trialType = lower(string(T.trialType));

    isProbe = isMain & contains(trialType,'probe');
    isTarget = isMain & (trialType == "target");
    isNonTarget = isMain & contains(trialType,'non-target');

    % create stim objects
    NonTarget.SetName('SART_NonTarget');
    NonTarget.SetData([
        onsets(isNonTarget), ...
        0.25*ones(sum(isNonTarget),1), ...
        ones(sum(isNonTarget),1)]);

    Target.SetName('SART_Target');
    Target.SetData([
        onsets(isTarget), ...
        0.25*ones(sum(isTarget),1), ...
        ones(sum(isTarget),1)]);

    probeDuration = T.probe1_stopped(isProbe) - T.probe1_started(isProbe);
    Probe.SetName('SART_Probe');
    Probe.SetData([
        onsets(isProbe), ...
        probeDuration, ...
        ones(sum(isProbe),1)]);
    %5*ones(sum(isProbe),1), ...
    % remove old SART
    subject.stim(stimIdx) = [];

    subject.stim(end+1) = NonTarget;
    subject.stim(end+1) = Target;
    subject.stim(end+1) = Probe;

    S.subject_postprocessed = subject;

    saveName = fullfile(matDir,...
        sprintf('S%d_postprocessed_SART_fixedStim.mat',subjNum));

    save(saveName,'-struct','S');

    fprintf('Saved %s\n',saveName);

    % -------------------------
    % Export HbO/HbR CSVs
    % -------------------------
    
    S2 = load(saveName);
    subject = S2.subject_postprocessed;
    
    t = double(subject.t(:));
    
    chanSrcDet = subject.probeInfo.probes.index_c;
    chanLabels = arrayfun(@(k) ...
        sprintf('S%d-D%d', chanSrcDet(k,1), chanSrcDet(k,2)), ...
        1:size(chanSrcDet,1), ...
        'UniformOutput', false);
    
    [target, non_target, probe] = getStimCols(t, subject.stim);
    
    keep = (target | non_target | probe);

    if any(keep)
        first_idx = find(keep, 1, 'first');
        last_idx  = find(keep, 1, 'last');
    else
        warning('No SART events found for subject %d. Skipping.', subjNum);
        continue
    end

    for HbType = {'HbO','HbR'}
    
        X = double(subject.(HbType{1}));
        
        t2 = t(first_idx:last_idx);
        X2 = X(first_idx:last_idx, :);
        target2 = target(first_idx:last_idx);
        non_target2 = non_target(first_idx:last_idx);
        probe2 = probe(first_idx:last_idx);

        T = array2table(...
            [t2, X2, target2, non_target2, probe2], ...
            'VariableNames', ...
            [{'time'}, chanLabels(:)', ...
            {'SART_Target','SART_NonTarget','SART_Probe'}]);
    
        outFile = fullfile(...
            matDir, ...
            sprintf('S%d_SART_%s.csv', subjNum, HbType{1}));
    
        writetable(T, outFile);
    
    end
    
    fprintf('Exported HbO/HbR CSVs for subject %d\n', subjNum);
    
 end
    
    
    function [target, non_target, probe] = getStimCols(t, stimObj)
    
    target = zeros(size(t));
    non_target = zeros(size(t));
    probe = zeros(size(t));
    
    for j = 1:numel(stimObj)
    
        s = struct(stimObj(j));
    
        D = s.data;
        if iscell(D)
            D = cell2mat(D);
        end
    
        labs = lower(cellstr(s.dataLabels));
        onsetIdx = find(strcmp(labs,'onset'),1);
        durIdx   = find(strcmp(labs,'duration'),1);
    
        if isempty(onsetIdx) || isempty(durIdx)
            continue
        end
    
        onset = D(:,onsetIdx);
        dur   = D(:,durIdx);
    
        condName = char(s.name);
    
        for i = 1:numel(onset)
    
            idx = (t >= onset(i)) & (t < onset(i) + dur(i));
    
            if contains(condName,'SART_NonTarget')
                non_target(idx) = 1;
    
            elseif contains(condName,'SART_Probe')
                probe(idx) = 1;
    
            elseif contains(condName,'SART_Target')
                target(idx) = 1;
            end
    
        end
    
    end

    end
