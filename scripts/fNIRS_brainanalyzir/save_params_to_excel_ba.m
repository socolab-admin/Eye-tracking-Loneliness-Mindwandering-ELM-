% SYNTAX:
% save_params_to_excel_ba(params, outdir)
%
%
% DESCRIPTION:
% Saves every field of the Brain AnalyzIR params struct to
%   outdir/params_summary_BA.xlsx  (one row per parameter, grouped by step)
%   outdir/params_BA.mat           (the exact struct, reloadable)
% together with the MATLAB version, toolbox commit and run date, so the
% preprocessing used for any output folder can be reported later.
%
%
% INPUTS:
% params - Struct from create_params_ba().
% outdir - Output folder.
%
%
% NOTES:
%     - Nested fields are flattened (e.g. qc.motion.min_clean).
%     - Arrays are written as text, e.g. "[4 11 20 ...]" or "S02, S70".
function save_params_to_excel_ba(params, outdir)

if ~isfolder(outdir)
    mkdir(outdir);
end

rows = cell(0, 4);
rows = flattenStruct(params, '', rows);

% ---- Run information ----
rows(end+1,:) = {'run', 'run', 'date',           char(datetime('now'))};
rows(end+1,:) = {'run', 'run', 'matlab_version', version};
rows(end+1,:) = {'run', 'run', 'toolbox_commit', toolboxCommit(params.paths.toolbox)};

T = cell2table(rows, 'VariableNames', {'Step', 'Group', 'Parameter', 'Value'});

xlsxFile = fullfile(outdir, 'params_summary_BA.xlsx');
writetable(T, xlsxFile);
save(fullfile(outdir, 'params_BA.mat'), 'params');

fprintf('Params saved to:\n  %s\n  %s\n', xlsxFile, fullfile(outdir, 'params_BA.mat'));
end

function rows = flattenStruct(s, prefix, rows)
names = fieldnames(s);
for i = 1:numel(names)
    name = names{i};
    value = s.(name);
    if isempty(prefix)
        fullName = name;
    else
        fullName = [prefix '.' name];
    end
    if isstruct(value)
        rows = flattenStruct(value, fullName, rows);
    else
        parts = strsplit(fullName, '.');
        step = parts{1};
        if numel(parts) > 2
            group = strjoin(parts(1:end-1), '.');
        else
            group = step;
        end
        rows(end+1,:) = {step, group, fullName, valueToText(value)}; %#ok<AGROW>
    end
end
end

function txt = valueToText(value)
if isstring(value) || iscellstr(value)
    value = string(value);
    if isempty(value)
        txt = '';
    else
        txt = char(strjoin(value, ', '));
    end
elseif ischar(value)
    txt = value;
elseif islogical(value) || isnumeric(value)
    if isscalar(value)
        txt = num2str(value);
    elseif isempty(value)
        txt = '';
    else
        txt = ['[' num2str(value(:)') ']'];
    end
else
    txt = class(value);
end
end

function txt = toolboxCommit(toolboxDir)
txt = 'unknown';
[status, out] = system(sprintf('git -C "%s" log -1 --format="%%h %%ad"', toolboxDir));
if status == 0
    txt = strtrim(out);
end
end
