function pre = ecg_preprocess(x, fs, cfg)
%ECG_PREPROCESS Remove baseline wander, mains interference and HF noise.
%   pre = ECG_PREPROCESS(x, fs, cfg)   (x in mV)
%   Stages (all zero-phase so wave timing is preserved):
%     1. 4th-order Butterworth high-pass at cfg.hpCutoff  -> baseline wander
%     2. Notch at cfg.mainsFreq (+ harmonics)             -> powerline
%     3. 4th-order Butterworth low-pass at cfg.lpCutoff   -> EMG / HF noise
%   pre.y is the clean signal; intermediate stages are kept for plotting.

x = x(:) - median(x);
nyq  = fs/2;
npad = min(numel(x)-1, round(2*fs));
qB = [0.5412, 1.3066];           % Q values of a 4th-order Butterworth

pre.raw = x;
y = x;
pre.hpApplied = false;
if cfg.hpCutoff > 0 && cfg.hpCutoff < 0.4*nyq
    for q = qB
        [b, a] = ecg_biquad('hp', cfg.hpCutoff, fs, q);
        y = ecg_filtfilt(b, a, y, npad);
    end
    pre.hpApplied = true;
end
pre.afterHP = y;

pre.notches = [];
if ~isempty(cfg.mainsFreq) && cfg.mainsFreq > 0
    nh = 1; if cfg.notchHarmonics, nh = 3; end
    for h = 1:nh
        f0 = h*cfg.mainsFreq;
        if f0 < 0.95*nyq
            [b, a] = ecg_biquad('notch', f0, fs, cfg.notchQ);
            y = ecg_filtfilt(b, a, y, npad);
            pre.notches(end+1) = f0;
        end
    end
end
pre.afterNotch = y;

fc = min(cfg.lpCutoff, 0.45*fs);
for q = qB
    [b, a] = ecg_biquad('lp', fc, fs, q);
    y = ecg_filtfilt(b, a, y, npad);
end
pre.lpCutoff = fc;
pre.y = y;

%% Spectra and simple noise metrics (before vs after)
[pre.f, pre.Praw]  = ecg_psd(x, fs);
[~,     pre.Pfilt] = ecg_psd(y, fs);
band = @(P, lo, hi) sum(P(pre.f >= lo & pre.f <= hi));
tot  = @(P) sum(P(pre.f >= 0.05 & pre.f <= min(150, nyq)));
if ~isempty(cfg.mainsFreq) && cfg.mainsFreq < nyq
    m = cfg.mainsFreq;
    pre.mainsFracRaw  = band(pre.Praw,  m-1, m+1)/max(tot(pre.Praw), eps);
    pre.mainsFracFilt = band(pre.Pfilt, m-1, m+1)/max(tot(pre.Pfilt), eps);
else
    pre.mainsFracRaw = NaN; pre.mainsFracFilt = NaN;
end
pre.baselineFracRaw = band(pre.Praw, 0, 0.5)/max(band(pre.Praw, 0, min(150,nyq)), eps);
pre.removedRms = sqrt(mean((x - y).^2));
end
