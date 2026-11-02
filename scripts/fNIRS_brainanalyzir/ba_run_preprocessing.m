% SYNTAX:
% manifest = ba_run_preprocessing(params)
%
%
% DESCRIPTION:
% Batch runner: finds every G*/S* subject folder in params.paths.rawdir,
% runs ba_preprocess_subject for each task in params.tasks, and records
% complete / skipped / failed per subject and task. A failing subject is
% logged and the batch continues (the Homer3 runner stopped on error()).
%
%
% OUTPUTS (written to params.paths.outdir):
%     processing_manifest.csv - one row per subject x task (status, duration,
%                               events, channels kept, motion summary)
%     channel_qc_all.csv      - one row per subject x task x channel
% manifest - the manifest table.
function manifest = ba_run_preprocessing(params)

subjects = ba_find_subjects(params);
fprintf('Found %d subject folder(s) to run.\n', numel(subjects));

manifest = table();
chanAll = table();

for i = 1:numel(subjects)
    subj = subjects(i);
    for task = string(params.tasks)
        fprintf('\n==== %s / %s / %s ====\n', subj.Group, subj.ID, task);
        try
            if strlength(subj.Tri) == 0
                error('BA:NoTri', 'No .tri file.');
            end
            [summary, chanTable] = ba_preprocess_subject(subj, task, params);
            chanAll = [chanAll; chanTable]; %#ok<AGROW>
        catch ME
            warning('BA:SubjectFailed', '%s %s failed: %s', subj.ID, task, ME.message);
            summary = failedRow(subj, task, ME.message);
        end
        manifest = [manifest; summary]; %#ok<AGROW>
    end
end

if ~isfolder(params.paths.outdir), mkdir(params.paths.outdir); end
writetable(manifest, fullfile(params.paths.outdir, 'processing_manifest.csv'));
if ~isempty(chanAll)
    writetable(chanAll, fullfile(params.paths.outdir, 'channel_qc_all.csv'));
end
fprintf('\nManifest: %s\n', fullfile(params.paths.outdir, 'processing_manifest.csv'));
disp(groupsummary(manifest, {'Task', 'Status'}));
end

function row = failedRow(subj, task, msg)
row = table(string(subj.ID), string(subj.Group), string(task), "failed", string(msg), ...
    NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, false, NaN, NaN, NaN, NaN, ...
    'VariableNames', {'Subject', 'Group', 'Task', 'Status', 'Message', ...
    'DurationSec', 'FsNative', 'FsAnalysis', 'NEvents', 'NLong', 'NLongKept', ...
    'NShortUsed', 'PropBadLong', 'BadSubject', 'MeanMotionCleanBefore', ...
    'MeanMotionCleanAfter', 'NLongLowMotion', 'NUnmatchedVideoPairs'});
end
