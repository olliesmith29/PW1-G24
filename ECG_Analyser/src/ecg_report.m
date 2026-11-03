function files = ecg_report(res, cfg, fig)
%ECG_REPORT Save the analysis: text report, beat-by-beat CSV and figure PNG.
%   files = ECG_REPORT(res, cfg, fig)   (fig optional)
%   Files are named <source>_report.txt, <source>_beats.csv and
%   <source>_dashboard.png in cfg.outputDir.

outDir = cfg.outputDir;
if ~exist(outDir, 'dir'), mkdir(outDir); end
base = regexprep(res.meta.name, '[^\w\-]', '_');
files = struct();

%% Text report
files.report = fullfile(outDir, [base '_report.txt']);
fidw = fopen(files.report, 'w');
[featLines, ~] = ecg_summary_text(res);
fprintf(fidw, 'ECG ANALYSIS REPORT\n%s\n%s\nGenerated: %s\n', cfg.project, cfg.authors, res.analysedAt);
fprintf(fidw, '%s\n', repmat('=', 1, 72));
fprintf(fidw, 'Units: %s\n', res.units.description);
fprintf(fidw, 'Filters: HP %.2f Hz, notch %s Hz, LP %.0f Hz (zero-phase)\n', cfg.hpCutoff, ...
    num2str(res.pre.notches), res.pre.lpCutoff);
fprintf(fidw, 'Mains power share: %.1f%% before -> %.2f%% after filtering\n\n', ...
    100*res.pre.mainsFracRaw, 100*res.pre.mainsFracFilt);
fprintf(fidw, 'MEASUREMENTS\n');
fprintf(fidw, '  %s\n', featLines{:});
fprintf(fidw, '\nDIFFERENTIALS / FINDINGS\n');
for k = 1:numel(res.dx)
    d = res.dx(k);
    fprintf(fidw, '  %d. [%s] %s\n     Evidence: %s\n     Consider: %s\n', k, d.likelihood, d.finding, d.evidence, d.causes);
end
if ~isempty(res.warnings)
    fprintf(fidw, '\nWARNINGS\n');
    fprintf(fidw, '  - %s\n', res.warnings{:});
end
fprintf(fidw, ['\nDISCLAIMER: Automated, rule-based analysis of a single-lead ECG for ' ...
    'education (EE22005).\nIt is not a medical device and must not be used for diagnosis ' ...
    'or treatment decisions.\n']);
fclose(fidw);

%% Beat table
files.beats = fullfile(outDir, [base '_beats.csv']);
f = res.fid; fs = res.fs; n = numel(f.R);
fidw = fopen(files.beats, 'w');
fprintf(fidw, 'beat,type,R_time_s,RR_prev_ms,P_present,PR_ms,QRS_ms,QT_ms,R_amp,ST_level,T_amp,template_corr\n');
for i = 1:n
    bt = 'N'; if i <= numel(res.F.beatType), bt = res.F.beatType(i); end
    c = NaN; if i <= numel(res.F.corr), c = res.F.corr(i); end
    fprintf(fidw, '%d,%s,%.4f,%.0f,%d,%.0f,%.0f,%.0f,%.3f,%.3f,%.3f,%.3f\n', i, bt, f.R(i)/fs, ...
        1000*f.RRprev(i), f.Pvalid(i), 1000*f.PR(i), 1000*f.QRSd(i), 1000*f.QT(i), ...
        f.Ramp(i), f.ST(i), f.Tamp(i), c);
end
fclose(fidw);

%% Figure
if nargin >= 3 && ~isempty(fig) && ishandle(fig)
    files.figure = fullfile(outDir, [base '_dashboard.png']);
    set(fig, 'PaperPositionMode', 'auto');
    print(fig, files.figure, '-dpng', '-r150');
end
end
