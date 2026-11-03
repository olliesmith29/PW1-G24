function [f, P] = ecg_psd(x, fs, segSeconds)
%ECG_PSD Welch power spectral density estimate (Hann window, 50 % overlap).
%   [f, P] = ECG_PSD(x, fs) returns one-sided PSD P (units^2/Hz) at
%   frequencies f (Hz). Implemented with FFT only - no toolbox needed.

if nargin < 3, segSeconds = 4; end
x = x(:) - mean(x);
N = numel(x);
L = min(N, max(16, round(segSeconds*fs)));
w = 0.5 - 0.5*cos(2*pi*(0:L-1)'/(L-1));
step = max(1, floor(L/2));
starts = 1:step:(N-L+1);
nfft = 2^nextpow2(L);
acc = zeros(nfft,1);
for s = starts
    seg = x(s:s+L-1).*w;
    acc = acc + abs(fft(seg, nfft)).^2;
end
acc = acc/numel(starts);
U = sum(w.^2);
P = acc/(fs*U);
nh = floor(nfft/2)+1;
P = P(1:nh);
P(2:end-1) = 2*P(2:end-1);
f = (0:nh-1)'*fs/nfft;
end
