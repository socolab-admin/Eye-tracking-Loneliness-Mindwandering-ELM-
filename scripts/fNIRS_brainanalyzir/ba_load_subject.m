% SYNTAX:
% [raw, channels] = ba_load_subject(snirfFile, probeFile, params)
%
%
% DESCRIPTION:
% Loads one SNIRF recording with Brain AnalyzIR and builds the channel table
% from probeInfo.probes.index_c (same channel order and S-D labels as the
% Homer3 outputs, e.g. "S1-D1").
%
%
% OUTPUTS:
% raw      - nirs.core.Data, raw intensity, native sampling rate, original
%            SNIRF stimulus marks removed (events are rebuilt from the .tri).
% channels - table, one row per index_c row:
%            Index, Label, Source, Detector, IsShort, ShortUsed, Excluded, Cols
%            (Cols = the two wavelength columns of raw.data).
%
% NOTES:
%     - Short channels come from params.channels.short_index; their labels
%       are printed so they can be checked against the montage (detectors
%       D15-D22 in ELM).
%     - params.channels.exclude removes long channels by S-D label.
%     - params.channels.short_drop removes short channels from the regressors.
function [raw, channels] = ba_load_subject(snirfFile, probeFile, params)

raw = nirs.io.loadSNIRF(snirfFile);
assert(numel(raw) == 1, 'Expected one recording in %s.', snirfFile);
raw.stimulus = Dictionary();   % rebuild events from the .tri file

P = load(probeFile);
assert(isfield(P, 'probeInfo'), 'probeInfo missing in %s', probeFile);
indexC = double(P.probeInfo.probes.index_c);
nCh = size(indexC, 1);

Label = "S" + string(indexC(:,1)) + "-D" + string(indexC(:,2));
IsShort = false(nCh, 1);
IsShort(params.channels.short_index) = true;
ShortUsed = IsShort & ~ismember(Label, string(params.channels.short_drop));
Excluded = ismember(Label, string(params.channels.exclude));

unknown = setdiff(string([params.channels.exclude, params.channels.short_drop]), Label);
if ~isempty(unknown)
    warning('BA:UnknownLabel', 'Channel label(s) not in probeInfo: %s', strjoin(unknown, ', '));
end

Cols = cell(nCh, 1);
link = raw.probe.link;
for c = 1:nCh
    cols = find(link.source == indexC(c,1) & link.detector == indexC(c,2));
    assert(numel(cols) == 2, '%s: expected 2 wavelength columns, found %d.', ...
        Label(c), numel(cols));
    Cols{c} = cols(:)';
end

channels = table((1:nCh)', Label, indexC(:,1), indexC(:,2), IsShort, ...
    ShortUsed, Excluded, Cols, 'VariableNames', {'Index', 'Label', ...
    'Source', 'Detector', 'IsShort', 'ShortUsed', 'Excluded', 'Cols'});

% ---- Report short channels (check against the montage) ----
fprintf('Short channels (index_c rows %s): %s\n', ...
    mat2str(params.channels.short_index), strjoin(Label(IsShort), ', '));
if any(indexC(IsShort, 2) < 15)
    warning('BA:ShortCheck', ['A short_index row is not on detectors D15-D22. ' ...
        'Check params.channels.short_index.']);
end
end
