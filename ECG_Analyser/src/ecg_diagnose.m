function [dx, rhythm] = ecg_diagnose(F, cfg)
%ECG_DIAGNOSE Rule-based differential list from the extracted features.
%   [dx, rhythm] = ECG_DIAGNOSE(F, cfg)
%   dx is a struct array (finding, likelihood, evidence, causes) sorted
%   High > Moderate > Low > Note. Thresholds live in cfg.th.
%   EDUCATIONAL ONLY - a single-lead, rule-based screen cannot diagnose.

th = cfg.th;
dx = struct('finding', {}, 'likelihood', {}, 'evidence', {}, 'causes', {});
rhythm = 'Undetermined';

%% Fail-safe: not enough data
if F.nBeats < 3 || strcmp(F.quality, 'Unusable')
    dx = add(dx, 'Insufficient data for rhythm analysis', 'Note', F.qualityNote, ...
        'Leads off, flat line, recording too short, or wrong sampling rate.');
    rhythm = 'No rhythm detected';
    return
end
if strcmp(F.quality, 'Poor')
    dx = add(dx, 'Poor signal quality - interpret with caution', 'Note', ...
        sprintf('Signal-quality index %.2f (< %.2f).', F.sqi, th.sqiPoor), ...
        'Motion artefact, poor electrode contact, muscle (EMG) noise.');
end

hr = F.hrMedian;
irregular = F.nRMSSD > th.afIrregular;
pPresent  = F.pFrac >= th.pPresentFrac && (isnan(F.PRstd) || F.PRstd <= th.prStdMax);
wide      = F.QRSd >= th.qrsWide;
isAF = false;

%% Rhythm
if irregular && ~pPresent
    isAF = true;
    rhythm = 'Irregularly irregular, no consistent P waves';
    dx = add(dx, 'Atrial fibrillation', 'High', ...
        sprintf('nRMSSD %.2f (> %.2f), P waves in %.0f%% of beats, PR SD %s.', ...
        F.nRMSSD, th.afIrregular, 100*F.pFrac, fmt_ms(F.PRstd)), ...
        'Hypertension, valve disease, heart failure, thyroid disease, alcohol, age.');
    dx = add(dx, 'Atrial flutter with variable block', 'Low', ...
        'Irregular ventricular response without clear P waves.', 'As for AF.');
    if hr > 110
        dx = add(dx, 'Multifocal atrial tachycardia', 'Low', ...
            sprintf('Rate %.0f bpm, irregular.', hr), 'Lung disease (COPD), hypoxia.');
    end
elseif irregular && pPresent
    rhythm = 'Sinus rhythm with marked variability';
    if F.ectopicBurden < 10
        dx = add(dx, 'Sinus arrhythmia', 'Moderate', ...
            sprintf('P waves present (%.0f%%), RR varies (nRMSSD %.2f).', 100*F.pFrac, F.nRMSSD), ...
            'Normal breathing-related variation, especially in young/fit people.');
    end
elseif ~pPresent && ~wide
    rhythm = 'Regular, narrow QRS, no consistent P waves';
    if hr > 140
        dx = add(dx, 'Supraventricular tachycardia (SVT)', 'High', ...
            sprintf('Regular narrow-complex rhythm at %.0f bpm without visible P waves.', hr), ...
            'AVNRT / AVRT, stimulants, caffeine.');
        dx = add(dx, 'Atrial flutter with 2:1 block', 'Moderate', 'Rate near 150 bpm.', 'Structural heart disease.');
    elseif hr < 60
        dx = add(dx, 'Junctional rhythm', 'Moderate', ...
            sprintf('Regular narrow QRS at %.0f bpm, P waves not seen.', hr), ...
            'Sinus node dysfunction, drugs (beta-blockers, digoxin).');
    else
        dx = add(dx, 'P waves not identified - possible junctional or ectopic atrial rhythm', 'Low', ...
            sprintf('P waves found in %.0f%% of beats.', 100*F.pFrac), ...
            'Also caused by small P waves in this lead or noise.');
    end
elseif ~pPresent && wide
    rhythm = 'Regular, wide QRS, no P waves';
    if hr > 100
        dx = add(dx, 'Ventricular tachycardia', 'High', ...
            sprintf('Wide QRS (%s) at %.0f bpm with no P waves. URGENT if real.', fmt_ms(F.QRSd), hr), ...
            'Ischaemic heart disease, cardiomyopathy, electrolyte disturbance.');
        dx = add(dx, 'SVT with aberrant conduction', 'Moderate', 'Wide-complex tachycardia.', 'Bundle branch block plus SVT.');
    elseif hr < 50
        dx = add(dx, 'Idioventricular (escape) rhythm', 'Moderate', ...
            sprintf('Wide QRS at %.0f bpm.', hr), 'Complete heart block, sinus arrest.');
    else
        dx = add(dx, 'Accelerated idioventricular rhythm', 'Moderate', ...
            sprintf('Wide QRS at %.0f bpm, no P waves.', hr), 'Reperfusion after MI, drugs.');
    end
else
    rhythm = 'Sinus rhythm';
end

%% Rate (sinus)
if pPresent
    if hr < th.bradyBpm
        lk = 'High'; if hr < th.severeBrady, lk = 'High'; end
        dx = add(dx, 'Sinus bradycardia', lk, sprintf('Heart rate %.0f bpm (< %d).', hr, th.bradyBpm), ...
            'Athletic heart, sleep, beta-blockers, hypothyroidism, sick sinus syndrome.');
        rhythm = 'Sinus bradycardia';
    elseif hr > th.tachyBpm
        dx = add(dx, 'Sinus tachycardia', 'High', sprintf('Heart rate %.0f bpm (> %d).', hr, th.tachyBpm), ...
            'Exercise, anxiety, pain, fever, dehydration, anaemia, hyperthyroidism, caffeine.');
        rhythm = 'Sinus tachycardia';
    end
end
if ~pPresent && hr < th.severeBrady
    dx = add(dx, 'Severe bradycardia', 'High', sprintf('Ventricular rate %.0f bpm.', hr), ...
        'High-grade AV block, sinus arrest.');
end

%% Conduction
if pPresent && F.PR > th.prLong
    dx = add(dx, 'First-degree AV block', 'High', sprintf('PR interval %s (> %s).', fmt_ms(F.PR), fmt_ms(th.prLong)), ...
        'Increased vagal tone, AV-nodal drugs, Lyme disease, ageing conduction system.');
elseif pPresent && F.PR < th.prShort
    lk = 'Low'; if wide, lk = 'Moderate'; end
    dx = add(dx, 'Short PR - possible pre-excitation (WPW)', lk, sprintf('PR interval %s (< %s).', fmt_ms(F.PR), fmt_ms(th.prShort)), ...
        'Accessory pathway (WPW), Lown-Ganong-Levine, junctional rhythm.');
end
if F.droppedBeats > 0 && ~isAF
    dx = add(dx, 'Possible second-degree AV block / sinus exit block', 'Moderate', ...
        sprintf('%d RR interval(s) approximately twice the normal length.', F.droppedBeats), ...
        'Mobitz I/II AV block, sinoatrial exit block, non-conducted PACs.');
end
if F.pauseCount > 0 && ~(F.droppedBeats > 0)
    lk = 'Moderate'; if F.maxRR > 3, lk = 'High'; end
    dx = add(dx, 'Sinus pause / arrest', lk, sprintf('%d pause(s), longest %.2f s (> %.1f s).', F.pauseCount, F.maxRR, th.pause), ...
        'Sick sinus syndrome, high vagal tone, drugs.');
end
if wide && pPresent
    dx = add(dx, 'Wide QRS - bundle branch block', 'High', sprintf('QRS duration %s (>= %s).', fmt_ms(F.QRSd), fmt_ms(th.qrsWide)), ...
        'LBBB / RBBB (needs 12-lead to tell apart), WPW, hyperkalaemia, sodium-channel drugs.');
elseif F.QRSd >= th.qrsBorder && F.QRSd < th.qrsWide
    dx = add(dx, 'Borderline QRS - incomplete BBB / IVCD', 'Low', sprintf('QRS duration %s.', fmt_ms(F.QRSd)), ...
        'Incomplete bundle branch block, intraventricular conduction delay.');
end

%% Ectopy
if ~isAF
    if F.nPVC > 0
        lk = 'Moderate'; if F.nPVC >= 3, lk = 'High'; end
        ev = sprintf('%d premature wide/abnormal beat(s), %.1f%% of beats.', F.nPVC, 100*F.nPVC/F.nBeats);
        if F.bigeminy, ev = [ev ' Ventricular bigeminy pattern.']; end
        if F.maxVRun >= 3 && hr <= 100, ev = [ev sprintf(' Run of %d consecutive PVCs (NSVT).', F.maxVRun)]; end
        dx = add(dx, 'Premature ventricular complexes (PVCs)', lk, ev, ...
            'Caffeine, stress, electrolyte imbalance, structural heart disease.');
    end
    if F.nPAC > 0
        lk = 'Moderate'; if F.nPAC >= 3, lk = 'High'; end
        dx = add(dx, 'Premature atrial complexes (PACs)', lk, ...
            sprintf('%d premature narrow beat(s).', F.nPAC), 'Usually benign: caffeine, alcohol, stress.');
    end
end

%% Repolarisation (QTc unreliable in AF)
if ~isnan(F.QTcB) && ~isAF && ~wide
    switch lower(cfg.sex)
        case 'male',   qtLim = th.qtcLongMale;
        case 'female', qtLim = th.qtcLongFemale;
        otherwise,     qtLim = th.qtcLongMale;
    end
    qtc = F.QTcB; qname = 'Bazett';
    if hr > 90 || hr < 50, qtc = F.QTcF; qname = 'Fridericia'; end
    if qtc > qtLim
        lk = 'Moderate'; if qtc > th.qtcVeryLong, lk = 'High'; end
        dx = add(dx, 'Prolonged QT interval', lk, sprintf('QTc (%s) %s (> %s).', qname, fmt_ms(qtc), fmt_ms(qtLim)), ...
            'Congenital long-QT, QT-prolonging drugs, low K+/Mg2+/Ca2+. >500 ms = torsades risk.');
    elseif qtc < th.qtcShort
        dx = add(dx, 'Short QT interval', 'Moderate', sprintf('QTc (%s) %s (< %s).', qname, fmt_ms(qtc), fmt_ms(th.qtcShort)), ...
            'Hypercalcaemia, digoxin, congenital short-QT syndrome.');
    end
end
if wide && (F.calibrated || ~isnan(F.QTcB))
    dx = add(dx, 'ST / QT not assessed', 'Note', ...
        'QRS is wide, so ST-segment and QT measurements are unreliable (secondary repolarisation changes).', ...
        'Requires 12-lead ECG and clinician review.');
end
if F.calibrated && ~wide
    if F.ST >= th.stElev
        dx = add(dx, 'ST elevation', 'High', sprintf('ST level %+.2f mV at J+60 ms (>= %.2f mV).', F.ST, th.stElev), ...
            'Acute MI (STEMI - emergency), pericarditis, early repolarisation, LV aneurysm.');
    elseif F.ST <= -th.stDep
        dx = add(dx, 'ST depression', 'Moderate', sprintf('ST level %+.2f mV (<= -%.2f mV).', F.ST, th.stDep), ...
            'Myocardial ischaemia, digoxin effect, LVH strain, hypokalaemia, rate-related.');
    end
    if F.QRSpp < th.lowVoltage
        dx = add(dx, 'Low QRS voltage', 'Low', sprintf('QRS peak-to-peak %.2f mV (< %.2f mV).', F.QRSpp, th.lowVoltage), ...
            'Poor electrode contact / gain setting (check first), obesity, pericardial effusion, hypothyroidism.');
    end
end
if ~wide && ~isnan(F.Tamp) && F.Tamp > th.peakedT*F.Ramp
    dx = add(dx, 'Tall / peaked T waves', 'Low', sprintf('T/R ratio %.2f.', F.Tamp/F.Ramp), ...
        'Hyperkalaemia, early hyperacute MI, normal variant.');
end
if F.Tinverted && ~wide
    dx = add(dx, 'T-wave inversion', 'Low', sprintf('Median T amplitude %+.2f %s.', F.Tamp, F.unitLabel), ...
        'Ischaemia, ventricular strain, normal in some lead positions - check electrode placement.');
end

%% Normal result
abnormal = ~arrayfun(@(s) strcmp(s.likelihood, 'Note'), dx);
if ~any(abnormal) && strcmp(rhythm, 'Sinus rhythm')
    dx = add(dx, 'Normal sinus rhythm', 'High', ...
        sprintf('Rate %.0f bpm, regular, P waves present, PR %s, QRS %s, QTc %s.', ...
        hr, fmt_ms(F.PR), fmt_ms(F.QRSd), fmt_ms(F.QTcB)), 'No abnormality found by this single-lead screen.');
end

%% Physiological state (application - "what is the body doing?")
if ~isAF && pPresent && ~isnan(F.RMSSD)
    if hr > 100 && F.RMSSD < 20
        st = 'Elevated rate with low HRV - consistent with exertion or stress.';
    elseif hr < 70 && F.RMSSD > 40
        st = 'Low rate with high HRV - consistent with a relaxed / well-recovered state.';
    else
        st = 'Resting-range rate and HRV.';
    end
    dx = add(dx, 'Physiological state (HRV)', 'Note', ...
        sprintf('RMSSD %.0f ms, SDNN %.0f ms. %s', F.RMSSD, F.SDNN, st), 'Application: stress / fitness monitoring.');
end

%% Sort by likelihood
rank = containers.Map({'High','Moderate','Low','Note'}, {1,2,3,4});
r = arrayfun(@(s) rank(s.likelihood), dx);
[~, o] = sort(r);
dx = dx(o);
end

%% ---------------------------------------------------------------------
function dx = add(dx, finding, likelihood, evidence, causes)
dx(end+1) = struct('finding', finding, 'likelihood', likelihood, ...
                   'evidence', evidence, 'causes', causes);
end

function s = fmt_ms(v)
if isnan(v), s = 'n/a'; else, s = sprintf('%.0f ms', 1000*v); end
end
