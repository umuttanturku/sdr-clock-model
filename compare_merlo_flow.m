%% compare_merlo_flow.m
% Comparative analysis: my clock model (sdr_clock_model_tworate.m) vs. the
% merlo_flow simulator (prettysick/merlo-flow, read-only copy) vs. the paper
% (Merlo et al., IEEE TMTT 74(2), 2026).
%
% merlo_flow runs read-only from the folder given by clockmodel_paths (.mf). If
% that folder is missing, merlo-flow-main.zip from this folder is extracted
% there once; the zip is not modified. All outputs go to <data>\comparison.
%
% Parts
%   A  Noise models, analytic: reference oscillator L(f) and ADEV, SYS and LO
%      L(f), integrated LO jitter, internode LO phase wander vs. latency
%   B  merlo_flow end-to-end runs (run_flow) for both presets
%   C  my model under four settings, from "as first built" to "matched to
%      merlo_flow" and "paper-level time error"
%   D  figures + summary tables
clear; clc; close all;

here   = fileparts(mfilename('fullpath'));
pths   = clockmodel_paths();
outDir = fullfile(pths.data, 'comparison');
mf     = pths.mf;
if ~isfolder(outDir), mkdir(outDir); end
if ~isfolder(mf), unzip(fullfile(here, 'merlo-flow-main.zip'), fileparts(fileparts(mf))); end
assert(isfolder(mf), 'merlo_flow not found in %s (set MERLO_FLOW_DIR)', mf);
addpath(here, mf, fullfile(mf, 'deps'));
logFile = fullfile(outDir, 'comparison_log.txt');
diary off;
if isfile(logFile), delete(logFile); end
diary(logFile);
fprintf('Comparison run %s, MATLAB %s\n', char(datetime('now')), version);

f_lo = 2.1e9;  f_bf = 1.0e9;  f_osc = 10e6;
kb2  = (f_bf/f_lo)^2;                       % LO phase PSD -> bf carrier

%% A) Noise models ------------------------------------------------------------
f = logspace(-3, log10(2e6), 4000);

% --- mine
me = sdr_clock_model_tworate(struct('paramsOnly', true, 'verbose', false));
S  = me.analytic_psd(f);
mine.osc = S(:,1).';  mine.sys = S(:,2).';  mine.lo = S(:,3).';

% --- merlo_flow, preset merlo2026 (two pll_stage calls, Node.enablePllNoise)
c1 = flow_config('merlo2026');
h  = c1.osc.h;
Sy_mf = @(ff) h.p2*ff.^2 + h.p1*ff + h.z0 + h.m1./ff + h.m2./ff.^2;
mfo   = f_osc^2*Sy_mf(f)./f.^2;              % S_phi = f0^2 S_y / f^2
f_sys = c1.chain.f_osc*c1.chain.kappa_sys;
st = struct('name', {'SYS', 'LO'}, 'type', 'pll', 'f_out', {f_sys, f_lo}, ...
    'kappa', {c1.chain.kappa_sys, c1.chain.kappa_lo}, 'loop', c1.pll.loop, ...
    'vco', {c1.pll.vco_at(f_sys), c1.pll.vco_at(f_lo)}, 'inband', @(ff) zeros(size(ff)), ...
    'excess_dB', 0, 'floor', {c1.pll.S_phi_0_at(f_sys), c1.pll.S_phi_0_at(f_lo)}, 'src', '');
Sm = pll_chain_psd(f, mfo, st);
mf26.osc = mfo;  mf26.sys = Sm{1};  mf26.lo = Sm{2};

% --- merlo_flow, preset x310_ubx160 (datasheet stage list)
c2 = flow_config('x310_ubx160');
hw = x310_ubx160_params(c2.chain.f_lo);
Sx = pll_chain_psd(f, mfo, hw.stages);
x310.osc = mfo;  x310.sys = Sx{hw.i_sys}/hw.sys_div^2;  x310.lo = Sx{end};
meas.f = hw.measured.f;
meas.L = hw.measured.L - 20*log10(hw.measured.f_c/f_lo);    % 2.4 -> 2.1 GHz

models = {mine, mf26, x310};
names  = {'This work', 'merlo\_flow merlo2026', 'merlo\_flow x310\_ubx160'};
namesP = {'this_work', 'mf_merlo2026', 'mf_x310_ubx160'};
Ldb    = @(Sp) 10*log10(Sp/2);

% L(f) at standard offsets
offs = [1 10 100 1e3 1e4 1e5 1e6];
fprintf('\n== A1. L(f) at standard offsets (dBc/Hz) ==\n');
for stg = {'osc', 'sys', 'lo'}
    fprintf('%s:\n', upper(stg{1}));
    fprintf('  %-26s', 'offset (Hz)'); fprintf('%9g', offs); fprintf('\n');
    for m = 1:3
        v = interp1(f, Ldb(models{m}.(stg{1})), offs);
        fprintf('  %-26s', strrep(names{m}, '\', '')); fprintf('%9.1f', v); fprintf('\n');
        Ltab.(stg{1})(m,:) = v;
    end
end
vm = interp1(f, Ldb(mine.lo), meas.f);  v26 = interp1(f, Ldb(mf26.lo), meas.f);  vx = interp1(f, Ldb(x310.lo), meas.f);
fprintf('LO vs Ettus UBX measured (scaled to 2.1 GHz), offsets %s Hz\n', mat2str(meas.f));
fprintf('  measured  : %s\n', mat2str(round(meas.L, 1)));
fprintf('  this work : %s   rms err %.1f dB\n', mat2str(round(vm, 1)), rms(vm - meas.L));
fprintf('  mf 2026   : %s   rms err %.1f dB\n', mat2str(round(v26, 1)), rms(v26 - meas.L));
fprintf('  mf x310   : %s   rms err %.1f dB\n', mat2str(round(vx, 1)), rms(vx - meas.L));
lo_rms_err = [rms(vm - meas.L), rms(v26 - meas.L), rms(vx - meas.L)];

% Integrated LO jitter (single node, at 2.1 GHz and at 1 GHz)
bands = [1/44e-3 1e6; 1e3 1e6; 1e4 1e6];
fprintf('\n== A2. Integrated LO phase jitter, one node ==\n');
for b = 1:size(bands,1)
    s = f >= bands(b,1) & f <= bands(b,2);
    for m = 1:3
        v = trapz(f(s), models{m}.lo(s));
        jit(b,m) = sqrt(v);                                          %#ok<SAGROW>
        fprintf('  %8.1f Hz - %7.0f Hz  %-24s %7.2f deg @2.1 GHz  %7.2f deg @1 GHz  %7.1f fs\n', ...
            bands(b,:), strrep(names{m}, '\', ''), rad2deg(jit(b,m)), rad2deg(jit(b,m)*sqrt(kb2)), ...
            1e15*jit(b,m)/(2*pi*f_lo));
    end
end

% Internode LO phase wander over a latency d (both nodes, independent)
%   var = 2 * int S_lo(f) * 2(1 - cos 2 pi f d) df, scaled to the bf carrier
dl = logspace(-6, log10(0.2), 60);
for m = 1:3
    for i = 1:numel(dl)
        wand(m,i) = rad2deg(sqrt(kb2*2*trapz(f, models{m}.lo.*2.*(1 - cos(2*pi*f*dl(i)))))); %#ok<SAGROW>
    end
end
dq = [2e-6 1e-3 5e-3 44e-3];
fprintf('\n== A3. Internode LO phase wander at 1 GHz (deg rms), latency d ==\n');
fprintf('  %-26s', 'd'); fprintf('%10s', '2 us', '1 ms', '5 ms', '44 ms'); fprintf('\n');
for m = 1:3
    v = interp1(dl, wand(m,:), dq);  wandQ(m,:) = v;                 %#ok<SAGROW>
    fprintf('  %-26s', strrep(names{m}, '\', '')); fprintf('%10.3f', v); fprintf('\n');
end

% Reference-oscillator ADEV from the PSDs
fA  = logspace(-6, log10(2e6), 40000);
So_me = me.analytic_psd(fA);  So_me = So_me(:,1).';
SyM = (fA/f_osc).^2 .* So_me;                % mine: S_y = (f/f0)^2 S_phi
SyF = Sy_mf(fA);
tauA = logspace(-3, 2, 41);
for i = 1:numel(tauA)
    k = (sin(pi*fA*tauA(i)).^4)./(pi*fA*tauA(i)).^2;
    adM(i) = sqrt(2*trapz(fA, SyM.*k));                              %#ok<SAGROW>
    adF(i) = sqrt(2*trapz(fA, SyF.*k));                              %#ok<SAGROW>
end
fprintf('\n== A4. Reference-oscillator ADEV ==\n');
fprintf('  tau (s)      '); fprintf('%10g', [1e-3 1e-2 0.1 1 10 100]); fprintf('\n');
fprintf('  this work    '); fprintf('%10.2e', interp1(tauA, adM, [1e-3 1e-2 0.1 1 10 100])); fprintf('\n');
fprintf('  merlo_flow   '); fprintf('%10.2e', interp1(tauA, adF, [1e-3 1e-2 0.1 1 10 100])); fprintf('\n');

%% B) merlo_flow end-to-end runs ---------------------------------------------
fprintf('\n== B. merlo_flow run_flow (unmodified) ==\n');
tb = tic; R1 = run_flow('merlo2026');   tR1 = toc(tb);
tb = tic; R2 = run_flow('x310_ubx160'); tR2 = toc(tb);
fprintf('run_flow times: merlo2026 %.1f s, x310_ubx160 %.1f s\n', tR1, tR2);
close all;

%% C) My model under four settings --------------------------------------------
% Paper-like run length (~50 s, ~1100 epochs), no figures, no per-run .mat
common = struct('T_req', 50, 'makeFigures', false, 'saveResults', false, 'verbose', true, ...
                'timing', 'fixed');     % these cases set sigT directly
C = {
  'C1 as first built (2.1 GHz, 100 us, sigT 30 ps)', struct('f_bf', 2.1e9, 'L_bf', 100e-6, 't_bf', 1e-3, 'sigT', 30e-12)
  'C2 paper Table I (1 GHz, 2 us, sigT 30 ps)',      struct('f_bf', 1e9,   'L_bf', 2e-6,   't_bf', 1e-3, 'sigT', 30e-12)
  'C3 matched to merlo_flow',                        struct('f_bf', 1e9,   'L_bf', 1e-6,   't_bf', c1.bf.proc_latency, ...
                                                            'sigT', R1.resid_std, 'static_tau', c1.bf.static_tau)
  'C4 paper-level time error (sigT 65 ps)',          struct('f_bf', 1e9,   'L_bf', 2e-6,   't_bf', 1e-3, 'sigT', 65e-12)
};
for i = 1:size(C,1)
    fprintf('\n-- %s --\n', C{i,1});
    o = common;  for fn = fieldnames(C{i,2}).', o.(fn{1}) = C{i,2}.(fn{1}); end
    RC(i) = sdr_clock_model_tworate(o);                              %#ok<SAGROW>
end

%% D) Summary table -----------------------------------------------------------
pap = struct('time_ps', 65, 'phase_deg', 23, 'df_std_ppb', 2.04, 'Gc', 0.99);
rows = {};
for i = 1:size(C,1)
    rows(end+1,:) = {C{i,1}, 1e12*RC(i).time_std, RC(i).phase_std_deg, ...
        1e9*RC(i).df_std, RC(i).Gc_median, RC(i).Gc_p5};             %#ok<SAGROW>
end
rows(end+1,:) = {'merlo_flow merlo2026 (K=40)', 1e12*R1.resid_std, NaN, 1e9*std(R1.df_hat), median(R1.Gc), prctile(R1.Gc,5)};
rows(end+1,:) = {'merlo_flow x310_ubx160 (K=40)', 1e12*R2.resid_std, NaN, 1e9*std(R2.df_hat), median(R2.Gc), prctile(R2.Gc,5)};
rows(end+1,:) = {'Paper, Config A ~24-27 dB', pap.time_ps, pap.phase_deg, pap.df_std_ppb, pap.Gc, NaN};
Tsum = cell2table(rows, 'VariableNames', {'case', 'time_std_ps', 'phase_std_deg_bf', 'df_std_ppb', 'Gc_median', 'Gc_p5'});
fprintf('\n== D. Summary ==\n'); disp(Tsum);
writetable(Tsum, fullfile(outDir, 'comparison_summary.csv'));

%% Figures --------------------------------------------------------------------
col = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19];
fig1 = figure('Color', 'w', 'Position', [60 60 1300 420]);
tiledlayout(1, 3, 'TileSpacing', 'compact');
nexttile;
for m = [1 2], semilogx(f, Ldb(models{m}.osc), 'Color', col(m,:), 'LineWidth', 1.4); hold on; end
grid on; xlim([1e-2 2e6]); ylim([-180 20]);
xlabel('Offset (Hz)'); ylabel('L(f) (dBc/Hz)'); title('Reference oscillator, 10 MHz');
legend('This work', 'merlo\_flow (both presets)', 'Location', 'northeast');
nexttile;
for m = 1:3, semilogx(f, Ldb(models{m}.lo), 'Color', col(m,:), 'LineWidth', 1.4); hold on; end
semilogx(meas.f, meas.L, 'kd', 'MarkerFaceColor', 'k');
grid on; xlim([1 2e6]); ylim([-170 0]);
xlabel('Offset (Hz)'); ylabel('L(f) (dBc/Hz)'); title('LO, 2.1 GHz');
legend([names, {'Ettus UBX measured (scaled)'}], 'Location', 'southwest');
nexttile;
loglog(tauA, adM, 'Color', col(1,:), 'LineWidth', 1.4); hold on;
loglog(tauA, adF, 'Color', col(2,:), 'LineWidth', 1.4);
grid on; xlabel('\tau (s)'); ylabel('\sigma_y(\tau)'); title('Reference oscillator ADEV');
legend('This work', 'merlo\_flow', 'Location', 'northeast');
exportgraphics(fig1, fullfile(outDir, 'fig_noise_models.png'), 'Resolution', 150);

fig2 = figure('Color', 'w', 'Position', [60 60 700 430]);
for m = 1:3, loglog(dl*1e3, wand(m,:), 'Color', col(m,:), 'LineWidth', 1.6); hold on; end
xline([1 5 44], ':', {'1 ms', '5 ms (mf latency)', '44 ms (resync)'});
grid on; xlabel('Latency after TWTT, d (ms)'); ylabel('Internode LO phase wander at 1 GHz (deg rms)');
title('Uncorrected LO phase wander between TWTT and the pulse');
legend(names, 'Location', 'northwest');
exportgraphics(fig2, fullfile(outDir, 'fig_lo_wander.png'), 'Resolution', 150);

fig3 = figure('Color', 'w', 'Position', [60 60 900 420]);
lab = categorical(Tsum.case, Tsum.case);
tiledlayout(1, 2, 'TileSpacing', 'compact');
nexttile; barh(lab, Tsum.time_std_ps); grid on; xlabel('TWTT time error std (ps)'); title('Time');
nexttile; barh(lab, Tsum.Gc_median); grid on; xlim([0.9 1]); xlabel('Median coherent gain'); title('Coherent gain');
set(findall(fig3, 'Type', 'axes'), 'TickLabelInterpreter', 'none');
exportgraphics(fig3, fullfile(outDir, 'fig_summary.png'), 'Resolution', 150);

save(fullfile(outDir, 'comparison_results.mat'), 'f', 'mine', 'mf26', 'x310', 'meas', ...
    'Ltab', 'lo_rms_err', 'bands', 'jit', 'dl', 'wand', 'dq', 'wandQ', 'tauA', 'adM', 'adF', ...
    'R1', 'R2', 'RC', 'C', 'Tsum');
fprintf('\nOutputs in %s\n', outDir);
diary off;
