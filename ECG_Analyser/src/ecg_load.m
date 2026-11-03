function [x, fs, info] = ecg_load(filename, cfg)
%ECG_LOAD Read an ECG recording from .csv / .txt / .dat / .mat.
%   [x, fs, info] = ECG_LOAD(filename, cfg)
%
%   Text files (e.g. Arduino Serial Monitor / PuTTY logs from the AD8232):
%     - header lines and non-numeric lines are skipped; '!' lines (the
%       SparkFun sketch prints '!' when a lead is off) are counted
%     - 1 column  -> ECG samples, fs taken from cfg.fs
%     - 2+ columns -> if column 1 is increasing it is treated as time
%       (seconds, ms from millis() or us from micros() - detected
%       automatically) and fs is calculated from it
%     - irregular Arduino timing is corrected by resampling onto a
%       uniform grid
%   .mat files (MATLAB Signal Simulator / PhysioNet exports): the longest
%   numeric vector is used; variables named fs/Fs/fsamp/Fsamp are read.

if nargin < 2 || isempty(cfg), cfg = ecg_config(); end
if ~exist(filename, 'file')
    error('ECG:fileNotFound', 'File not found: %s', filename);
end
[~, name, ext] = fileparts(filename);
info = struct('source', filename, 'name', name, 'leadsOffLines', 0, ...
              'timeColumn', false, 'timeUnit', '', 'resampled', false, ...
              'droppedSamples', 0, 'unitsHint', '', 'notes', {{}});
fs = cfg.fs;

switch lower(ext)
    case '.mat'
        [x, fsFile] = load_mat(filename, cfg);
        if ~isempty(fsFile), fs = fsFile; end
        t = [];
    otherwise
        [M, header, nBad] = read_numeric_text(filename);
        info.leadsOffLines = nBad;
        if isempty(M)
            error('ECG:emptyInput', 'No numeric data found in %s.', filename);
        end
        [x, t, info] = pick_columns(M, header, cfg, info);
end

% remember if raw samples were ADC integers (resampling makes them fractional)
xr = x(isfinite(x));
if ~isempty(xr) && all(abs(xr - round(xr)) < 1e-9) && min(xr) >= 0 && max(xr) <= 2^cfg.adcBits - 1
    info.unitsHint = 'counts';
end

%% Time column -> fs
if ~isempty(t)
    dt = diff(t);
    bad = dt <= 0;
    if any(bad)                     % millis() reset / duplicated stamps
        keep = [true; ~bad];
        info.droppedSamples = sum(~keep);
        t = t(keep); x = x(keep); dt = diff(t);
        info.notes{end+1} = sprintf('%d samples with non-increasing time removed.', info.droppedSamples);
    end
    mdt = median(dt);
    if mdt < 0.5
        scale = 1;     info.timeUnit = 's';
    elseif mdt < 200
        scale = 1e-3;  info.timeUnit = 'ms';
    else
        scale = 1e-6;  info.timeUnit = 'us';
    end
    t = (t - t(1))*scale;
    dt = diff(t);
    fsT = 1/median(dt);
    if isempty(fs), fs = fsT; end
    jitter = std(dt)/mean(dt);
    if jitter > cfg.maxJitter
        tu = (0:1/fs:t(end))';
        x = interp1(t, x, tu, 'linear');
        info.resampled = true;
        info.notes{end+1} = sprintf('Irregular sampling (jitter %.1f%%) - resampled to %.1f Hz.', 100*jitter, fs);
    end
end
if isempty(fs)
    error('ECG:noFs', ['Sampling rate unknown for %s. Set cfg.fs (e.g. cfg.fs = 250) ' ...
        'or include a time column.'], filename);
end
if info.leadsOffLines > 0
    info.notes{end+1} = sprintf('%d non-numeric lines skipped (e.g. "!" leads-off markers).', info.leadsOffLines);
end
x = x(:);
end

%% ---------------------------------------------------------------------
function [M, header, nBad] = read_numeric_text(filename)
txt = fileread(filename);
lines = regexp(txt, '\r\n|\n|\r', 'split');
lines = lines(~cellfun(@isempty, regexprep(lines, '\s', '')));
numPat = '^\s*[-+]?(\d|\.\d)[\deE\.\+\-,;\s]*$';
isNum = ~cellfun(@isempty, regexp(lines, numPat, 'once'));
header = '';
first = find(isNum, 1);
if isempty(first), M = []; nBad = numel(lines); return; end
if first > 1, header = lines{first-1}; end
nBad = sum(~isNum(first:end));
dl = regexprep(lines(isNum), '[,;\t]', ' ');
cnt = cellfun(@(s) numel(sscanf(s, '%f')), dl);
ncol = mode(cnt);
good = cnt == ncol;
nBad = nBad + sum(~good);                 % partial lines from serial
v = sscanf(strjoin(dl(good), ' '), '%f');
M = reshape(v, ncol, [])';
end

function [x, t, info] = pick_columns(M, header, cfg, info)
ncol = size(M,2);
names = {};
if ~isempty(header)
    names = strtrim(regexp(lower(header), '[,;\t]', 'split'));
end
t = [];
ecgCol = [];
if ncol >= 2 && all(diff(M(:,1)) >= 0) && numel(unique(M(:,1))) > 0.9*size(M,1)
    t = M(:,1); info.timeColumn = true;
end
if ~isempty(cfg.column)
    ecgCol = cfg.column;
elseif numel(names) == ncol
    hit = find(~cellfun(@isempty, regexp(names, 'ecg|signal|value|lead|voltage|mv', 'once')), 1);
    if ~isempty(hit), ecgCol = hit; end
end
if isempty(ecgCol)
    if info.timeColumn, ecgCol = 2; else, ecgCol = 1; end
end
x = M(:, ecgCol);
end

function [x, fs] = load_mat(filename, cfg)
S = load(filename);
fs = [];
fn = fieldnames(S);
for k = 1:numel(fn)
    if any(strcmpi(fn{k}, {'fs','fsamp','samplingrate','sample_rate'})) && isscalar(S.(fn{k}))
        fs = double(S.(fn{k}));
    end
end
best = []; bestLen = 0;
for k = 1:numel(fn)
    v = S.(fn{k});
    if isstruct(v)                         % e.g. struct with .ecg, .fs fields
        sf = fieldnames(v);
        for j = 1:numel(sf)
            vv = v.(sf{j});
            if any(strcmpi(sf{j}, {'fs','fsamp'})) && isscalar(vv), fs = double(vv); end
            if isnumeric(vv) && min(size(vv)) == 1 && numel(vv) > bestLen
                best = vv; bestLen = numel(vv);
            end
        end
    elseif isnumeric(v) && numel(v) > bestLen
        if min(size(v)) == 1
            best = v; bestLen = numel(v);
        elseif size(v,2) <= 4                % [t ecg] style matrix
            if all(diff(v(:,1)) > 0) && size(v,2) >= 2
                best = v(:,2);
                if isempty(fs), fs = 1/median(diff(v(:,1))); end
            else
                c = cfg.column; if isempty(c), c = 1; end
                best = v(:,c);
            end
            bestLen = size(v,1);
        end
    end
end
if isempty(best)
    error('ECG:emptyInput', 'No numeric ECG vector found in %s.', filename);
end
x = double(best(:));
end
