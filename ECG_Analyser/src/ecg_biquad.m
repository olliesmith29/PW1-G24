function [b, a] = ecg_biquad(type, f0, fs, Q)
%ECG_BIQUAD Second-order IIR section (RBJ audio-EQ cookbook formulae).
%   [b,a] = ECG_BIQUAD(type, f0, fs, Q)
%     type : 'lp' | 'hp' | 'notch'
%     f0   : corner / centre frequency (Hz), 0 < f0 < fs/2
%     fs   : sampling rate (Hz)
%     Q    : quality factor (0.7071 = Butterworth 2nd order)
%   Written from first principles so the program does not need the
%   Signal Processing Toolbox (butter/iirnotch are not used).

if f0 <= 0 || f0 >= fs/2
    error('ECG:badFilter', 'Filter frequency %.2f Hz must be between 0 and fs/2 (%.1f Hz).', f0, fs/2);
end
w0 = 2*pi*f0/fs;
c  = cos(w0);
alpha = sin(w0)/(2*Q);
switch lower(type)
    case 'lp'
        b = [(1-c)/2, 1-c, (1-c)/2];
    case 'hp'
        b = [(1+c)/2, -(1+c), (1+c)/2];
    case 'notch'
        b = [1, -2*c, 1];
    otherwise
        error('ECG:badFilter', 'Unknown filter type "%s".', type);
end
a = [1+alpha, -2*c, 1-alpha];
b = b/a(1);
a = a/a(1);
end
