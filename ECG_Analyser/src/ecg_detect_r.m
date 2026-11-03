function [rIdx, det] = ecg_detect_r(y, fs, cfg)
%ECG_DETECT_R R-peak detection (Pan-Tompkins with adaptive thresholds).
%   [rIdx, det] = ECG_DETECT_R(y, fs, cfg)
%   y : pre-processed ECG (column).  rIdx : sample indices of R peaks.
%   Steps: 5-15 Hz band-pass -> derivative -> squaring -> 150 ms moving
%   window integration -> adaptive dual threshold with T-wave rejection
%   and search-back for missed beats -> refine on the filtered ECG.
%   Polarity is checked so an inverted lead (swapped RA/LA) still works.
%   Ref: J. Pan & W. Tompkins, IEEE Trans. Biomed. Eng., 32(3), 1985.

y = y(:); N = numel(y);
det = struct('polarity', 1, 'message', '', 'mwi', zeros(N,1), 'nCandidates', 0);
rIdx = zeros(0,1);
if N < round(0.5*fs) || std(y) < 1e-9
    det.message = 'Signal too short or flat - no beats detected.';
    return
end
npad = min(N-1, round(fs));

%% 1. Band-pass (QRS energy)
lo = cfg.qrsBand(1); hi = min(cfg.qrsBand(2), 0.45*fs);
[b, a] = ecg_biquad('hp', lo, fs, 0.7071); bp = ecg_filtfilt(b, a, y, npad);
[b, a] = ecg_biquad('lp', hi, fs, 0.7071); bp = ecg_filtfilt(b, a, bp, npad);
%% 2-4. Derivative, square, integrate
d   = conv(bp, [1 2 0 -2 -1]'*fs/8, 'same');
sq  = d.^2;
W   = max(1, round(cfg.mwiWindow*fs));
mwi = conv(sq, ones(W,1)/W, 'same');
det.mwi = mwi;

%% Candidate peaks (local maxima at least one refractory period apart)
ref = round(cfg.refractory*fs);
locs = find(mwi(2:end-1) > mwi(1:end-2) & mwi(2:end-1) >= mwi(3:end)) + 1;
if isempty(locs), det.message = 'No candidate peaks.'; return; end
[~, order] = sort(mwi(locs), 'descend');
blocked = false(N,1); keep = false(size(locs));
for k = order(:)'
    L = locs(k);
    if ~blocked(L)
        keep(k) = true;
        blocked(max(1,L-ref):min(N,L+ref)) = true;
    end
end
locs = sort(locs(keep));
pk = mwi(locs);
det.nCandidates = numel(locs);

%% Robust threshold initialisation (offline: use whole record)
nExp = max(3, round(0.5*N/fs));             % ~ half the expected beat count
sp = sort(pk, 'descend');
SPKI = median(sp(1:min(nExp, numel(sp))));
low = pk(pk < 0.5*SPKI);
if isempty(low), NPKI = 0.1*SPKI; else, NPKI = median(low); end
THR1 = NPKI + 0.25*(SPKI - NPKI);

%% Adaptive threshold pass
qrs = zeros(0,1); qrsSlope = zeros(0,1);
rejected = zeros(0,1);
tw = round(cfg.tWaveCheck*fs);
sw = max(1, round(0.075*fs));
for i = 1:numel(locs)
    L = locs(i); A = pk(i);
    % --- search-back for a missed beat
    if numel(qrs) >= 2
        rrAvg = mean(diff(qrs(max(1,end-8):end)));
        if L - qrs(end) > cfg.searchBack*rrAvg && ~isempty(rejected)
            c = rejected(rejected > qrs(end) + ref & rejected < L - ref);
            if ~isempty(c)
                [Am, j] = max(mwi(c));
                if Am > 0.5*THR1
                    qrs(end+1,1) = c(j); %#ok<AGROW>
                    qrsSlope(end+1,1) = max(abs(d(max(1,c(j)-sw):min(N,c(j)+sw)))); %#ok<AGROW>
                    SPKI = 0.25*Am + 0.75*SPKI;
                end
            end
        end
    end
    % --- classify this candidate
    slope = max(abs(d(max(1,L-sw):min(N,L+sw))));
    if A > THR1
        if ~isempty(qrs) && (L - qrs(end)) < tw && slope < 0.5*qrsSlope(end)
            NPKI = 0.125*A + 0.875*NPKI;          % T wave
            rejected(end+1,1) = L; %#ok<AGROW>
        else
            qrs(end+1,1) = L; qrsSlope(end+1,1) = slope; %#ok<AGROW>
            SPKI = 0.125*A + 0.875*SPKI;
        end
    else
        NPKI = 0.125*A + 0.875*NPKI;
        rejected(end+1,1) = L; %#ok<AGROW>
    end
    THR1 = NPKI + 0.25*(SPKI - NPKI);
end
qrs = sort(qrs);
if isempty(qrs), det.message = 'No QRS complexes passed the threshold.'; return; end

%% Polarity check and refinement onto the ECG itself
hw = round(0.10*fs);
pmax = zeros(numel(qrs),1); pmin = pmax;
for i = 1:numel(qrs)
    w = max(1,qrs(i)-hw):min(N,qrs(i)+hw);
    pmax(i) = max(y(w)); pmin(i) = -min(y(w));
end
if median(pmin) > cfg.invertRatio*median(pmax)
    det.polarity = -1;
    det.message = 'Signal appears inverted (check RA/LA electrode placement) - analysed with polarity flipped.';
end
ys = det.polarity*y;
rIdx = zeros(numel(qrs),1);
for i = 1:numel(qrs)
    w = max(1,qrs(i)-hw):min(N,qrs(i)+hw);
    [~, k] = max(ys(w));
    rIdx(i) = w(k);
end
% remove duplicates closer than the refractory period (keep taller)
rIdx = unique(rIdx);
i = 2;
while i <= numel(rIdx)
    if rIdx(i) - rIdx(i-1) < ref
        if ys(rIdx(i)) > ys(rIdx(i-1)), rIdx(i-1) = []; else, rIdx(i) = []; end
    else
        i = i + 1;
    end
end
end
