function p = clockmodel_paths()
%CLOCKMODEL_PATHS  Output folder and merlo_flow location for this machine.
%
%   P = CLOCKMODEL_PATHS() returns a struct with
%     P.data  folder for model outputs (.mat, .fig, comparison\, studies\)
%     P.mf    folder of the read-only merlo_flow copy (contains x310_ubx160_params.m)
%
%   Each path is taken from the first of these that is set:
%     1  environment variables CLOCKMODEL_DATA and MERLO_FLOW_DIR
%     2  clockmodel_config.m in this folder (not committed; copy
%        clockmodel_config_example.m and edit it)
%     3  defaults: <repo>\output and <data>\merlo-flow-main\merlo_flow
%
%   Large outputs should not go to a synced or nearly full drive, so set one of
%   the first two on any machine where <repo>\output is a poor place for them.

here = fileparts(mfilename('fullpath'));
p = struct('data', '', 'mf', '');

if isfile(fullfile(here, 'clockmodel_config.m'))
    c = clockmodel_config();
    if isfield(c, 'data'), p.data = c.data; end
    if isfield(c, 'mf'),   p.mf   = c.mf;   end
end

if ~isempty(getenv('CLOCKMODEL_DATA')), p.data = getenv('CLOCKMODEL_DATA'); end
if ~isempty(getenv('MERLO_FLOW_DIR')),  p.mf   = getenv('MERLO_FLOW_DIR');  end

if isempty(p.data), p.data = fullfile(here, 'output'); end
if isempty(p.mf),   p.mf   = fullfile(p.data, 'merlo-flow-main', 'merlo_flow'); end
end
