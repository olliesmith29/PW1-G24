function fid = ecg_delineate(ys, fs, rIdx, cfg)
%ECG_DELINEATE Locate P, Q, R, S, T fiducial points for every beat.
%   fid = ECG_DELINEATE(ys, fs, rIdx, cfg)
%   ys   : filtered ECG with R upright (mV), rIdx : R-peak indices
%   fid  : struct of column vectors (one row per beat). Indices are
%          samples; amplitudes are relative to the local isoelectric
%          (PR-segment) baseline; intervals are seconds. Any feature that
%          cannot be found is NaN (fail-safe - never crashes on a missing
%          wave).
%   Windows scale with the RR interval so the method works from ~40 to
%   ~180 bpm. T-wave end uses the tangent (Lepeschkin) method.

ys = ys(:); N = numel(ys); rIdx = rIdx(:); n = numel(rIdx);
f = {'Pon','Ppk','QRSon','Q','R','S','QRSoff','Tpk','Tend','base', ...
     'Pamp','Ramp','Qamp','Samp','Tamp','ST','PR','QRSd','QT','RRprev'};
for k = 1:numel(f), fid.(f{k}) = NaN(n,1); end
fid.Pvalid = false(n,1);
fid.R = rIdx;
if n == 0, return; end

ms = @(s) max(1, round(s*fs));
d  = [diff(ys); 0]*fs;                          % mV/s
e  = conv(abs(d), ones(ms(0.02),1)/ms(0.02), 'same');
rr = diff(rIdx)/fs;
if isempty(rr), medRR = 1; else, medRR = median(rr); end

for i = 1:n
    r = rIdx(i);
    if i > 1, RRp = (r - rIdx(i-1))/fs; else, RRp = medRR; end
    if i < n, RRn = (rIdx(i+1) - r)/fs; else, RRn = medRR; end
    fid.RRprev(i) = RRp;

    %% Q, S and QRS boundaries
    w = max(1, r-ms(0.06)):r;        [~,k] = min(ys(w)); Q = w(k);
    w = r:min(N, r+ms(0.08));        [~,k] = min(ys(w)); S = w(k);
    wq = max(1, r-ms(0.12)):min(N, r+ms(0.12));
    thr = cfg.qrsEdgeFrac*max(e(wq));
    on = r;  lim = max(1, r - ms(0.15));
    while on > lim && e(on) > thr, on = on - 1; end
    off = r; lim = min(N, r + ms(0.20));
    if i < n, lim = min(lim, rIdx(i+1) - ms(0.1)); end
    while off < lim && e(off) > thr, off = off + 1; end

    bw = max(1, on-ms(0.04)):max(1, on-ms(0.01));
    base = median(ys(bw));

    fid.Q(i) = Q; fid.S(i) = S; fid.QRSon(i) = on; fid.QRSoff(i) = off;
    fid.base(i) = base;
    fid.Ramp(i) = ys(r) - base; fid.Qamp(i) = ys(Q) - base; fid.Samp(i) = ys(S) - base;
    fid.QRSd(i) = (off - on)/fs;
    jOff = ms(0.06); if RRp < 0.5, jOff = ms(0.04); end
    if off + jOff <= N, fid.ST(i) = ys(off + jOff) - base; end

    %% T wave
    tS = off + ms(0.04);
    tE = min(N, r + ms(min(0.60, 0.75*RRn)));
    if i < n, tE = min(tE, rIdx(i+1) - ms(0.10)); end
    if tE - tS >= ms(0.04)
        seg = ys(tS:tE) - base;
        [~, k] = max(abs(seg));
        Tpk = tS + k - 1; Tamp = seg(k);
        if k > 1 && k < numel(seg) && abs(Tamp) > 0.03*abs(fid.Ramp(i))
            fid.Tpk(i) = Tpk; fid.Tamp(i) = Tamp;
            sgn = sign(Tamp);
            wE = Tpk:min([N, Tpk + ms(0.25), tE + ms(0.10)]);
            v  = sgn*(ys(wE) - base);             % stop where T has returned
            kt = find(v < 0.15*abs(Tamp), 1);     %  near baseline, so a following
            if isempty(kt), [~, kt] = min(v); end %  P wave (fused at high HR) is ignored
            wE = wE(1:min(numel(wE), max(2, kt + ms(0.02))));
            [m, k2] = min(sgn*d(wE));             % steepest return slope
            if m < 0
                j = wE(k2);
                dist = (sgn*(ys(j) - base))/(-m);   % seconds to baseline
                te = j + round(dist*fs);
                te = min([te, Tpk + ms(0.30), N]);
                te = max(te, Tpk);
                fid.Tend(i) = te;
                fid.QT(i) = (te - on)/fs;
            end
        end
    end

    %% P wave
    pS = on - ms(min(0.35, 0.7*RRp));
    if i > 1 && ~isnan(fid.Tpk(i-1)), pS = max(pS, fid.Tpk(i-1) + ms(0.08)); end
    pS = max(1, pS);
    pE = on - ms(0.02);
    if pE - pS >= ms(0.04)
        seg = ys(pS:pE) - base;
        [pa, k] = max(seg);
        interior = k > 2 && k < numel(seg) - 1;
        if interior && pa > 0 && pa >= cfg.pMinRatio*fid.Ramp(i)
            Ppk = pS + k - 1;
            j = Ppk; lim = max(pS, Ppk - ms(0.12));
            while j > lim && (ys(j) - base) > 0.2*pa, j = j - 1; end
            fid.Pvalid(i) = true; fid.Ppk(i) = Ppk; fid.Pamp(i) = pa;
            fid.Pon(i) = j; fid.PR(i) = (on - j)/fs;
        end
    end
end
end
