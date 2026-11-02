% SYNTAX:
% tri = ba_read_tri(triFile)
%
%
% DESCRIPTION:
% Reads an ELM .tri trigger file (one row per trigger:
% timestamp ; sample index ; code) into a table.
%
%
% OUTPUTS:
% tri - table with columns Timestamp (string), Sample (double), Code (double),
%       in file order. Sample is the 1-based row of the SNIRF data, as used
%       by scripts/fNIRS/run_preprocessing.m.
function tri = ba_read_tri(triFile)

assert(isfile(triFile), 'TRI file not found: %s', triFile);
fid = fopen(triFile, 'r');
assert(fid >= 0, 'Could not open TRI file: %s', triFile);
cleaner = onCleanup(@() fclose(fid));
raw = textscan(fid, '%s %f %f', 'Delimiter', ';');

tri = table(string(raw{1}), round(raw{2}), round(raw{3}), ...
    'VariableNames', {'Timestamp', 'Sample', 'Code'});
tri = tri(~isnan(tri.Sample) & ~isnan(tri.Code), :);
assert(height(tri) > 0, 'TRI file has no rows: %s', triFile);
end
