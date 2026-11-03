%% ECG_Analyser.m - Single-lead ECG analysis program
%  EE22005 Engineering Practice & Design - Project Week 1
%  "The Puzzling Physiology" - Group 24 (afb48, fjc48, owas20, aedg20, lhs53, ke417)
%
%  Removes noise, detects P-QRS-T features, measures rate / intervals /
%  HRV, suggests a list of differential diagnoses and displays everything
%  on a one-page dashboard.  Works with:
%    * SparkFun AD8232 + Arduino recordings saved as .csv/.txt
%      (columns: [time_ms, value] or just [value])
%    * MATLAB Signal Simulator / PhysioNet exports (.mat or .csv)
%    * Built-in synthetic ECGs (for testing without hardware)
%  No toolboxes are required (filters and peak detection are hand-written).
%
%  HOW TO USE: edit the USER SETTINGS block, then press Run (F5).
%  Run tests/run_tests.m to execute the verification test plan.
%
%  Educational use only - NOT a medical device.

clear; close all; clc;
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'src'));
cfg = ecg_config();

%% ===================== USER SETTINGS ===================================
% source options:
%   'capture'             - record live from the Nano ESP32 + AD8232
%                           (Firmware/ECG_NanoESP32), save CSV, analyse
%   'select'              - choose a file with a dialog box
%   'C:\path\to\ecg.csv'  - a specific file
%   'synthetic:normal'    - built-in signal; also brady, tachy, af, pvc,
%                           avb1, avb2, longqt, stelev, stdep, wideqrs,
%                           pause, vt
%   'demo'                - batch-analyse every synthetic rhythm
%   a folder path         - batch-analyse every recording in the folder
source = 'capture';

cfg.fs        = [];        % Hz - REQUIRED if your file has no time column
                           %      (e.g. 250 if the Arduino sketch used delay(4))
cfg.units     = 'capture';    % 'auto' | 'mV' | 'V' | 'V_adc' | 'counts'
cfg.mainsFreq = 50;        % UK mains
cfg.sex       = 'unknown'; % 'male' | 'female' - sets the QTc limit
cfg.displaySeconds = 10;   % length of the annotated strip
cfg.saveOutputs = true;    % write report, beat table and PNG
cfg.outputDir   = fullfile(here, 'ECG_outputs');

% live capture (source = 'capture')
cfg.capturePort    = '';   % '' = auto-detect, or e.g. 'COM5' (Arduino IDE > Tools > Port)
cfg.captureSeconds = 30;   % recording length
cfg.captureDir     = fullfile(here, 'recordings');
%% =======================================================================

if strcmpi(source, 'capture')
    source = ecg_capture(cfg.capturePort, cfg.captureSeconds, cfg.captureDir);
end

if strcmpi(source, 'select')
    [f, p] = uigetfile({'*.csv;*.txt;*.dat;*.mat', 'ECG recordings'}, 'Select an ECG recording');
    if isequal(f, 0), disp('No file selected.'); return; end
    source = fullfile(p, f);
end

if strcmpi(source, 'demo')
    types = {'normal','brady','tachy','af','pvc','avb1','avb2','longqt', ...
             'stelev','stdep','wideqrs','pause','vt'};
    cfg.showPlots = false;            % 13 figures - save them instead
    ecg_batch(strcat('synthetic:', types), cfg);
    fprintf('Dashboards saved in %s\n', cfg.outputDir);
    return
end
if exist(source, 'dir')
    cfg.showPlots = false;
    ecg_batch(source, cfg);
    return
end

%% Single recording
res = ecg_run_source(source, cfg);

[featLines, dxLines] = ecg_summary_text(res);
fprintf('\n===== ECG ANALYSIS =====\n');
fprintf('%s\n', featLines{:});
fprintf('\n----- Differentials / findings (not a medical diagnosis) -----\n');
fprintf('%s\n', dxLines{:});
if ~isempty(res.warnings)
    fprintf('\n----- Warnings -----\n');
    fprintf('  - %s\n', res.warnings{:});
end

fig = ecg_plot(res, cfg);
if cfg.saveOutputs
    files = ecg_report(res, cfg, fig);
    fprintf('\nSaved: %s\n       %s\n', files.report, files.beats);
    if isfield(files, 'figure'), fprintf('       %s\n', files.figure); end
end
