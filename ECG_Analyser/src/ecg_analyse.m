function res = ecg_analyse(x, fs, cfg, meta)
%ECG_ANALYSE Complete ECG analysis pipeline (the core of the program).
%   res = ECG_ANALYSE(x, fs)            uses default settings
%   res = ECG_ANALYSE(x, fs, cfg)       custom settings (see ecg_config)
%   res = ECG_ANALYSE(x, fs, cfg, meta) meta = info struct from ecg_load
%
%   Pipeline: validate -> unit conversion -> pre-process (filters) ->
%   R-peak detection -> P/QRS/T delineation -> features -> differentials.
%
%   Errors (identifiers) for invalid input:
%     ECG:emptyInput  x empty / non-numeric / all NaN
%     ECG:badInput    x is not a vector
%     ECG:badFs       fs missing, non-positive or < 50 Hz

if nargin < 3 || isempty(cfg), cfg = ecg_config(); end
if nargin < 4 || isempty(meta), meta = struct('source', 'workspace', 'name', 'workspace', 'notes', {{}}); end
tic0 = tic;
res.warnings = {};
if isfield(meta, 'notes'), res.warnings = meta.notes(:)'; end

%% 1. Validate input
if isempty(x) || ~isnumeric(x)
    error('ECG:emptyInput', 'ECG input is empty or not numeric.');
end
if ~isvector(x)
    error('ECG:badInput', 'ECG input must be a vector (got %dx%d).', size(x,1), size(x,2));
end
if isempty(fs) || ~isscalar(fs) || ~isnumeric(fs) || ~isfinite(fs) || fs <= 0
    error('ECG:badFs', 'Sampling rate must be a positive number of Hz.');
end
if fs < 50
    error('ECG:badFs', 'Sampling rate %.1f Hz is too low for ECG (need >= 100 Hz, minimum 50 Hz).', fs);
end
if fs < 100
    res.warnings{end+1} = sprintf('Low sampling rate (%.0f Hz): QRS timing accuracy is reduced.', fs);
end
x = double(x(:));
bad = ~isfinite(x);
if all(bad)
    error('ECG:emptyInput', 'ECG input contains no finite samples.');
end
if any(bad)
    k = find(~bad);
    x(bad) = interp1(k, x(k), find(bad), 'linear', NaN);
    x(isnan(x) & (1:numel(x))' < k(1))  = x(k(1));
    x(isnan(x) & (1:numel(x))' > k(end)) = x(k(end));
    res.warnings{end+1} = sprintf('%d missing/invalid samples (%.1f%%) interpolated.', sum(bad), 100*mean(bad));
end
if numel(x)/fs < 5
    res.warnings{end+1} = sprintf('Recording is short (%.1f s) - at least 10 s is recommended.', numel(x)/fs);
end

%% 2. Units
hint = ''; if isfield(meta, 'unitsHint'), hint = meta.unitsHint; end
[xmv, units] = ecg_units(x, cfg, hint);
if units.auto
    res.warnings{end+1} = ['Units assumed: ' units.description '.'];
end
% flat / saturated segments (leads off)
flatRun = round(0.2*fs);
dz = [false; diff(x) == 0];
runs = conv(double(dz), ones(flatRun,1), 'same') >= flatRun - 1;
res.flatFraction = mean(runs);
if res.flatFraction > 0.02
    res.warnings{end+1} = sprintf('%.0f%% of the record is flat/saturated - possible leads-off or clipping.', 100*res.flatFraction);
end

%% 3. Pre-processing
pre = ecg_preprocess(xmv, fs, cfg);

%% 4. R-peak detection
[rIdx, det] = ecg_detect_r(pre.y, fs, cfg);
if ~isempty(det.message), res.warnings{end+1} = det.message; end
ys = det.polarity*pre.y;

%% 5. Delineation, features, differentials
fid = ecg_delineate(ys, fs, rIdx, cfg);
F   = ecg_features(ys, fs, fid, cfg, units);
[dx, rhythm] = ecg_diagnose(F, cfg);

%% Assemble result
res.meta = meta;
res.cfg  = cfg;
res.fs   = fs;
res.t    = (0:numel(x)-1)'/fs;
res.raw  = xmv - median(xmv);
res.units = units;
res.pre  = pre;
res.ecg  = ys;
res.det  = det;
res.fid  = fid;
res.F    = F;
res.dx   = dx;
res.rhythm = rhythm;
res.analysedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
res.runTime = toc(tic0);
end
