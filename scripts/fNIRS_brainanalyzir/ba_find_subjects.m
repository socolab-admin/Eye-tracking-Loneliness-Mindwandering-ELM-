% SYNTAX:
% subjects = ba_find_subjects(params)
%
%
% DESCRIPTION:
% Lists subject folders rawdir/G*/S*/ and their input files.
% Folder names look like G01_2025-02-26 / S02_2025-02-26_002; the subject ID
% is the part before the first "_" (S02). The SART log is matched as
% logdir/<N>_sart*.csv with N = subject number (S02 -> 2).
%
%
% OUTPUTS:
% subjects - struct array: ID, Group, Folder, Snirf, Tri, Probe, Log
%            (missing files are empty strings).
function subjects = ba_find_subjects(params)

subjects = struct('ID', {}, 'Group', {}, 'Folder', {}, 'Snirf', {}, ...
    'Tri', {}, 'Probe', {}, 'Log', {});

groupDirs = dir(fullfile(params.paths.rawdir, [params.prefix.group '*']));
groupDirs = groupDirs([groupDirs.isdir]);

for g = 1:numel(groupDirs)
    groupID = string(strtok(groupDirs(g).name, '_'));
    subjDirs = dir(fullfile(groupDirs(g).folder, groupDirs(g).name, [params.prefix.subject '*']));
    subjDirs = subjDirs([subjDirs.isdir]);
    for s = 1:numel(subjDirs)
        name = subjDirs(s).name;
        if startsWith(name, params.subjects.skip_folder_pattern)
            continue
        end
        id = string(strtok(name, '_'));
        if ~isempty(params.subjects.include) && ~ismember(id, string(params.subjects.include))
            continue
        end
        if ismember(id, string(params.subjects.exclude))
            fprintf('Excluded by params: %s\n', id);
            continue
        end
        folder = fullfile(subjDirs(s).folder, name);
        subj.ID = id;
        subj.Group = groupID;
        subj.Folder = string(folder);
        subj.Snirf = firstFile(folder, '*.snirf');
        subj.Tri = firstFile(folder, '*.tri');
        subj.Probe = firstFile(folder, '*probeInfo*.mat');
        subj.Log = firstFile(params.paths.logdir, sprintf('%d_sart*.csv', ...
            str2double(extractAfter(id, params.prefix.subject))));
        if strlength(subj.Snirf) == 0 || strlength(subj.Probe) == 0
            warning('BA:MissingInput', '%s: missing .snirf or probeInfo; skipped.', id);
            continue
        end
        subjects(end+1) = subj; %#ok<AGROW>
    end
end
end

function f = firstFile(folder, pattern)
d = dir(fullfile(folder, pattern));
d = d(~startsWith({d.name}, '._'));
if isempty(d)
    f = "";
else
    f = string(fullfile(d(1).folder, d(1).name));
end
end
