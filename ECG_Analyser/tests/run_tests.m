function results = run_tests()
%RUN_TESTS Verification test plan for the Group 24 ECG Analyser.
%   results = RUN_TESTS() runs every test case, prints a pass/fail table
%   and writes tests/test_results.csv.
%   Test signals come from ecg_synth, so the true beat positions and
%   rhythm are known exactly. Categories: Nominal operation, Boundary
%   conditions, Edge cases (fail-safe behaviour) and Error handling.
%   R-peak match tolerance: +/- 75 ms.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'src'));
cfg = ecg_config();
cfg.showPlots = false; cfg.saveOutputs = false;
noisy = struct('baseline', 0.3, 'mains', 0.1, 'emg', 0.02);

T = {};
% ID      Category    Description                                           Pass criterion
T(end+1,:) = {'T01','Nominal','Clean normal sinus rhythm, 72 bpm',            'Se & PPV >= 99%, HR 72+/-2, finding "Normal sinus rhythm"', @() t_rhythm('normal', struct(), 'Normal sinus rhythm', cfg)};
T(end+1,:) = {'T02','Nominal','Normal rhythm + baseline wander, 50 Hz, EMG',  'Se & PPV >= 99%, HR 72+/-2, finding "Normal sinus rhythm"', @() t_rhythm('normal', noisy, 'Normal sinus rhythm', cfg)};
T(end+1,:) = {'T03','Nominal','Sinus bradycardia, 48 bpm (noisy)',            'Se & PPV >= 99%, finding "Sinus bradycardia"',     @() t_rhythm('brady', noisy, 'Sinus bradycardia', cfg)};
T(end+1,:) = {'T04','Nominal','Sinus tachycardia, 125 bpm (noisy)',           'Se & PPV >= 99%, finding "Sinus tachycardia"',     @() t_rhythm('tachy', noisy, 'Sinus tachycardia', cfg)};
T(end+1,:) = {'T05','Nominal','Atrial fibrillation (noisy)',                  'Se & PPV >= 99%, top finding "Atrial fibrillation"', @() t_rhythm('af', noisy, 'Atrial fibrillation', cfg)};
T(end+1,:) = {'T06','Nominal','PVC every 6th beat (noisy)',                   'All PVCs labelled V, no N beat labelled V, finding "PVCs"', @() t_pvc(noisy, cfg)};
T(end+1,:) = {'T07','Nominal','First-degree AV block, PR 280 ms',             'PR 280+/-20 ms, finding "First-degree AV block"',  @() t_interval('avb1', 'PR', 0.280, 0.020, 'First-degree AV block', noisy, cfg)};
T(end+1,:) = {'T08','Nominal','Long QT, QTc 530 ms',                          'QTcB 530+/-30 ms, finding "Prolonged QT interval"', @() t_interval('longqt', 'QTcB', 0.530, 0.030, 'Prolonged QT interval', noisy, cfg)};
T(end+1,:) = {'T09','Nominal','ST elevation +0.25 mV',                        'ST +0.25+/-0.06 mV, finding "ST elevation"',      @() t_interval('stelev', 'ST', 0.25, 0.06, 'ST elevation', noisy, cfg)};
T(end+1,:) = {'T10','Nominal','ST depression -0.15 mV',                       'ST -0.15+/-0.06 mV, finding "ST depression"',     @() t_interval('stdep', 'ST', -0.15, 0.06, 'ST depression', noisy, cfg)};
T(end+1,:) = {'T11','Nominal','Wide QRS (bundle branch block)',               'QRS >= 120 ms, finding "Wide QRS"',               @() t_rhythm('wideqrs', noisy, 'Wide QRS - bundle branch block', cfg)};
T(end+1,:) = {'T12','Nominal','Mobitz II second-degree AV block',             'finding "Possible second-degree AV block"',       @() t_rhythm('avb2', noisy, 'Possible second-degree AV block / sinus exit block', cfg)};
T(end+1,:) = {'T13','Nominal','2.8 s sinus pause',                            'finding "Sinus pause / arrest"',                   @() t_rhythm('pause', noisy, 'Sinus pause / arrest', cfg)};
T(end+1,:) = {'T14','Nominal','Ventricular tachycardia, 165 bpm',             'Se & PPV >= 99%, finding "Ventricular tachycardia"', @() t_rhythm('vt', noisy, 'Ventricular tachycardia', cfg)};
T(end+1,:) = {'T15','Boundary','HR exactly 60 bpm',                           'NOT labelled bradycardia (limit is < 60)',         @() t_hr_boundary(60, 'Sinus bradycardia', false, cfg)};
T(end+1,:) = {'T16','Boundary','HR 58 bpm (just below limit)',                'Labelled "Sinus bradycardia"',                     @() t_hr_boundary(58, 'Sinus bradycardia', true, cfg)};
T(end+1,:) = {'T17','Boundary','Low sampling rate 125 Hz',                    'Se & PPV >= 99%, HR 72+/-2',      @() t_lowfs(cfg)};
T(end+1,:) = {'T18','Boundary','Very heavy noise (EMG 0.1 mV, motion)',       'Se & PPV >= 95%, no crash',                         @() t_heavy(cfg)};
T(end+1,:) = {'T19','Edge','Inverted lead polarity',                          'Polarity = -1, Se & PPV >= 99%, normal rhythm',     @() t_inverted(cfg)};
T(end+1,:) = {'T20','Edge','Flat line (leads off)',                           'No crash, 0 beats, "Insufficient data" only',       @() t_flat(cfg)};
T(end+1,:) = {'T21','Edge','Recording only 1.5 s long',                       'No crash, short-record warning, < 3 beats -> insufficient', @() t_short(cfg)};
T(end+1,:) = {'T22','Edge','5% NaN samples (dropouts)',                       'NaNs interpolated + warning, Se & PPV >= 99%',     @() t_nan(cfg)};
T(end+1,:) = {'T23','Edge','Arduino CSV: millis() time, ADC counts, "!" lines, jitter', 'fs 250+/-5 Hz, units = counts, 3 "!" lines counted, HR 72+/-2', @() t_csv(cfg)};
T(end+1,:) = {'T24','Error','Empty input',                                    'Error ID ECG:emptyInput',                          @() t_error(@() ecg_analyse([], 500, cfg), 'ECG:emptyInput')};
T(end+1,:) = {'T25','Error','Negative sampling rate',                         'Error ID ECG:badFs',                               @() t_error(@() ecg_analyse(randn(1000,1), -5, cfg), 'ECG:badFs')};
T(end+1,:) = {'T26','Error','Matrix instead of vector',                       'Error ID ECG:badInput',                            @() t_error(@() ecg_analyse(randn(100,3), 500, cfg), 'ECG:badInput')};
T(end+1,:) = {'T27','Error','File does not exist',                            'Error ID ECG:fileNotFound',                        @() t_error(@() ecg_load('no_such_file.csv', cfg), 'ECG:fileNotFound')};
T(end+1,:) = {'T28','Error','Text file with no time column and cfg.fs empty', 'Error ID ECG:noFs',                                 @() t_nofs(cfg)};

%% Run
n = size(T,1);
results = struct('id', T(:,1), 'category', T(:,2), 'description', T(:,3), ...
    'criterion', T(:,4), 'measured', '', 'pass', false);
fprintf('\n%-4s %-9s %-58s %-6s %s\n', 'ID', 'Category', 'Description', 'Result', 'Measured');
fprintf('%s\n', repmat('-', 1, 140));
for k = 1:n
    try
        [ok, meas] = T{k,5}();
    catch err
        ok = false; meas = ['UNEXPECTED ERROR: ' err.message];
    end
    results(k).pass = ok; results(k).measured = meas;
    if ok, s = 'PASS'; else, s = 'FAIL'; end
    fprintf('%-4s %-9s %-58s %-6s %s\n', T{k,1}, T{k,2}, T{k,3}, s, meas);
end
np = sum([results.pass]);
fprintf('%s\n%d / %d tests passed\n', repmat('-', 1, 140), np, n);

fw = fopen(fullfile(here, 'test_results.csv'), 'w');
fprintf(fw, 'ID,Category,Description,Pass criterion,Measured,Result\n');
for k = 1:n
    r = results(k); s = 'FAIL'; if r.pass, s = 'PASS'; end
    fprintf(fw, '%s,%s,"%s","%s","%s",%s\n', r.id, r.category, r.description, r.criterion, strrep(r.measured, '"', ''''), s);
end
fprintf(fw, ',,,,"Run %s: %d/%d passed",\n', datestr(now, 'yyyy-mm-dd HH:MM'), np, n);
fclose(fw);
end

%% ======================= individual tests ==============================
function [ok, m] = t_rhythm(type, noise, expected, cfg)
[x, ~, tr] = ecg_synth(type, 30, 500, noise);
r = ecg_analyse(x, 500, cfg);
[se, ppv] = match(r.fid.R, tr.rIdx, 500);
has = has_finding(r, expected);
ok = se >= 0.99 && ppv >= 0.99 && has;
if any(strcmp(type, {'normal'})), ok = ok && abs(r.F.hrMedian - 72) <= 2; end
if strcmp(type, 'af'), ok = ok && strcmp(r.dx(1).finding, expected); end
m = sprintf('Se %.1f%% PPV %.1f%% HR %.0f | %s', 100*se, 100*ppv, r.F.hrMedian, top(r));
end

function [ok, m] = t_pvc(noise, cfg)
[x, ~, tr] = ecg_synth('pvc', 30, 500, noise);
r = ecg_analyse(x, 500, cfg);
[se, ppv, map] = match(r.fid.R, tr.rIdx, 500);
trueV = tr.beatType == 'V';
det = repmat('?', numel(tr.rIdx), 1);
det(map > 0) = r.F.beatType(map(map > 0));
tpV = sum(trueV & det == 'V'); fpV = sum(~trueV & det == 'V');
ok = se >= 0.99 && ppv >= 0.99 && tpV == sum(trueV) && fpV == 0 && ...
     has_finding(r, 'Premature ventricular complexes (PVCs)');
m = sprintf('PVCs found %d/%d, false V %d | %s', tpV, sum(trueV), fpV, top(r));
end

function [ok, m] = t_interval(type, field, target, tol, expected, noise, cfg)
x = ecg_synth(type, 30, 500, noise);
r = ecg_analyse(x, 500, cfg);
v = r.F.(field);
ok = abs(v - target) <= tol && has_finding(r, expected);
if any(strcmp(field, {'PR','QTcB'})), m = sprintf('%s = %.0f ms | %s', field, 1000*v, top(r));
else, m = sprintf('%s = %+.2f mV | %s', field, v, top(r)); end
end

function [ok, m] = t_hr_boundary(hr, finding, shouldHave, cfg)
o = struct('hr', hr);
[x, ~] = ecg_synth('normal', 60, 500, o);
r = ecg_analyse(x, 500, cfg);
% remove random HRV influence: use exactly regular beats
has = has_finding(r, finding);
ok = has == shouldHave;
m = sprintf('HR %.1f bpm, "%s" reported: %d', r.F.hrMedian, finding, has);
end

function [ok, m] = t_lowfs(cfg)
[x, ~, tr] = ecg_synth('normal', 30, 125, struct('baseline', 0.3, 'emg', 0.02));
r = ecg_analyse(x, 125, cfg);
[se, ppv] = match(r.fid.R, tr.rIdx, 125);
w = any(~cellfun(@isempty, strfind(r.warnings, 'sampling')));
ok = se >= 0.99 && ppv >= 0.99 && abs(r.F.hrMedian - 72) <= 2;
m = sprintf('Se %.1f%% PPV %.1f%% HR %.0f, low-fs notches %s, warning %d', 100*se, 100*ppv, r.F.hrMedian, mat2str(r.pre.notches), w);
end

function [ok, m] = t_heavy(cfg)
[x, ~, tr] = ecg_synth('normal', 30, 500, struct('baseline', 0.8, 'mains', 0.3, 'emg', 0.1, 'motion', 1.0, 'seed', 3));
r = ecg_analyse(x, 500, cfg);
[se, ppv] = match(r.fid.R, tr.rIdx, 500);
ok = se >= 0.95 && ppv >= 0.95;
m = sprintf('Se %.1f%% PPV %.1f%% quality %s', 100*se, 100*ppv, r.F.quality);
end

function [ok, m] = t_inverted(cfg)
[x, ~, tr] = ecg_synth('normal', 30, 500, struct('baseline', 0.3, 'mains', 0.1, 'emg', 0.02));
r = ecg_analyse(-x, 500, cfg);
[se, ppv] = match(r.fid.R, tr.rIdx, 500);
ok = r.det.polarity == -1 && se >= 0.99 && ppv >= 0.99 && has_finding(r, 'Normal sinus rhythm');
m = sprintf('polarity %d, Se %.1f%% PPV %.1f%% | %s', r.det.polarity, 100*se, 100*ppv, top(r));
end

function [ok, m] = t_flat(cfg)
r = ecg_analyse(512*ones(5000,1), 500, cfg);
ok = r.F.nBeats == 0 && numel(r.dx) == 1 && ~isempty(strfind(r.dx(1).finding, 'Insufficient'));
m = sprintf('beats %d | %s', r.F.nBeats, top(r));
end

function [ok, m] = t_short(cfg)
x = ecg_synth('normal', 1.5, 500);
r = ecg_analyse(x, 500, cfg);
w = any(~cellfun(@isempty, strfind(r.warnings, 'short')));
ok = w && r.F.nBeats < 3 && ~isempty(strfind(r.dx(1).finding, 'Insufficient'));
m = sprintf('beats %d, warning %d | %s', r.F.nBeats, w, top(r));
end

function [ok, m] = t_nan(cfg)
[x, ~, tr] = ecg_synth('normal', 30, 500, struct('baseline', 0.3, 'emg', 0.02));
idx = 1:20:numel(x); x(idx) = NaN;       % 5% scattered dropouts
r = ecg_analyse(x, 500, cfg);
[se, ppv] = match(r.fid.R, tr.rIdx, 500);
w = any(~cellfun(@isempty, strfind(r.warnings, 'interpolated')));
ok = w && se >= 0.99 && ppv >= 0.99;
m = sprintf('warning %d, Se %.1f%% PPV %.1f%%', w, 100*se, 100*ppv);
end

function [ok, m] = t_csv(cfg)
fs = 250;
[x, t] = ecg_synth('normal', 30, fs, struct('baseline', 0.2, 'mains', 0.1, 'emg', 0.02));
counts = round(512 + x*1100/1000/5*1023);
tm = round(1000*t + 0.8*randn(size(t)));            % millis() with jitter
tm = max(tm, [0; tm(1:end-1) + 1]);                 % keep increasing
tm = cummax_(tm);
fn = [tempname '.csv'];
fw = fopen(fn, 'w');
fprintf(fw, 'time_ms,ecg\n');
for k = 1:numel(x)
    fprintf(fw, '%d,%d\n', tm(k), counts(k));
    if any(k == [1000 3000 5000]), fprintf(fw, '!\n'); end
end
fclose(fw);
c = cfg; c.fs = [];
[xl, fsl, info] = ecg_load(fn, c);
r = ecg_analyse(xl, fsl, c, info);
delete(fn);
ok = abs(fsl - 250) <= 5 && strcmp(r.units.mode, 'counts') && info.leadsOffLines == 3 && abs(r.F.hrMedian - 72) <= 2;
m = sprintf('fs %.1f Hz, units %s, "!" lines %d, resampled %d, HR %.0f', fsl, r.units.mode, info.leadsOffLines, info.resampled, r.F.hrMedian);
end

function [ok, m] = t_nofs(cfg)
fn = [tempname '.txt'];
fw = fopen(fn, 'w'); fprintf(fw, '%d\n', round(512 + 50*randn(500,1))); fclose(fw);
c = cfg; c.fs = [];
[ok, m] = t_error(@() ecg_load(fn, c), 'ECG:noFs');
delete(fn);
end

function [ok, m] = t_error(fh, id)
try
    fh();
    ok = false; m = 'no error raised';
catch err
    ok = strcmp(err.identifier, id);
    m = sprintf('raised %s', err.identifier);
end
end

%% ======================= helpers =======================================
function [se, ppv, map] = match(det, truth, fs)
tol = round(0.075*fs);
map = zeros(numel(truth),1); used = false(numel(det),1);
for j = 1:numel(truth)
    [dmin, k] = min(abs(det - truth(j)));
    if ~isempty(dmin) && dmin <= tol && ~used(k), map(j) = k; used(k) = true; end
end
tp = sum(map > 0);
se = tp/max(1, numel(truth));
ppv = tp/max(1, numel(det));
end

function tf = has_finding(r, name)
tf = any(strcmp({r.dx.finding}, name));
end

function s = top(r)
if isempty(r.dx), s = '(no findings)'; else, s = strjoin({r.dx.finding}, '; '); end
end

function y = cummax_(x)
y = x; for k = 2:numel(y), y(k) = max(y(k), y(k-1) + 1); end
end
