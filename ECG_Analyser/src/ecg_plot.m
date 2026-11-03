function fig = ecg_plot(res, cfg)
%ECG_PLOT One-page analysis dashboard.
%   fig = ECG_PLOT(res, cfg)
%   Panels: raw vs filtered strip | spectrum before/after filtering |
%   annotated strip with P-Q-R-S-T markers | average beat with PR, QRS
%   and QT intervals | heart-rate tachogram | Poincare plot |
%   measurements and differential list. Footer carries the group
%   usernames, source file and date (ePortfolio ownership rule).

if nargin < 2, cfg = res.cfg; end
F = res.F; fid = res.fid; fs = res.fs; t = res.t; u = F.unitLabel;
vis = 'on'; if ~cfg.showPlots, vis = 'off'; end
fig = figure('Name', ['ECG Analysis - ' res.meta.name], 'NumberTitle', 'off', ...
    'Color', 'w', 'Position', [40 40 1500 950], 'Visible', vis);

C.raw = [0.70 0.70 0.70]; C.ecg = [0.10 0.20 0.45];
C.P = [0.10 0.60 0.20]; C.Q = [0.20 0.45 0.90]; C.R = [0.85 0.10 0.10];
C.S = [0.60 0.20 0.80]; C.T = [0.95 0.55 0.05]; C.V = [0.85 0.10 0.10];

%% Display window (centre on first ectopic beat if any)
dur = min(cfg.displaySeconds, t(end));
t0 = 0;
v = find(F.beatType ~= 'N', 1);
if ~isempty(v), t0 = max(0, min(t(end) - dur, fid.R(v)/fs - dur/3)); end
win = t >= t0 & t <= t0 + dur;

%% 1. Raw vs filtered
ax1 = subplot(4,3,[1 2]);
plot(t(win), res.raw(win), 'Color', C.raw); hold on
plot(t(win), res.det.polarity*res.pre.y(win), 'Color', C.ecg, 'LineWidth', 1);
hold off; grid on; xlim([t0 t0+dur]);
ylabel(['Amplitude (' u ')']);
title('1. Raw signal (grey) vs filtered (blue)');
legend({'raw','filtered'}, 'Location', 'northeast');

%% 2. Spectrum
subplot(4,3,3);
fmax = min(150, fs/2);
k = res.pre.f <= fmax & res.pre.f > 0;
plot(res.pre.f(k), 10*log10(res.pre.Praw(k) + eps), 'Color', C.raw); hold on
plot(res.pre.f(k), 10*log10(res.pre.Pfilt(k) + eps), 'Color', C.ecg, 'LineWidth', 1);
hold off; grid on; xlim([0 fmax]);
xlabel('Frequency (Hz)'); ylabel('PSD (dB)');
title(sprintf('2. Spectrum: HP %.1f Hz, notch %s Hz, LP %.0f Hz', cfg.hpCutoff, ...
    strjoin(arrayfun(@num2str, res.pre.notches, 'UniformOutput', false), '/'), res.pre.lpCutoff));

%% 3. Annotated strip
ax3 = subplot(4,3,[4 5]);
y = res.ecg;
plot(t(win), y(win), 'Color', C.ecg, 'LineWidth', 1); hold on
mk = {'Ppk','P','^'; 'Q','Q','v'; 'R','R','o'; 'S','S','v'; 'Tpk','T','^'};
h = []; lab = {};
for m = 1:size(mk,1)
    idx = fid.(mk{m,1}); idx = idx(~isnan(idx));
    idx = idx(t(idx) >= t0 & t(idx) <= t0 + dur);
    if ~isempty(idx)
        h = [h, plot(t(idx), y(idx), mk{m,3}, 'Color', C.(mk{m,2}), ...
            'MarkerFaceColor', C.(mk{m,2}), 'MarkerSize', 5)]; %#ok<AGROW>
        lab{end+1} = mk{m,2}; %#ok<AGROW>
    end
end
yl = ylim; yl(2) = yl(2) + 0.2*diff(yl); ylim(yl);
for b = find(F.beatType(:)' ~= 'N')
    tb = fid.R(b)/fs;
    if tb >= t0 && tb <= t0 + dur
        text(tb, yl(2) - 0.05*diff(yl), F.beatType(b), 'Color', C.V, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end
end
hold off; grid on; xlim([t0 t0+dur]);
ylabel(['ECG (' u ')']);
title('3. Detected waves (V = ventricular ectopic, S = supraventricular ectopic)');
if ~isempty(h), legend(h, lab, 'Location', 'northeast', 'Orientation', 'horizontal'); end
linkaxes([ax1 ax3], 'x');

%% 4. Average beat
ax4 = subplot(4,3,6);
% shrink slightly so the title clears panel 2's x-label and the x-label
% clears panel 6's title
p4 = get(ax4, 'Position');
set(ax4, 'Position', [p4(1), p4(2) + 0.015, p4(3), p4(4) - 0.035]);
if ~isempty(F.beats)
    tt = 1000*F.templateTime;
    xl = [tt(1) tt(end)];
    nShow = min(40, size(F.beats,2));
    nIdx = F.beatType(F.beatIdx) == 'N';
    if any(nIdx), avg = median(F.beats(:, nIdx), 2); else, avg = median(F.beats, 2); end
    % y-range: trace plus margins, and a reserved label strip at the top
    r = range_(avg);
    strip = 0.22*r;
    yl = [min(avg) - 0.12*r, max(avg) + 0.10*r + strip];
    yStrip = yl(2) - strip;                 % bottom of the label strip
    segs = {1000*[F.offPon F.offQRSon],    'PR',   [0.85 0.95 0.85], C.P;
            1000*[F.offQRSon F.offQRSoff], 'QRS',  [0.95 0.85 0.85], C.R;
            1000*[F.offQRSoff F.offTend],  'ST-T', [0.99 0.92 0.80], C.T};
    hold on
    % 1) interval shading (behind everything, clipped to the axes)
    for s = 1:size(segs,1)
        shade(clip_to(segs{s,1}, xl), [yl(1) yStrip], segs{s,3});
    end
    % 2) individual beats, 3) average beat
    plot(tt, F.beats(:, 1:nShow), 'Color', [0.80 0.80 0.80]);
    plot(tt, avg, 'Color', C.ecg, 'LineWidth', 2);
    % 4) label strip: white band covers any grey beats, then labels
    patch([xl(1) xl(2) xl(2) xl(1)], [yStrip yStrip yl(2) yl(2)], 'w', 'EdgeColor', 'none');
    plot(xl, [yStrip yStrip], '-', 'Color', [0.75 0.75 0.75]);
    for s = 1:size(segs,1)
        x = clip_to(segs{s,1}, xl);
        if ~any(isnan(x)) && x(2) > x(1)
            text(mean(x), yStrip + 0.5*strip, segs{s,2}, 'Color', segs{s,4}, ...
                'FontSize', 8, 'FontWeight', 'bold', 'Clipping', 'on', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        end
    end
    hold off; grid on; box on
    xlim(xl); ylim(yl);
    set(ax4, 'Layer', 'top');               % keep ticks/grid above patches
    yt = get(ax4, 'YTick');
    set(ax4, 'YTick', yt(yt <= yStrip));    % no tick labels inside the label strip
end
xlabel('Time from R (ms)'); ylabel(u);
title('4. Average beat (grey = individual beats)');

%% 5. Tachogram
subplot(4,3,[7 8]);
if ~isempty(F.rr)
    plot(F.rrTime, F.hrInst, '.-', 'Color', C.ecg); hold on
    ect = F.beatType(2:end) ~= 'N';
    if any(ect), plot(F.rrTime(ect), F.hrInst(ect), 'o', 'Color', C.V, 'MarkerFaceColor', C.V); end
    plot([0 t(end)], cfg.th.bradyBpm*[1 1], '--', 'Color', [0.4 0.4 0.4]);
    plot([0 t(end)], cfg.th.tachyBpm*[1 1], '--', 'Color', [0.4 0.4 0.4]);
    hold off; xlim([0 t(end)]);
end
grid on; xlabel('Time (s)'); ylabel('Heart rate (bpm)');
title('5. Beat-to-beat heart rate (dashed: 60 / 100 bpm limits, red: ectopic)');

%% 6. Poincare
subplot(4,3,9);
if numel(F.rr) >= 2
    rr = 1000*F.rr;
    plot(rr(1:end-1), rr(2:end), '.', 'Color', C.ecg, 'MarkerSize', 10); hold on
    lims = [min(rr) max(rr)] + [-50 50];
    plot(lims, lims, ':', 'Color', [0.5 0.5 0.5]); hold off
    axis([lims lims]); axis square
    stp = 100*max(1, ceil(diff(lims)/400));
    tk = stp*ceil(lims(1)/stp):stp:lims(2);
    set(gca, 'XTick', tk, 'YTick', tk);
end
grid on; xlabel('RR_n (ms)'); ylabel('RR_{n+1} (ms)');
title('6. Poincare plot (tight cluster = regular)');

%% 7. Text panel
[featLines, dxLines] = ecg_summary_text(res);
ax = subplot(4,3,[10 11 12]); axis(ax, 'off');
pos = get(ax, 'Position'); set(ax, 'Position', [pos(1) pos(2)-0.04 pos(3) pos(4)+0.04]);
text(0, 1, [{'MEASUREMENTS'}; featLines], 'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'FontName', 'Courier', 'FontSize', 8.5, 'Interpreter', 'none');
maxDx = 14;
if numel(dxLines) > maxDx, dxLines = [dxLines(1:maxDx); {'    ... (see report for full list)'}]; end
text(0.42, 1, [{'DIFFERENTIALS / FINDINGS (rule-based screen - NOT a medical diagnosis)'}; dxLines], ...
    'Units', 'normalized', 'VerticalAlignment', 'top', 'FontName', 'Courier', ...
    'FontSize', 8.5, 'Interpreter', 'none');

%% Footer (ownership + disclaimer)
foot = sprintf('%s  |  %s  |  Source: %s  |  Analysed %s  |  Educational use only - not for clinical decisions', ...
    cfg.authors, cfg.project, res.meta.name, res.analysedAt);
annotation(fig, 'textbox', [0 0 1 0.03], 'String', foot, 'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', 'FontSize', 8, 'Interpreter', 'none', 'Color', [0.3 0.3 0.3]);
annotation(fig, 'textbox', [0 0.965 1 0.035], 'String', ...
    sprintf('ECG Analysis - %s   |   %s, %.0f bpm', res.meta.name, res.rhythm, F.hrMedian), ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 13, ...
    'FontWeight', 'bold', 'Interpreter', 'none');
end

function shade(x, yl, col)
if any(isnan(x)) || x(2) <= x(1), return; end
patch([x(1) x(2) x(2) x(1)], [yl(1) yl(1) yl(2) yl(2)], col, 'EdgeColor', 'none');
end

function x = clip_to(x, xl)
%CLIP_TO Limit an [start end] interval to the axis range (NaN if outside).
if any(isnan(x)), return; end
x = [max(x(1), xl(1)), min(x(2), xl(2))];
if x(2) <= x(1), x = [NaN NaN]; end
end

function r = range_(v)
r = max(v) - min(v); if r == 0, r = 1; end
end
