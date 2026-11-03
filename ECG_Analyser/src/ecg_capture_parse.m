function [out, rest] = ecg_capture_parse(buf)
%ECG_CAPTURE_PARSE Split raw serial text from the Nano ESP32 into valid lines.
%   [out, rest] = ECG_CAPTURE_PARSE(buf)
%   buf  : text received so far (may end part-way through a line)
%   rest : the unfinished last line, to be prepended to the next chunk
%   out.lines : cell of lines to write to the CSV (data lines and '!')
%   out.t, out.v : time (us) and voltage (V) of the data lines
%   out.nOff  : number of '!' leads-off lines
%   out.nJunk : number of discarded lines (header, partial or corrupt)
%
%   Kept as a separate function so the parsing can be unit-tested without
%   hardware (see tests/run_tests.m, T29).

out = struct('lines', {{}}, 't', zeros(0,1), 'v', zeros(0,1), 'nOff', 0, 'nJunk', 0);
parts = regexp(buf, '\n', 'split');
rest = parts{end};                       % incomplete line (empty if buf ended in \n)
parts = strtrim(parts(1:end-1));         % strtrim also removes the \r of \r\n
parts = parts(~cellfun(@isempty, parts));
if isempty(parts), return; end

isData = ~cellfun(@isempty, regexp(parts, '^\d+,-?\d+(\.\d+)?$', 'once'));
isOff  = strcmp(parts, '!');
out.lines = parts(isData | isOff);
out.nOff  = sum(isOff);
out.nJunk = sum(~isData & ~isOff);
if any(isData)
    vals = sscanf(strjoin(strrep(parts(isData), ',', ' '), ' '), '%f');
    vals = reshape(vals, 2, [])';
    out.t = vals(:,1);
    out.v = vals(:,2);
end
end
