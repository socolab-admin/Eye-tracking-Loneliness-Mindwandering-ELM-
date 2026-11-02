% SYNTAX:
% [SubjStats, GroupStats] = ba_sart_glm(params)
%
%
% DESCRIPTION:
% SART GLM with Brain AnalyzIR.
%
% First level (per subject): nirs.modules.GLM, type AR-IRLS (Barker et al.,
% 2013), canonical HRF, short-separation regressors added inside the GLM
% (AddShortSepRegressors = true; only the good short channels flagged in
% ba_preprocess_subject). Bad long channels are removed before fitting.
%
% Regressors (params.glm.model):
%   "events"   - NonTarget, TargetCorrect, TargetError, ProbeMW, ProbeOnTask
%                (Target/NonTarget 0.25 s; probes = probe screen duration)
%   "preprobe" - the same plus PreProbeMW / PreProbeOnTask windows
%                (params.sart.preprobe_window_sec before each probe)
% Every event type has its own regressor; differences are tested as
% contrasts (e.g. TargetError-TargetCorrect), so the unequal number of
% targets and non-targets only changes how precise each beta is.
%
% Group level: nirs.modules.MixedEffects, formula params.glm.group_formula
% (default beta ~ -1 + cond + (1|subject)), then params.glm.contrasts.
%
%
% OUTPUTS (params.paths.outdir/glm_<model>/):
%     subject_betas.csv    - first-level betas/t per subject, channel, cond
%     group_conditions.csv - group beta/t/p/q per channel x condition
%     group_contrasts.csv  - group contrasts per channel
%     glm_results.mat      - SubjStats, GroupStats
%
% NOTES:
%     - A condition missing for a subject (e.g. no commission errors or no
%       mind-wandering reports) is simply absent from that subject's model.
%     - Commission errors and mind-wandering probes are rare per subject;
%       the group model carries most of the information for those contrasts.
function [SubjStats, GroupStats] = ba_sart_glm(params)

model = string(params.glm.model);
outDir = fullfile(params.paths.outdir, "glm_" + model);
if ~isfolder(outDir), mkdir(outDir); end

M = readtable(fullfile(params.paths.outdir, 'processing_manifest.csv'), 'TextType', 'string');
M = M(M.Task == "SART" & M.Status == "complete", :);
if params.glm.skip_bad_subjects
    M = M(~M.BadSubject, :);
end
assert(height(M) > 0, 'No SART subjects to model.');

conds = ["NonTarget", "TargetCorrect", "TargetError", "ProbeMW", "ProbeOnTask"];
if model == "preprobe"
    conds = [conds, "PreProbeMW", "PreProbeOnTask"];
end

% ---- Load, drop bad channels, keep model conditions ----
data = nirs.core.Data.empty;
for i = 1:height(M)
    f = fullfile(params.paths.outdir, 'SART', M.Group(i), M.Subject(i), ...
        sprintf('%s_SART_BA.mat', M.Subject(i)));
    S = load(f, 'hb', 'chanTable', 'channels');
    hb = S.hb;
    keepCh = S.chanTable.KeepForAnalysis | S.chanTable.UsedAsShortRegressor;
    link = hb.probe.link;
    keepRows = false(height(link), 1);
    for c = find(keepCh)'
        keepRows = keepRows | (link.source == S.channels.Source(c) & link.detector == S.channels.Detector(c));
    end
    hb.data = hb.data(:, keepRows);
    hb.probe.link = link(keepRows, :);

    stim = Dictionary();
    for k = conds
        if any(strcmp(hb.stimulus.keys, char(k)))
            stim(char(k)) = hb.stimulus(char(k));
        end
    end
    hb.stimulus = stim;
    data(end+1) = hb; %#ok<AGROW>
end

% ---- First level ----
job = nirs.modules.GLM();
job.type = params.glm.type;
job.AddShortSepRegressors = params.shortsep.sart.in_glm;
SubjStats = job.run(data);

subjTable = table();
for i = 1:numel(SubjStats)
    t = SubjStats(i).table();
    t.subject = repmat(string(SubjStats(i).demographics('subject')), height(t), 1);
    subjTable = [subjTable; t]; %#ok<AGROW>
end
writetable(subjTable, fullfile(outDir, 'subject_betas.csv'));

% ---- Group level ----
GroupStats = [];
if numel(SubjStats) < 2
    warning('BA:GLMGroup', 'Group model needs at least 2 subjects.');
else
    job = nirs.modules.MixedEffects();
    job.formula = params.glm.group_formula;
    GroupStats = job.run(SubjStats);
    writetable(GroupStats.table(), fullfile(outDir, 'group_conditions.csv'));

    contrasts = string(params.glm.contrasts);
    if model == "preprobe"
        contrasts = [contrasts, string(params.glm.preprobe_contrasts)];
    end
    conTable = table();
    for k = contrasts
        try
            ct = GroupStats.ttest(char(k));
            conTable = [conTable; ct.table()]; %#ok<AGROW>
        catch ME
            warning('BA:Contrast', 'Contrast %s skipped: %s', k, ME.message);
        end
    end
    if ~isempty(conTable)
        writetable(conTable, fullfile(outDir, 'group_contrasts.csv'));
    end
end

save(fullfile(outDir, 'glm_results.mat'), 'SubjStats', 'GroupStats', 'params', '-v7.3');
fprintf('GLM (%s) results written to %s\n', model, outDir);
end
