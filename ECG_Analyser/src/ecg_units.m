function [y, u] = ecg_units(x, cfg, hint)
%ECG_UNITS Convert raw samples to millivolts at the electrodes.
%   [y, u] = ECG_UNITS(x, cfg)
%   cfg.units = 'auto' guesses the format:
%     counts : integers within the ADC range (Arduino analogRead 0-1023)
%     V_adc  : positive volts centred ~1.5 V (AD8232 output measured directly)
%     V      : volts at the electrodes (range < 50 mV)
%     mV     : millivolts (MATLAB Signal Simulator, PhysioNet)
%     arbitrary : anything else - amplitude-based rules are then disabled
%   Front-end gain (AD8232 = 1100) and ADC settings come from cfg.
%   hint (optional) = unit guessed by ecg_load from the raw file.

xf = x(isfinite(x));
full = 2^cfg.adcBits - 1;
mode = lower(cfg.units);
if nargin < 3, hint = ''; end
if strcmp(mode, 'auto') && ~isempty(hint)
    mode = hint; u.auto = true;
elseif strcmp(mode, 'auto')
    rng_ = max(xf) - min(xf);
    isInt = all(abs(xf - round(xf)) < 1e-9);
    if isInt && min(xf) >= 0 && max(xf) <= full && rng_ >= 5
        mode = 'counts';
    elseif min(xf) > 0 && median(xf) > 0.5 && max(xf) <= 5.5 && rng_ < 3.5
        mode = 'v_adc';
    elseif rng_ < 0.05
        mode = 'v';
    elseif rng_ <= 20
        mode = 'mv';
    else
        mode = 'arbitrary';
    end
    u.auto = true;
else
    u.auto = false;
end
u.calibrated = true;
switch mode
    case 'counts'
        y = x*cfg.adcVref/full/cfg.frontEndGain*1000;
        u.description = sprintf('ADC counts (%d-bit, Vref %.1f V, gain %g) -> mV', cfg.adcBits, cfg.adcVref, cfg.frontEndGain);
    case 'v_adc'
        y = x/cfg.frontEndGain*1000;
        u.description = sprintf('Volts at front-end output (gain %g) -> mV', cfg.frontEndGain);
    case 'v'
        y = x*1000;
        u.description = 'Volts -> mV';
    case 'mv'
        y = x;
        u.description = 'mV';
    otherwise
        y = x;
        u.calibrated = false;
        mode = 'arbitrary';
        u.description = 'Arbitrary units - amplitude rules (ST, voltage) disabled';
end
u.mode = mode;
if u.calibrated, u.label = 'mV'; else, u.label = 'a.u.'; end
end
