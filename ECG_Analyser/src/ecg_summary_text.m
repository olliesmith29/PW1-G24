function [featLines, dxLines] = ecg_summary_text(res)
%ECG_SUMMARY_TEXT Human-readable summary lines (used by console, figure, report).

F = res.F; u = F.unitLabel;
ms = @(v) num_or_na(1000*v, '%.0f ms');
featLines = {
    sprintf('Source        : %s', res.meta.name)
    sprintf('Duration      : %.1f s @ %.0f Hz   Beats: %d', F.duration, res.fs, F.nBeats)
    sprintf('Signal quality: %s (SQI %.2f)', F.quality, F.sqi)
    sprintf('Rhythm        : %s', res.rhythm)
    sprintf('Heart rate    : %s (range %s - %s)', num_or_na(F.hrMedian, '%.0f bpm'), num_or_na(F.hrMin, '%.0f'), num_or_na(F.hrMax, '%.0f'))
    sprintf('PR interval   : %s   (P waves in %s of beats)', ms(F.PR), num_or_na(100*F.pFrac, '%.0f%%'))
    sprintf('QRS duration  : %s', ms(F.QRSd))
    sprintf('QT / QTc(B/F) : %s / %s / %s', ms(F.QT), ms(F.QTcB), ms(F.QTcF))
    sprintf('ST level      : %s     T amp: %s', num_or_na(F.ST, ['%+.2f ' u]), num_or_na(F.Tamp, ['%+.2f ' u]))
    sprintf('R amp / QRSpp : %s / %s', num_or_na(F.Ramp, ['%.2f ' u]), num_or_na(F.QRSpp, ['%.2f ' u]))
    sprintf('HRV SDNN/RMSSD: %s / %s   pNN50 %s', num_or_na(F.SDNN, '%.0f ms'), num_or_na(F.RMSSD, '%.0f ms'), num_or_na(F.pNN50, '%.0f%%'))
    sprintf('Ectopic beats : %d PVC, %d PAC   Pauses: %d', F.nPVC, F.nPAC, F.pauseCount)
    };
if ~isnan(F.LFHF)
    featLines{end+1} = sprintf('LF/HF ratio   : %.2f', F.LFHF);
end
dxLines = {};
for k = 1:numel(res.dx)
    d = res.dx(k);
    dxLines{end+1,1} = sprintf('[%s] %s', d.likelihood, d.finding); %#ok<AGROW>
    dxLines{end+1,1} = sprintf('    %s', d.evidence); %#ok<AGROW>
end
end

function s = num_or_na(v, f)
if isempty(v) || isnan(v), s = 'n/a'; else, s = sprintf(f, v); end
end
