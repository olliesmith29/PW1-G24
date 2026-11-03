function F = ecg_features(ys, fs, fid, cfg, units)
%ECG_FEATURES Rhythm, interval, morphology, HRV and signal-quality features.
%   F = ECG_FEATURES(ys, fs, fid, cfg, units)
%   Beats are labelled 'N' (normal), 'S' (premature, narrow - supra-
%   ventricular) or 'V' (premature and wide / abnormal shape / no P -
%   ventricular). Interval medians use 'N' beats only.

ys = ys(:);
n  = numel(fid.R);
F  = defaults();
F.nBeats   = n;
F.duration = numel(ys)/fs;
F.calibrated = units.calibrated;
F.unitLabel  = units.label;
F.beatType = repmat('N', n, 1);
F.corr = NaN(n,1);
if n < 3
    F.quality = 'Unusable';
    F.qualityNote = sprintf('Only %d beat(s) detected - not enough for rhythm analysis.', n);
    return
end

R  = fid.R(:);
rr = diff(R)/fs;
F.rr = rr; F.rrTime = R(2:end)/fs;
F.hrInst = 60./rr;

%% Template / morphology correlation
pre = round(0.20*fs); post = round(0.40*fs);
ok = find(R - pre >= 1 & R + post <= numel(ys));
F.templateTime = (-pre:post)'/fs;
if numel(ok) >= 2
    M = zeros(pre+post+1, numel(ok));
    for j = 1:numel(ok), M(:,j) = ys(R(ok(j))-pre : R(ok(j))+post); end
    tmpl = median(M, 2);
    for j = 1:numel(ok)
        c = corrcoef(M(:,j), tmpl); F.corr(ok(j)) = c(1,2);
    end
    F.beats = M; F.beatIdx = ok;
end

%% Premature beat classification
for i = 1:numel(rr)
    nb = [max(1,i-4):i-1, i+1:min(numel(rr),i+4)];
    if numel(nb) >= 2, loc = median(rr(nb)); else, loc = median(rr); end
    if rr(i) < cfg.th.prematurity*loc
        b = i + 1;                      % beat ending this short interval
        wide  = fid.QRSd(b) >= cfg.th.qrsWide;
        odd   = ~isnan(F.corr(b)) && F.corr(b) < 0.80;
        if wide || odd                  % ventricular = wide or abnormal shape
            F.beatType(b) = 'V';
        else
            F.beatType(b) = 'S';
        end
    end
end
% wide, abnormally shaped beats that are not premature (e.g. VT runs)
wideOdd = fid.QRSd >= cfg.th.qrsWide & F.corr < 0.6 & ~fid.Pvalid;
F.beatType(wideOdd) = 'V';
isN = F.beatType == 'N';
F.nPVC = sum(F.beatType == 'V');
F.nPAC = sum(F.beatType == 'S');
F.ectopicBurden = 100*(F.nPVC + F.nPAC)/n;
F.bigeminy = has_bigeminy(F.beatType);
F.maxVRun  = max_run(F.beatType, 'V');

%% Rate
F.hrMean   = 60/mean(rr);
F.hrMedian = 60/median(rr);
F.hrMin    = 60/max(rr);
F.hrMax    = 60/min(rr);

%% Regularity / HRV
nnMask = isN(1:end-1) & isN(2:end);
nn = rr(nnMask);
ratio = rr/median(rr);
noV = ~(F.beatType(1:end-1) == 'V' | F.beatType(2:end) == 'V') & ratio < 1.75;
rrNoV = rr(noV);              % exclude PVC-coupled intervals and pauses
if numel(rrNoV) >= 3
    F.nRMSSD = sqrt(mean(diff(rrNoV).^2))/mean(rrNoV);
    F.cvRR   = std(rrNoV)/mean(rrNoV);
end
if numel(nn) >= 3
    F.meanNN = mean(nn);
    F.SDNN   = 1000*std(nn);
    F.RMSSD  = 1000*sqrt(mean(diff(nn).^2));
    F.pNN50  = 100*mean(abs(diff(nn)) > 0.05);
end
F.pauseCount = sum(rr > cfg.th.pause);
F.maxRR      = max(rr);
F.droppedBeats = sum(ratio > 1.75 & ratio < 2.25 & F.beatType(1:end-1) ~= 'V');

%% Intervals and amplitudes (normal beats)
nm = @(v) safe_median(v(isN));
F.pFrac  = mean(fid.Pvalid(isN));
prv = fid.PR(isN & fid.Pvalid);
F.PR     = safe_median(prv);
if numel(prv) >= 3, F.PRstd = std(prv); end
F.QRSd   = nm(fid.QRSd);
F.QT     = nm(fid.QT);
rrN = fid.RRprev(isN);
F.RRforQT = safe_median(rrN);
F.QTcB = F.QT/sqrt(F.RRforQT);
F.QTcF = F.QT/F.RRforQT^(1/3);
F.Ramp = nm(fid.Ramp);
F.QRSpp = nm(fid.Ramp - min(fid.Qamp, fid.Samp));
F.Pamp = safe_median(fid.Pamp(isN & fid.Pvalid));
F.Tamp = nm(fid.Tamp);
F.ST   = nm(fid.ST);
F.Tinverted = F.Tamp < 0;

%% Typical fiducial offsets relative to R (for the average-beat plot)
rel = @(v) safe_median((v(isN) - R(isN))/fs);
F.offPon = rel(fid.Pon); F.offQRSon = rel(fid.QRSon);
F.offQRSoff = rel(fid.QRSoff); F.offTend = rel(fid.Tend);
F.offPpk = rel(fid.Ppk); F.offTpk = rel(fid.Tpk);

%% Signal quality index = share of beats matching the template
F.sqi = mean(F.corr(~isnan(F.corr)) >= 0.9 | F.beatType(~isnan(F.corr)) ~= 'N');
if isnan(F.sqi), F.sqi = 0; end
if F.sqi >= cfg.th.sqiGood
    F.quality = 'Good';
elseif F.sqi >= cfg.th.sqiPoor
    F.quality = 'Acceptable';
else
    F.quality = 'Poor';
    F.qualityNote = 'Many beats differ from the average beat - noise or motion artefact likely.';
end

%% Frequency-domain HRV (needs >= 2 min of mostly normal beats)
if F.duration >= 120 && numel(nn) >= 100
    tn = F.rrTime(nnMask);
    ti = (tn(1):0.25:tn(end))';
    ri = interp1(tn, nn, ti, 'linear');
    ri = ri - mean(ri);
    [fh, Ph] = ecg_psd(ri, 4, 64);
    F.LF = sum(Ph(fh >= 0.04 & fh < 0.15))*(fh(2)-fh(1))*1e6;
    F.HF = sum(Ph(fh >= 0.15 & fh < 0.40))*(fh(2)-fh(1))*1e6;
    F.LFHF = F.LF/max(F.HF, eps);
end
end

%% ---------------------------------------------------------------------
function F = defaults()
names = {'hrMean','hrMedian','hrMin','hrMax','nRMSSD','cvRR','meanNN','SDNN', ...
    'RMSSD','pNN50','maxRR','pFrac','PR','PRstd','QRSd','QT','RRforQT','QTcB', ...
    'QTcF','Ramp','QRSpp','Pamp','Tamp','ST','offPon','offQRSon','offQRSoff', ...
    'offTend','offPpk','offTpk','sqi','LF','HF','LFHF','ectopicBurden'};
for k = 1:numel(names), F.(names{k}) = NaN; end
F.nPVC = 0; F.nPAC = 0; F.pauseCount = 0; F.droppedBeats = 0;
F.bigeminy = false; F.maxVRun = 0; F.Tinverted = false;
F.rr = []; F.rrTime = []; F.hrInst = [];
F.beats = []; F.beatIdx = []; F.templateTime = [];
F.quality = ''; F.qualityNote = '';
end

function m = safe_median(v)
v = v(~isnan(v));
if isempty(v), m = NaN; else, m = median(v); end
end

function tf = has_bigeminy(bt)
s = bt(:)';
tf = ~isempty(strfind(s, 'NVNVNV'));
end

function m = max_run(bt, c)
m = 0; cur = 0;
for k = 1:numel(bt)
    if bt(k) == c, cur = cur + 1; m = max(m, cur); else, cur = 0; end
end
end
