% ELM Brain AnalyzIR pipeline - main script
%
% Steps:
%   1. create params (edit create_params_ba.m or override below)
%   2. save params to Excel/.mat in the output folder (methods record)
%   3. preprocess every subject for video and SART
%   4. group QC tables and figures
%   5. video: pairwise AR-prewhitened ISC (dyad table for R)
%   6. SART: AR-IRLS GLM (first level) + mixed-effects group model
%
% Run from MATLAB:  run_main_ba
% or from a terminal: matlab -batch "run_main_ba"

clear; clc;

% Step 1: create params
params = create_params_ba();

% Step 1b (optional): override here instead of editing create_params_ba.m
% params.subjects.include = [];          % all subjects
% params.channels.exclude = ["S3-D7"];   % drop a long channel by label

addpath(genpath(params.paths.toolbox));
addpath(fileparts(mfilename('fullpath')));

% Step 2: save params log file used for methods clarity
save_params_to_excel_ba(params, params.paths.outdir);

% Step 3: preprocessing
manifest = ba_run_preprocessing(params);

% Step 4: QC report
ba_qc_report(params);

% Step 5: video ISC
if params.isc.run && ismember("video", string(params.tasks))
    ba_video_isc(params);
end

% Step 6: SART GLM
if params.glm.run && ismember("SART", string(params.tasks))
    ba_sart_glm(params);
end
