function res = ecg_run_source(source, cfg)
%ECG_RUN_SOURCE Load (or synthesise) one recording and analyse it.
%   res = ECG_RUN_SOURCE('recording.csv', cfg)
%   res = ECG_RUN_SOURCE('synthetic:pvc', cfg)   - built-in test signal
%         (any ecg_synth type; realistic noise is added)

if strncmpi(source, 'synthetic', 9)
    parts = regexp(source, ':', 'split');
    type = 'normal'; if numel(parts) > 1, type = parts{2}; end
    fs = 500;
    noise = struct('baseline', 0.3, 'mains', 0.1, 'emg', 0.02, 'motion', 0);
    x = ecg_synth(type, 30, fs, noise);
    meta = struct('source', source, 'name', ['synthetic_' type], 'notes', {{}});
else
    [x, fs, meta] = ecg_load(source, cfg);
end
res = ecg_analyse(x, fs, cfg, meta);
end
