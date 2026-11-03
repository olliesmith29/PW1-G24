function cfg = ecg_config()
%ECG_CONFIG Default settings for the Group 24 ECG Analyser.
%   cfg = ECG_CONFIG() returns a struct holding every tunable parameter in
%   one place, so the processing functions contain no "magic numbers".
%   Change values in ECG_Analyser.m (e.g. cfg.sex = 'female') rather than
%   editing this file.
%
%   EE22005 Project Week 1 - Group 24 (afb48, fjc48, owas20, aedg20, lhs53, ke417)

%% Ownership / labelling (shown on every figure and report)
cfg.authors   = 'Group 24 - afb48, fjc48, owas20, aedg20, lhs53, ke417';
cfg.project   = 'EE22005 PW1 - The Puzzling Physiology (ECG)';

%% Input interpretation
cfg.fs        = [];        % sampling rate (Hz) if the file has no time column
cfg.column    = [];        % which column holds ECG (empty = automatic)
cfg.units     = 'auto';    % 'auto' | 'mV' | 'V' | 'V_adc' | 'counts' | 'arbitrary'
cfg.adcBits   = 10;        % Arduino Uno ADC = 10 bit (0-1023)
cfg.adcVref   = 5.0;       % Arduino analogue reference (V)
cfg.frontEndGain = 1100;   % AD8232 SparkFun board: 100 (in-amp) x 11 (op-amp)
cfg.maxJitter = 0.02;      % resample if sample-interval CV exceeds this

%% Pre-processing (zero-phase IIR filters - no toolbox required)
cfg.hpCutoff       = 0.5;  % Hz - baseline wander removal
cfg.lpCutoff       = 40;   % Hz - EMG / HF noise removal (diagnostic bandwidth)
cfg.mainsFreq      = 50;   % Hz - UK mains
cfg.notchQ         = 30;   % notch quality factor
cfg.notchHarmonics = true; % also notch 100 Hz, 150 Hz (if below Nyquist)

%% R-peak detection (Pan-Tompkins)
cfg.qrsBand    = [5 15];   % Hz - QRS energy band
cfg.mwiWindow  = 0.150;    % s  - moving-window integrator length
cfg.refractory = 0.200;    % s  - minimum time between beats
cfg.tWaveCheck = 0.360;    % s  - T-wave discrimination window
cfg.searchBack = 1.66;     % x mean RR before search-back is triggered
cfg.invertRatio = 1.4;     % flip polarity if |negative| > ratio x positive

%% Delineation
cfg.pMinRatio  = 0.06;     % P amplitude must exceed this fraction of R
cfg.qrsEdgeFrac = 0.10;    % QRS on/offset where slope < this x peak slope

%% Clinical decision thresholds (adult resting single-lead ECG)
th.bradyBpm      = 60;     % bpm
th.severeBrady   = 40;
th.tachyBpm      = 100;
th.prLong        = 0.200;  % s  (1st-degree AV block)
th.prShort       = 0.120;  % s  (pre-excitation)
th.qrsWide       = 0.120;  % s  (bundle branch block / ventricular)
th.qrsBorder     = 0.110;  % s  (incomplete BBB / IVCD)
th.qtcLongMale   = 0.450;  % s
th.qtcLongFemale = 0.460;  % s
th.qtcVeryLong   = 0.500;  % s  (torsades risk)
th.qtcShort      = 0.350;  % s
th.stElev        = 0.10;   % mV (1 mm)
th.stDep         = 0.05;   % mV (0.5 mm)
th.lowVoltage    = 0.50;   % mV peak-to-peak QRS
th.peakedT       = 0.75;   % T/R amplitude ratio
th.pause         = 2.0;    % s
th.prematurity   = 0.80;   % RR < 0.8 x local median = premature
th.afIrregular   = 0.12;   % normalised RMSSD above which rhythm is irregular
th.pPresentFrac  = 0.60;   % fraction of beats needing a P wave
th.prStdMax      = 0.040;  % s - max PR variability for a consistent P wave
th.sqiGood       = 0.90;
th.sqiPoor       = 0.70;
cfg.th = th;
cfg.sex = 'unknown';       % 'male' | 'female' | 'unknown' (QTc limits)

%% Output
cfg.displaySeconds = 10;   % length of the annotated strip
cfg.showPlots   = true;
cfg.saveOutputs = true;
cfg.outputDir   = 'ECG_outputs';
cfg.verbose     = true;
end
