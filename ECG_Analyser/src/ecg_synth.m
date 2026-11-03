function [ecg, t, truth] = ecg_synth(type, duration, fs, opts)
%ECG_SYNTH Synthetic single-lead ECG with known ground truth.
%   [ecg, t, truth] = ECG_SYNTH(type, duration, fs, opts)
%   Each beat is built from Gaussian P, Q, R, S and (asymmetric) T waves
%   whose timing follows the RR interval, so the true R-peak positions and
%   intervals are known exactly - used to TEST the analyser.
%
%   type : 'normal' | 'brady' | 'tachy' | 'af' | 'pvc' | 'avb1' | 'avb2' |
%          'longqt' | 'stelev' | 'stdep' | 'wideqrs' | 'pause' | 'vt'
%   duration (s, default 30), fs (Hz, default 500)
%   opts.baseline, opts.mains, opts.emg, opts.motion : noise amplitudes (mV)
%   opts.seed : random seed (default 1); opts.hr / opts.hrv override rate / variability
%   ecg is in mV.  truth has fields rIdx, rTimes, beatType, hr, pr, qtc...

if nargin < 1 || isempty(type), type = 'normal'; end
if nargin < 2 || isempty(duration), duration = 30; end
if nargin < 3 || isempty(fs), fs = 500; end
if nargin < 4, opts = struct(); end
def = struct('baseline',0,'mains',0,'emg',0,'motion',0,'seed',1,'hr',[],'hrv',[]);
fn = fieldnames(def);
for k = 1:numel(fn)
    if ~isfield(opts, fn{k}), opts.(fn{k}) = def.(fn{k}); end
end
set_seed(opts.seed);

%% Rhythm parameters
p.hr = 72; p.hrv = 0.03; p.pr = 0.16; p.qtc = 0.40; p.st = 0;
p.pAmp = 0.15; p.rAmp = 1.2; p.tAmp = 0.30; p.wide = false; p.hasP = true;
switch lower(type)
    case 'normal'
    case 'brady',   p.hr = 48;
    case 'tachy',   p.hr = 125; p.hrv = 0.01;
    case 'af',      p.hr = 95;  p.hasP = false;
    case 'pvc',     p.hr = 70;
    case 'avb1',    p.pr = 0.28;
    case 'avb2',    p.hr = 75;
    case 'longqt',  p.qtc = 0.53;
    case 'stelev',  p.st = 0.25;
    case 'stdep',   p.st = -0.15;
    case 'wideqrs', p.wide = true;
    case 'pause',   p.hr = 70;
    case 'vt',      p.hr = 165; p.hrv = 0.01; p.wide = true; p.hasP = false; p.tAmp = -0.4;
    otherwise
        error('ECG:badType', 'Unknown synthetic rhythm "%s".', type);
end
if ~isempty(opts.hr), p.hr = opts.hr; end
if ~isempty(opts.hrv), p.hrv = opts.hrv; end

%% Beat times
rr0 = 60/p.hr;
times = []; btype = ''; tcur = 0.5; k = 0;
pOnly = [];                      % P waves that are not conducted (AV block)
while tcur < duration - 0.3
    k = k + 1;
    bt = 'N';
    switch lower(type)
        case 'af'
            rr = rr0*(1 + 0.22*randn); rr = min(max(rr, 0.33), 1.3);
        case 'pvc'
            rr = rr0*(1 + p.hrv*randn);
            if mod(k,6) == 0, bt = 'V'; rr = 0.6*rr0; end
            if numel(btype) >= 1 && btype(end) == 'V', rr = 1.4*rr0; end
        case 'avb2'
            rr = rr0*(1 + 0.01*randn);
            if mod(k,4) == 0     % Mobitz II: P wave with no QRS, then gap
                pOnly(end+1) = tcur + rr - 0.15 + 0.01; %#ok<AGROW>
                rr = 2*rr;
            end
        case 'pause'
            rr = rr0*(1 + p.hrv*randn);
            if abs(tcur - duration/2) < rr0/2, rr = 2.8; end
        otherwise
            rr = rr0*(1 + p.hrv*randn);
    end
    tcur = tcur + rr;
    if tcur >= duration - 0.3, break; end
    if strcmpi(type, 'pvc') && bt == 'V'
        % premature beat already shortened rr
    end
    times(end+1) = tcur; %#ok<AGROW>
    btype(end+1) = bt; %#ok<AGROW>
end
if strcmpi(type,'vt'), btype(:) = 'V'; end

%% Build waveform
N = round(duration*fs);
t = (0:N-1)'/fs;
ecg = zeros(N,1);
if isempty(times), rrList = []; else, rrList = diff([times(1)-rr0, times]); end
for i = 1:numel(times)
    tr = times(i);
    rrb = rrList(i); if btype(i) == 'V' && ~strcmpi(type,'vt'), rrb = rr0; end
    qt = p.qtc*rrb^(1/3);          % Fridericia rate scaling
    idx = find(t > tr - 0.6 & t < tr + 0.8);
    tt = t(idx) - tr;
    w = zeros(size(tt));
    if btype(i) == 'V' || p.wide && strcmpi(type,'vt')
        % broad ventricular complex, discordant T, no P
        w = w + g(tt, -0.02, 1.5*sign(p.rAmp), 0.028) + g(tt, 0.05, -0.35, 0.025);
        w = w + gasym(tt, 0.30, -0.45, 0.07, 0.06);
    else
        if p.hasP
            w = w + g(tt, -p.pr + 0.01, p.pAmp, 0.025);
        end
        if p.wide
            w = w + g(tt, -0.035, -0.10, 0.012) + g(tt, 0, p.rAmp, 0.022) ...
                  + g(tt, 0.05, -0.40, 0.020);
            qrsOn = -0.06;
        else
            w = w + g(tt, -0.025, -0.12, 0.008) + g(tt, 0, p.rAmp, 0.010) ...
                  + g(tt, 0.025, -0.25, 0.009);
            qrsOn = -0.04;
        end
        % T end (tangent convention) = T peak + 2*sigma2, so QT = Tend - QRSon
        s1 = 0.06*sqrt(rrb); s2 = 0.04;
        tpk = qrsOn + qt - 2*s2;
        w = w + gasym(tt, tpk, p.tAmp, s1, s2);
        if p.st ~= 0
            w = w + g(tt, 0.12, p.st, 0.06);
        end
    end
    ecg(idx) = ecg(idx) + w;
end
% non-conducted P waves (AV block)
for i = 1:numel(pOnly)
    ecg = ecg + g(t - pOnly(i), 0, p.pAmp, 0.025);
end
% AF fibrillatory waves
if strcmpi(type,'af')
    fphase = cumsum(2*pi*(5.5 + 0.8*randn(N,1))/fs);
    ecg = ecg + 0.03*sin(fphase);
end

%% Noise / artefacts
if opts.baseline > 0
    ph = 2*pi*rand(2,1);
    ecg = ecg + opts.baseline*(0.6*sin(2*pi*0.25*t + ph(1)) + 0.4*sin(2*pi*0.07*t + ph(2)));
end
if opts.mains > 0
    ecg = ecg + opts.mains*(sin(2*pi*50*t) + 0.3*sin(2*pi*150*t + 1));
end
if opts.emg > 0
    ecg = ecg + opts.emg*randn(N,1);
end
if opts.motion > 0
    nEv = max(1, round(duration/10));
    for e = 1:nEv
        t0 = rand*duration;
        ecg = ecg + opts.motion*(t > t0).*exp(-(t - t0)/0.3).*sign(randn);
    end
end

truth.type = type;
truth.fs = fs;
truth.rTimes = times(:);
truth.rIdx = round(times(:)*fs) + 1;
truth.beatType = btype(:);
truth.hr = p.hr;
truth.pr = p.pr;
truth.qtc = p.qtc;
truth.st = p.st;
truth.hasP = p.hasP;
end

function y = g(t, mu, a, s)
y = a*exp(-(t - mu).^2/(2*s^2));
end

function y = gasym(t, mu, a, s1, s2)
s = s1*ones(size(t)); s(t >= mu) = s2;
y = a*exp(-(t - mu).^2./(2*s.^2));
end

function set_seed(s)
try
    rng(s);
catch
    rand('seed', s); randn('seed', s); %#ok<RAND>
end
end
