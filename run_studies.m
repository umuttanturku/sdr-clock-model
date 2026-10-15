%% run_studies.m
% Follow-up studies to the merlo_flow comparison (see the comparison doc):
%   1  TWTT time error from the ToA CRLB (Eqs. 22, 24), checked against
%      merlo_flow's own CRLB code and its measured 26.4 ps at 27 dB
%   2  X310 + UBX-160 noise chain (datasheet-fitted, from merlo_flow's
%      parameters): analytic check vs. merlo_flow and Ettus' measurement, and a
%      simulated-PSD check through the two-rate generator
%   3  SNR sweep (paper Fig. 11 axis): time error, phase and coherent gain,
%      at the CRLB and with the estimator excess that matches the paper
%   4  Pulse timing across the 44 ms epoch
% merlo_flow is used read-only from the folder given by clockmodel_paths (.mf).
% Outputs: <data>\studies
clear; clc; close all;
here   = fileparts(mfilename('fullpath'));
addpath(here);
pths   = clockmodel_paths();
outDir = fullfile(pths.data, 'studies');
mf     = pths.mf;
assert(isfolder(mf), 'merlo_flow not found in %s (set MERLO_FLOW_DIR)', mf);
if ~isfolder(outDir), mkdir(outDir); end
logFile = fullfile(outDir, 'studies_log.txt');
diary off; if isfile(logFile), delete(logFile); end
diary(logFile);
fprintf('Studies run %s, MATLAB %s\n', char(datetime('now')), version);

T_run = 20;                        % s per simulation run (~450 epochs)
quiet = struct('makeFigures', false, 'saveResults', false, 'verbose', false, 'T_req', T_run);

%% 1) CRLB ------------------------------------------------------------------
fprintf('\n== 1. TWTT time error from the CRLB ==\n');
p0 = sdr_clock_model_tworate(struct('paramsOnly', true, 'verbose', false));
c  = p0.crlb;
fprintf('PTT %g MHz, %g us at %g MSa/s: %d samples\n', p0.opts.ptt.beta/1e6, ...
    p0.opts.ptt.tau_pd*1e6, p0.opts.ptt.fs/1e6, c.N);
fprintf('Mine (analytic, zeta_f = pi beta): one-way %.2f ps, two-way %.2f ps at 27 dB\n', ...
    1e12*c.sig_1way, 1e12*c.sig_2way);
oldPath = path; addpath(fullfile(mf, 'deps'));
[s_bb, ~] = waveform_ptt(p0.opts.ptt.tau_pd, p0.opts.ptt.beta, p0.opts.ptt.fs);
sigma2 = mean(abs(s_bb).^2)/10^(27/10);
v1mf = crlb_toa(s_bb, p0.opts.ptt.fs, sigma2);
path(oldPath);
fprintf('merlo_flow crlb_toa (numeric, rect edges included): one-way %.2f ps, two-way %.2f ps\n', ...
    1e12*sqrt(v1mf), 1e12*sqrt(v1mf/2));
fprintf('merlo_flow measured at 27 dB (run_flow, 40 epochs): 26.4 ps -> %.2fx my bound\n', ...
    26.4e-12/c.sig_2way);
paper_ps = 65;                     % paper, ~60-70 ps at 24-27 dB
excess_paper = paper_ps*1e-12/c.sig_2way;
fprintf('Excess that reproduces the paper''s ~%d ps at 27 dB: %.2f\n', paper_ps, excess_paper);

%% 2) X310 + UBX-160 chain ---------------------------------------------------
fprintf('\n== 2. X310 + UBX-160 chain ==\n');
chX = chain_x310_from_merlo_flow(mf, 2.1e9);
pX  = sdr_clock_model_tworate(struct('paramsOnly', true, 'verbose', false, 'chain', chX));
fprintf('SYS %.1f MHz, LO %.3f GHz, %d stages\n', pX.f0_sys/1e6, pX.f0_lo/1e9, numel(chX.stages));
% analytic LO vs. merlo_flow's own pll_chain_psd (same oscillator for the check)
fchk = logspace(3, 6, 31);
addpath(mf); hw = x310_ubx160_params(2.1e9);
Sref_mine = pX.analytic_psd(fchk);  Sosc_mine = Sref_mine(:,1).';
Smf = pll_chain_psd(fchk, Sosc_mine, hw.stages);  path(oldPath);
d_lo = 10*log10(Sref_mine(:,3).'./Smf{end});
fprintf('LO PSD, mine vs merlo_flow pll_chain_psd (same reference), 1 kHz-1 MHz: max |diff| %.3f dB\n', max(abs(d_lo)));
mL  = chX.measured.L - 20*log10(chX.measured.f_c/2.1e9);
keep = chX.measured.f <= 1e6;
Lx  = 10*log10(pX.analytic_psd(chX.measured.f(keep))*[0;0;1]/2).';
Ld  = 10*log10(p0.analytic_psd(chX.measured.f(keep))*[0;0;1]/2).';
fprintf('vs Ettus measured (scaled to 2.1 GHz), 1 kHz-1 MHz: X310 chain RMS gap %.2f dB, default chain %.2f dB\n', ...
    rms(Lx - mL(keep)), rms(Ld - mL(keep)));
% two-rate generator through the 4-stage chain
r2 = sdr_clock_model_tworate(setfield(setfield(quiet, 'chain', chX), 'verbose', true)); %#ok<SFLD>
fprintf('Generator check (X310 chain), mean sim/model 1 Hz-1 MHz [osc sys lo]: %+.2f %+.2f %+.2f dB\n', r2.psd_err_dB);
r2d = sdr_clock_model_tworate(setfield(quiet, 'verbose', true)); %#ok<SFLD>
fprintf('Generator check (default chain),  mean sim/model 1 Hz-1 MHz [osc sys lo]: %+.2f %+.2f %+.2f dB\n', r2d.psd_err_dB);

%% 3) SNR sweep ---------------------------------------------------------------
fprintf('\n== 3. SNR sweep (X310 chain, pulse 1 ms after TWTT) ==\n');
snr = 6:3:33;  ex = [1 excess_paper];
S3 = table();
for e = ex
    for s = snr
        o = quiet; o.chain = chX; o.snr_dB = s; o.crlb_excess = e; o.seed = 100 + s;
        r = sdr_clock_model_tworate(o);
        S3 = [S3; table(e, s, 1e12*r.sigT, 1e12*r.time_std, r.phase_std_deg, 1e9*r.df_std, ...
            r.Gc_median, r.Gc_p5, 'VariableNames', {'excess', 'snr_dB', 'sigT_ps', 'time_std_ps', ...
            'phase_std_deg', 'df_std_ppb', 'Gc_median', 'Gc_p5'})];                   %#ok<AGROW>
        fprintf('  excess %.2f, %2d dB: sigT %6.1f ps, phase %5.1f deg, df %5.2f ppb, Gc median %.4f (p5 %.4f)\n', ...
            e, s, 1e12*r.sigT, r.phase_std_deg, 1e9*r.df_std, r.Gc_median, r.Gc_p5);
    end
end
writetable(S3, fullfile(outDir, 'snr_sweep.csv'));

%% 4) Pulse timing across the epoch ------------------------------------------
fprintf('\n== 4. Pulse timing across the 44 ms epoch (27 dB) ==\n');
tbf = [0.1 1 2 5 10 20 30 40]*1e-3;
chains = {chX, []};  cname = {'x310', 'default'};
S4 = table();
for ci = 1:2
    for e = ex
        for t = tbf
            o = quiet; o.chain = chains{ci}; o.crlb_excess = e; o.t_bf = t; o.seed = 200 + round(t*1e4);
            r = sdr_clock_model_tworate(o);
            S4 = [S4; table(string(cname{ci}), e, 1e3*t, r.phase_std_deg, r.Gc_median, r.Gc_p5, ...
                'VariableNames', {'chain', 'excess', 't_bf_ms', 'phase_std_deg', 'Gc_median', 'Gc_p5'})]; %#ok<AGROW>
            fprintf('  %-7s excess %.2f, pulse at %4.1f ms: phase %5.1f deg, Gc median %.4f (p5 %.4f)\n', ...
                cname{ci}, e, 1e3*t, r.phase_std_deg, r.Gc_median, r.Gc_p5);
        end
    end
end
writetable(S4, fullfile(outDir, 'pulse_timing.csv'));

%% 5) Reference oscillator: guessed table vs. sourced TCXO h-coefficients ----
% Typical TCXO: h0 = 9.4e-20, h-2 = 3.8e-21 (Kassas, Ghadiok, Humphreys, ION
% GNSS+ 2014, Table I); that source drops the flicker term h-1 = 1.8e-19 given by
% Curran et al. 2012, Table I (after Van Dierendonck 1984). A white PM floor of
% -155 dBc/Hz, as in the guessed table, is added to both.
fprintf('\n== 5. Reference oscillator profile (X310 chain) ==\n');
fm = logspace(-2, 6, 41);
oscs = {[], osc_from_h(fm, 9.4e-20, 0, 3.8e-21, -155), osc_from_h(fm, 9.4e-20, 1.8e-19, 3.8e-21, -155)};
oname = {'guess', 'h 2-term', 'h 3-term'};
tau_a = [1e-3 1e-2 0.1 1];
for oi = 1:3
    o = struct('paramsOnly', true, 'verbose', false, 'chain', chX);
    if ~isempty(oscs{oi}), o.osc = oscs{oi}; end
    p = sdr_clock_model_tworate(o);
    fprintf('  %-8s L(f) at 1, 10, 100, 1k Hz: %s dBc/Hz;  ADEV at %s s: %s\n', oname{oi}, ...
        mat2str(round(10*log10(p.analytic_psd([1 10 100 1e3])*[1;0;0]/2).', 1)), mat2str(tau_a), ...
        mat2str(adev_from_S(@(f) p.analytic_psd(f)*[1;0;0], p.opts.osc.f0, tau_a), 2));
end
% clock-only contribution (sigT = 0), then with TWTT error at 27 dB
tb5 = [1 5 20 40]*1e-3;
S5 = table();
for oi = 1:3
    for e = [0 1 excess_paper]
        for t = tb5
            if e > 0 && t ~= 1e-3, continue; end
            o = quiet; o.chain = chX; o.t_bf = t; o.seed = 300 + round(t*1e4);
            if ~isempty(oscs{oi}), o.osc = oscs{oi}; end
            if e == 0, o.timing = 'fixed'; o.sigT = 0; else, o.crlb_excess = e; end
            r = sdr_clock_model_tworate(o);
            S5 = [S5; table(string(oname{oi}), e, 1e3*t, r.phase_std_deg, 1e9*r.df_std, r.Gc_median, ...
                r.Gc_p5, max(abs(r.psd_err_dB)), 'VariableNames', {'osc', 'excess', 't_bf_ms', ...
                'phase_std_deg', 'df_std_ppb', 'Gc_median', 'Gc_p5', 'psd_err_dB'})];  %#ok<AGROW>
            fprintf('  %-8s excess %.2f, pulse at %4.1f ms: phase %5.2f deg, df %5.3f ppb, Gc median %.4f (p5 %.4f), PSD err %.2f dB\n', ...
                oname{oi}, e, 1e3*t, r.phase_std_deg, 1e9*r.df_std, r.Gc_median, r.Gc_p5, max(abs(r.psd_err_dB)));
        end
    end
end
writetable(S5, fullfile(outDir, 'oscillator.csv'));

save(fullfile(outDir, 'studies_results.mat'), 'c', 'v1mf', 'excess_paper', 'd_lo', 'Lx', 'Ld', 'mL', ...
    'S3', 'S4', 'S5', 'snr', 'tbf');
fprintf('\nOutputs in %s\n', outDir);
diary off;

function osc = osc_from_h(fm, h0, hm1, hm2, Lfloor)
% L(f) table at 10 MHz from the power-law coefficients of S_y(f) = h0 + h-1/f + h-2/f^2
% plus a white PM floor: S_phi = (f0/f)^2 S_y, L = S_phi/2.
osc.f0 = 10e6;  osc.fm = fm;
osc.L  = 10*log10((osc.f0./fm).^2.*(h0 + hm1./fm + hm2./fm.^2)/2 + 10^(Lfloor/10));
end

function a = adev_from_S(Sphi, f0, tau)
% Allan deviation from a one-sided phase PSD (rad^2/Hz) at carrier f0, up to 2 MHz.
% sin^4 is replaced by its mean 3/8 where it oscillates faster than the grid.
f  = logspace(-5, log10(2e6), 2e4).';
Sy = (f/f0).^2.*Sphi(f);
a  = zeros(size(tau));
for i = 1:numel(tau)
    x = pi*tau(i)*f;  s4 = sin(x).^4;  s4(x > 20) = 3/8;
    a(i) = sqrt(2*trapz(f, Sy.*s4./x.^2));
end
end