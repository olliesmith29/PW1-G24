function summary = ecg_batch(sources, cfg)
%ECG_BATCH Analyse a range of ECG signals and tabulate the results.
%   summary = ECG_BATCH(folder, cfg)      every .csv/.txt/.dat/.mat in folder
%   summary = ECG_BATCH({'a.csv','synthetic:af',...}, cfg)
%   Each recording gets its own dashboard/report; a comparison table is
%   written to <cfg.outputDir>/batch_summary.csv and printed.
%   A failure on one file is logged and the batch carries on.

if nargin < 2 || isempty(cfg), cfg = ecg_config(); end
if ischar(sources)
    if exist(sources, 'dir')
        d = [dir(fullfile(sources, '*.csv')); dir(fullfile(sources, '*.txt')); ...
             dir(fullfile(sources, '*.dat')); dir(fullfile(sources, '*.mat'))];
        sources = cellfun(@(n) fullfile(sources, n), {d.name}, 'UniformOutput', false);
    else
        sources = {sources};
    end
end
summary = struct('source', {}, 'status', {}, 'beats', {}, 'hr', {}, 'pr_ms', {}, ...
    'qrs_ms', {}, 'qtc_ms', {}, 'quality', {}, 'rhythm', {}, 'top_finding', {});
for k = 1:numel(sources)
    s = sources{k};
    row = struct('source', s, 'status', 'OK', 'beats', NaN, 'hr', NaN, 'pr_ms', NaN, ...
        'qrs_ms', NaN, 'qtc_ms', NaN, 'quality', '', 'rhythm', '', 'top_finding', '');
    try
        res = ecg_run_source(s, cfg);
        fig = [];
        if cfg.showPlots || cfg.saveOutputs, fig = ecg_plot(res, cfg); end
        if cfg.saveOutputs, ecg_report(res, cfg, fig); end
        if ~cfg.showPlots && ~isempty(fig), close(fig); end
        F = res.F;
        row.beats = F.nBeats; row.hr = F.hrMedian; row.pr_ms = 1000*F.PR;
        row.qrs_ms = 1000*F.QRSd; row.qtc_ms = 1000*F.QTcB; row.quality = F.quality;
        row.rhythm = res.rhythm;
        if ~isempty(res.dx), row.top_finding = res.dx(1).finding; end
    catch err
        row.status = ['FAILED: ' err.message];
    end
    summary(end+1) = row; %#ok<AGROW>
end

%% Print and save table
fprintf('\n%-28s %5s %5s %5s %5s %5s %-10s %s\n', 'Source', 'Beats', 'HR', 'PR', 'QRS', 'QTc', 'Quality', 'Top finding');
for k = 1:numel(summary)
    r = summary(k);
    [~, nm, ex] = fileparts(r.source);
    if strcmp(r.status, 'OK')
        fprintf('%-28s %5d %5.0f %5.0f %5.0f %5.0f %-10s %s\n', [nm ex], r.beats, r.hr, r.pr_ms, r.qrs_ms, r.qtc_ms, r.quality, r.top_finding);
    else
        fprintf('%-28s %s\n', [nm ex], r.status);
    end
end
if cfg.saveOutputs
    if ~exist(cfg.outputDir, 'dir'), mkdir(cfg.outputDir); end
    fn = fullfile(cfg.outputDir, 'batch_summary.csv');
    fw = fopen(fn, 'w');
    fprintf(fw, 'source,status,beats,hr_bpm,pr_ms,qrs_ms,qtc_bazett_ms,quality,rhythm,top_finding\n');
    for k = 1:numel(summary)
        r = summary(k);
        fprintf(fw, '"%s","%s",%g,%.1f,%.0f,%.0f,%.0f,%s,"%s","%s"\n', r.source, r.status, r.beats, ...
            r.hr, r.pr_ms, r.qrs_ms, r.qtc_ms, r.quality, r.rhythm, r.top_finding);
    end
    fclose(fw);
    fprintf('\nSummary saved to %s\n', fn);
end
end
