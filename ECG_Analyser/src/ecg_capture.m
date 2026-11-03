function file = ecg_capture(port, durationS, outDir, showLive)
%ECG_CAPTURE Record ECG from the Nano ESP32 (AD8232) over USB and save as CSV.
%   file = ECG_CAPTURE()                         auto-detect port, 30 s
%   file = ECG_CAPTURE('COM5', 60)               chosen port, 60 s
%   file = ECG_CAPTURE(port, durationS, outDir, showLive)
%
%   Reads the "time_us,ecg_V" lines sent by Firmware/ECG_NanoESP32 and
%   writes them to <outDir>/ECG_yyyymmdd_HHMMSS.csv, which ecg_load /
%   ECG_Analyser.m read directly. Leads-off markers ('!') are kept so the
%   analyser can report them.
%   A live 5-second trace is shown so you can check the electrodes;
%   closing that window stops the recording early. Ctrl+C also stops it
%   safely (the data recorded so far is kept).
%
%   Requires MATLAB R2019b or later (serialport). Close the Arduino IDE
%   Serial Monitor first - only one program can open the port.

if nargin < 1, port = ''; end
if nargin < 2 || isempty(durationS), durationS = 30; end
if nargin < 3 || isempty(outDir), outDir = fullfile(pwd, 'recordings'); end
if nargin < 4 || isempty(showLive), showLive = true; end
if isempty(which('serialport'))
    error('ECG:noSerial', 'Live capture needs MATLAB R2019b or later (serialport).');
end

%% Choose the port
if isempty(port)
    ports = serialportlist("available");
    if isempty(ports)
        error('ECG:noPort', ['No serial port found. Plug in the Nano ESP32, close the ' ...
            'Arduino Serial Monitor, and try again.']);
    elseif numel(ports) > 1
        error('ECG:choosePort', ['Several ports available (%s). Set cfg.capturePort ' ...
            'to the one shown in Arduino IDE > Tools > Port.'], strjoin(ports, ', '));
    end
    port = char(ports(1));
end

%% Open port and output file
s = serialport(port, 115200);
configureTerminator(s, "LF");
s.Timeout = 2;
if ~exist(outDir, 'dir'), mkdir(outDir); end
file = fullfile(outDir, ['ECG_' datestr(now, 'yyyymmdd_HHMMSS') '.csv']);
fid = fopen(file, 'w');
if fid < 0
    clear s
    error('ECG:fileWrite', 'Cannot create %s', file);
end
cleaner = onCleanup(@() close_all(fid, s)); %#ok<NASGU>
fprintf(fid, 'time_us,ecg_V\n');

%% Synchronise: drop the partial first line; resume if the board was paused
flush(s);
if isempty(read_line(s))
    write(s, 'p', 'char');                % sketch may have been paused with 'p'
    if isempty(read_line(s))
        error('ECG:noData', ['No data from %s. Check the firmware is uploaded ' ...
            '(ECG_NanoESP32.ino) and that this is the right port.'], port);
    end
end

%% Live view
fig = []; hLine = []; hTitle = [];
if showLive
    fig = figure('Name', 'ECG capture - close to stop', 'NumberTitle', 'off', 'Color', 'w');
    hLine = plot(NaN, NaN, 'Color', [0.10 0.20 0.45]);
    grid on; xlabel('Time (s)'); ylabel('AD8232 output (V)');
    hTitle = title('Starting...');
end

%% Record
fprintf('Recording %d s from %s -> %s\n', durationS, port, file);
buf = ''; nData = 0; nOff = 0; nJunk = 0;
liveT = zeros(0,1); liveV = zeros(0,1);
tStart = tic; lastDraw = 0; lastOff = -inf;
while toc(tStart) < durationS
    if showLive && ~ishghandle(fig)
        fprintf('Live window closed - stopping early.\n');
        break
    end
    n = s.NumBytesAvailable;
    if n == 0
        pause(0.005);
        continue
    end
    [p, buf] = ecg_capture_parse([buf, read(s, n, 'char')]);
    if ~isempty(p.lines)
        fprintf(fid, '%s\n', p.lines{:});
    end
    nData = nData + numel(p.t); nOff = nOff + p.nOff; nJunk = nJunk + p.nJunk;
    if p.nOff > 0, lastOff = toc(tStart); end

    if showLive && ~isempty(p.t)
        liveT = [liveT; p.t/1e6]; liveV = [liveV; p.v]; %#ok<AGROW>
        keep = liveT >= liveT(end) - 5;
        liveT = liveT(keep); liveV = liveV(keep);
    end
    if showLive && toc(tStart) - lastDraw > 0.2 && ishghandle(fig)
        set(hLine, 'XData', liveT, 'YData', liveV);
        if ~isempty(liveT), xlim([liveT(end) - 5, liveT(end) + 0.01]); end
        if toc(tStart) - lastOff < 1
            set(hTitle, 'String', sprintf('%.0f / %d s   LEADS OFF - check electrodes', toc(tStart), durationS), 'Color', [0.85 0.1 0.1]);
        else
            set(hTitle, 'String', sprintf('%.0f / %d s   recording', toc(tStart), durationS), 'Color', [0 0 0]);
        end
        drawnow limitrate
        lastDraw = toc(tStart);
    end
end

%% Summary
fprintf('Saved %s\n  %d samples (~%.0f Hz), %d leads-off markers, %d discarded lines.\n', ...
    file, nData, nData/max(toc(tStart), eps), nOff, nJunk);
if nData == 0
    warning('ECG:noData', 'No ECG samples were recorded.');
end
if showLive && ishghandle(fig), close(fig); end
end

%% -----------------------------------------------------------------------
function L = read_line(s)
L = '';
try
    L = readline(s);
catch
end
if isempty(L) || (isstring(L) && ismissing(L)), L = ''; end
end

function close_all(fid, s)
try, fclose(fid); catch, end
try, delete(s); catch, end
end
