function y = ecg_filtfilt(b, a, x, npad)
%ECG_FILTFILT Zero-phase (forward-backward) filtering with reflection padding.
%   y = ECG_FILTFILT(b, a, x, npad) filters column vector x forwards and
%   backwards so the ECG waves are not shifted in time (essential when
%   measuring PR / QRS / QT intervals). npad samples of odd-reflected
%   signal are added at each end to suppress start-up transients.

x = x(:);
N = numel(x);
if N < 4
    y = x; return
end
if nargin < 4 || isempty(npad)
    npad = 3*max(numel(a), numel(b));
end
npad = max(0, min(npad, N-1));
if npad > 0
    pre  = 2*x(1)   - flipud(x(2:npad+1));
    post = 2*x(end) - flipud(x(end-npad:end-1));
    xp = [pre; x; post];
else
    xp = x;
end
yp = filter(b, a, xp);
yp = flipud(filter(b, a, flipud(yp)));
y  = yp(npad+1 : npad+N);
end
