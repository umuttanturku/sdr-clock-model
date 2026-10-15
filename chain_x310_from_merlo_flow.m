function ch = chain_x310_from_merlo_flow(mfDir, f_lo)
%CHAIN_X310_FROM_MERLO_FLOW  X310 + UBX-160 noise chain for sdr_clock_model_tworate.
%
%   CH = CHAIN_X310_FROM_MERLO_FLOW(MFDIR, F_LO) reads the datasheet-built stage
%   list from merlo_flow's x310_ubx160_params.m (in MFDIR, a read-only copy of
%   prettysick/merlo-flow) and converts it to this model's chain format:
%
%     10 MHz TCXO -PLL1-> 96 MHz VCXO -PLL2-> 2400 MHz -/48-> 50 MHz -MAX2871-> F_LO
%     SYS clock = PLL2 output / 12 = 200 MHz
%
%   Stage values (LMK04816, CVHD-950-class VCXO, MAX2871, UHD settings) and the
%   three constants fitted to Ettus' measured UBX phase noise are merlo_flow's;
%   see its datasheets/REFERENCES.md. Nothing in MFDIR is modified.
%
%   Mapping (both models use the same type-II loop):
%     in-band (PFD/CP/divider, output-referred) -> Sinb = 10^(excess/10) * inband(f)
%     open-loop VCO b3/f^3 + b2/f^2 + b1/f + b0 -> Svco
%     white output floor                         -> Sfloor

if nargin < 1 || isempty(mfDir), pths = clockmodel_paths(); mfDir = pths.mf; end
if nargin < 2 || isempty(f_lo),  f_lo  = 2.1e9; end
assert(isfile(fullfile(mfDir, 'x310_ubx160_params.m')), ...
    'x310_ubx160_params.m not found in %s', mfDir);

oldPath = path;  restore = onCleanup(@() path(oldPath));
addpath(mfDir);
hw = x310_ubx160_params(f_lo);

for i = 1:numel(hw.stages)
    s = hw.stages(i);
    if strcmp(s.type, 'div')
        st(i) = struct('name', s.name, 'type', 'div', 'kappa', s.kappa, 'fn', [], 'zeta', [], ...
                       'Svco', [], 'Sinb', [], 'Sfloor', 0);                    %#ok<AGROW>
    else
        v = s.vco;
        if ~isfield(v, 'b1'), v.b1 = 0; end
        if ~isfield(v, 'b3'), v.b3 = 0; end
        Svco = @(af) v.b3*af.^-3 + v.b2*af.^-2 + v.b1*af.^-1 + v.b0;
        g    = 10^(s.excess_dB/10);
        inb  = s.inband;
        Sinb = @(af) g*inb(af);
        st(i) = struct('name', s.name, 'type', 'pll', 'kappa', s.kappa, 'fn', s.loop.fn, ...
                       'zeta', s.loop.zeta, 'Svco', Svco, 'Sinb', Sinb, 'Sfloor', s.floor); %#ok<AGROW>
    end
end
ch = struct('name', 'X310 + UBX-160 (merlo_flow x310_ubx160_params)', 'stages', st, ...
            'i_sys', hw.i_sys, 'sys_div', hw.sys_div);
ch.measured = hw.measured;      % Ettus UBX TX phase noise (f_c, f, L)
ch.fit      = hw.fit;
end
