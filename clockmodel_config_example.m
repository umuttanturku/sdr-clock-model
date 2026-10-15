function c = clockmodel_config_example()
%CLOCKMODEL_CONFIG_EXAMPLE  Template for the per-machine path settings.
%
%   Copy this file to clockmodel_config.m (which git ignores), rename the
%   function to clockmodel_config, and edit the paths. Leave a field out to use
%   the default from clockmodel_paths.m. The environment variables
%   CLOCKMODEL_DATA and MERLO_FLOW_DIR override both fields.

c.data = 'D:\ClockModelData';                                 % model outputs
c.mf   = 'D:\ClockModelData\merlo-flow-main\merlo_flow';      % read-only merlo_flow copy
end
