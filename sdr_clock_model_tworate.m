function res = sdr_clock_model_tworate(opts)
%SDR_CLOCK_MODEL_TWORATE  Two-rate stochastic clock model of a distributed-array SDR pair.
%
%   RES = SDR_CLOCK_MODEL_TWORATE()      runs with the defaults below
%   RES = SDR_CLOCK_MODEL_TWORATE(OPTS)  overrides any default field of OPTS
%
% Long-duration version of sdr_clock_model.m (same signal model, Merlo et al.,
% IEEE TMTT 74(2), 2026; equation numbers refer to that paper).
%
% WHY TWO RATES
% The phase-noise PSD spans ~0.01 Hz (crystal flicker / random walk, which
% dominates long-term wander) to ~MHz (PLL VCO noise, which dominates
% short-term jitter). The PSD is split at f_split:
%
%   S(f) = w(f) S(f)  +  (1 - w(f)) S(f),    w(f) = 1/(1 + (f/f_split)^n)
%          \_ slow _/    \____ fast ____/
%
% Each part comes from its own independent white noise, so the PSD of the sum
% is exactly S(f).
%   * Slow part: band-limited below ~f_split, sampled at fs_slow over the whole
%     record and spline-interpolated to any instant needed.
%   * Fast part: only offsets above ~f_split, so its correlation time is
%     ~1/f_split. Generated in short blocks at fs_fast around each TWTT exchange
%     and the beamforming pulse after it; blocks more than a few ms apart are
%     effectively independent.
% The split is applied per noise SOURCE before the PLL filtering, so the
% oscillator -> SYS clock -> LO correlation is kept in both parts.
%
% NOISE CHAIN (opts.chain)
% A list of stages from the 10 MHz reference to the LO. Each stage is
%   'pll': out = H (k in + n_inband) + (1 - H) n_vco + n_floor   (type-II loop H)
%   'div': out = k in
% with PSD handles Sinb, Svco (rad^2/Hz at the stage output) and a white Sfloor.
% The SYS (200 MHz) clock is the output of stage chain.i_sys divided by
% chain.sys_div. Default: my two-PLL tables. The X310 + UBX-160 chain built from
% merlo_flow's datasheet parameters comes from chain_x310_from_merlo_flow.m.
%
% REFERENCE OSCILLATOR (opts.osc)
%   .fm, .L : L(f) table (dBc/Hz at .f0), generated with the rest by FFT shaping
%   .h      : power-law S_y coefficients [h2 h1 h0 h-1 h-2]. The slow part is then
%             generated in the time domain with Kasdin's fractional-difference
%             filter, started at rest at t = 0, so flicker and random-walk FM keep
%             their non-stationary low-frequency wander (needed for holdover);
%             the PLL loops and the split are applied as IIR filters.
%
% TWTT TIME ERROR (opts.timing)
%   'crlb'  : sigma_T from the ToA CRLB (Eqs. 22, 24) at opts.snr_dB for the
%             PTT waveform, times opts.crlb_excess (1 = the bound itself)
%   'fixed' : sigma_T = opts.sigT
%
% BEAMFORMING
% TWTT runs on the LO; the beamforming pulses that set the coherent gain are at
% f_bf = 1.0 GHz (Table I, Config A: 2.0 us). LO phase noise is scaled by
% f_bf/f_lo. The pulse can sit anywhere in the epoch (opts.t_bf).

%% Defaults
d.T_req       = 100;           % record length (s)
d.seed        = 1;
d.fsplit      = 2e3;  d.nsplit = 8;
d.fs_slow     = 20e3; d.fs_fast = 4e6; d.Nb = 2^15;
d.tau_twtt    = 44e-3;         % resynchronization interval (s)
d.timing      = 'crlb';        % 'crlb' | 'fixed'
d.snr_dB      = 27;            % pre-integration SNR of each TWTT pulse (dB)
d.ptt         = struct('beta', 20e6, 'tau_pd', 1.5e-6, 'fs', 200e6);   % Table I, Config A
d.crlb_excess = 1;             % estimator std / CRLB std
d.sigT        = 30e-12;        % used when timing = 'fixed' (s)
d.f_bf        = 1.0e9;         % beamforming carrier (Hz), Table I
d.t_bf        = 1e-3;          % pulse start after each TWTT (s), 0 .. tau_twtt
d.L_bf        = 2e-6;          % pulse length (s), Table I Config A
d.static_tau  = 0;             % uncalibrated static time offset (s)
d.outDir      = '';            % '' = clockmodel_paths().data
d.saveResults = true;
d.makeFigures = true;
d.verbose     = true;
d.paramsOnly  = false;
% Reference oscillator L(f), dBc/Hz at 10 MHz (TCXO-like guess; replace when measured)
d.osc.f0 = 10e6;
d.osc.fm = [1    10   100  1e3  1e4  1e5  1e6];
d.osc.L  = [-65  -95 -120 -140 -150 -155 -155];
d.chain  = [];                 % [] = default two-PLL chain below
if nargin < 1, opts = struct(); end
o = d;
for fn = fieldnames(opts).', o.(fn{1}) = opts.(fn{1}); end
if isempty(o.chain), o.chain = default_chain(); end
if isempty(o.outDir), pths = clockmodel_paths(); o.outDir = pths.data; end
rng(o.seed);

%% Chain bookkeeping
ch     = o.chain;
f_osc  = o.osc.f0;
kprod  = cumprod([ch.stages.kappa]);
f0_sys = f_osc*kprod(ch.i_sys)/ch.sys_div;
f0_lo  = f_osc*kprod(end);
kbf    = o.f_bf/f0_lo;                      % LO phase noise -> bf carrier
kasdin = isfield(o.osc, 'h');                % power-law oscillator, time-domain slow part
if kasdin
    assert(numel(o.osc.h) == 5 && mod(o.nsplit, 2) == 0, 'osc.h needs 5 coefficients and an even nsplit');
    Sosc = @(af) S_from_h(f_osc, o.osc.h, af);
else
    Sosc = @(af) S_from_L(o.osc.fm, o.osc.L, af);
end

%% TWTT time error
[sig_crlb, crlb] = twtt_crlb(o.snr_dB, o.ptt);
switch lower(o.timing)
    case 'crlb',  sigT = o.crlb_excess*sig_crlb;
    case 'fixed', sigT = o.sigT;
    otherwise,    error('timing must be ''crlb'' or ''fixed''');
end

cfg(1) = struct('df0', +1.00e-7, 'D', 0,           'T0', 0);
cfg(2) = struct('df0', -0.82e-7, 'D', 1e-10/86400, 'T0', 3e-9);
res.opts = o;  res.f0_sys = f0_sys;  res.f0_lo = f0_lo;
res.sigT = sigT;  res.sig_crlb = sig_crlb;  res.crlb = crlb;
res.analytic_psd = @(fp) chain_psd(ch, Sosc, abs(fp(:)));   % [S_osc, S_sys, S_lo] (rad^2/Hz)
if o.paramsOnly, return; end

%% Grids
N_s = 2^nextpow2(o.T_req*o.fs_slow);
T   = N_s/o.fs_slow;
t_s = (0:N_s-1).'/o.fs_slow;
f_s = fftfreq(N_s, o.fs_slow);
f_b = fftfreq(o.Nb, o.fs_fast);
if kasdin   % |B|^2 of the digital Butterworth that splits the time-domain oscillator
    wc   = tan(pi*o.fsplit/o.fs_slow);
    wfun = @(f) (abs(f) < o.fs_slow/2)./(1 + (tan(pi*min(abs(f), o.fs_slow/2)/o.fs_slow)/wc).^o.nsplit);
else
    wfun = @(f) 1./(1 + (abs(f)/o.fsplit).^o.nsplit);
end

%% Fast-block layout: TWTT instant at i0; pulse in the same block if it fits
Nb   = o.Nb;
i0   = Nb/4 + 1;
nbf  = max(round(o.L_bf*o.fs_fast), 1);
ibf  = i0 + round(o.t_bf*o.fs_fast) + (0:nbf-1).';
same = ibf(end) <= Nb;
if ~same, ibf = i0 + (0:nbf-1).'; end        % own block, pulse starts at i0
tbf  = o.t_bf + (0:nbf-1).'/o.fs_fast;        % pulse sample times after t_k

%% Slow part
if o.verbose
    fprintf('Slow part: %d samples per signal (%.1f s at %.0f kHz), %d-stage chain\n', ...
        N_s, T, o.fs_slow/1e3, numel(ch.stages));
end
A_s = chain_amps(ch, Sosc, f_s, o.fs_slow, wfun(f_s));
if kasdin, A_s.osc(:) = 0; end                 % oscillator added in the time domain below
for n = 1:2
    [Xo, Xs, Xl] = chain_gen(A_s, ch, N_s);
    slow(n).osc = ifft(Xo, 'symmetric');                               %#ok<AGROW>
    slow(n).sys = ifft(Xs, 'symmetric');
    slow(n).lo  = ifft(Xl, 'symmetric');
    if kasdin
        [xo, xs, xl] = osc_kasdin(ch, f_osc, o.osc.h, N_s, o.fs_slow, o.fsplit, o.nsplit);
        slow(n).osc = slow(n).osc + xo;
        slow(n).sys = slow(n).sys + xs;
        slow(n).lo  = slow(n).lo  + xl;
        clear xo xs xl
    end
    G(n).sys = griddedInterpolant(t_s, slow(n).sys, 'spline');          %#ok<AGROW>
    G(n).lo  = griddedInterpolant(t_s, slow(n).lo,  'spline');
end
clear Xo Xs Xl A_s

%% Fast part per epoch, TWTT (eqs. 18, 28) and compensation (eq. 32)
A_f = chain_amps(ch, Sosc, f_b, o.fs_fast, 1 - wfun(f_b));
tk  = (0:o.tau_twtt:T - o.tau_twtt - o.t_bf - o.L_bf).';
K   = numel(tk);
Tnm = zeros(K,1); That = zeros(K,1); dfh = nan(K,1);
Gc  = nan(K,1);  eps_mean = nan(K,1); eps_std = nan(K,1);
Pacc = zeros(Nb,3); nacc = 0; Nacc_max = 300;

tic;
for k = 1:K
    tt = tk(k) + [0; tbf];                     % TWTT instant, then the pulse
    xs = zeros(1, 2); pb = zeros(nbf, 2);
    for n = 1:2
        [Xo, Xs, Xl] = chain_gen(A_f, ch, Nb);
        if n == 1 && nacc < Nacc_max
            Pacc = Pacc + abs([Xo Xs Xl]).^2;  nacc = nacc + 1;
        end
        fsys = ifft(Xs, 'symmetric');
        flo  = ifft(Xl, 'symmetric');
        if ~same                                % pulse far from the TWTT: fresh block
            [~, ~, Xl2] = chain_gen(A_f, ch, Nb);
            flo = ifft(Xl2, 'symmetric');
        end
        drift = cfg(n).df0*tt + 0.5*cfg(n).D*tt.^2;
        Toff  = cfg(n).T0 + (n == 2)*o.static_tau;
        % eq. (6): system-clock time error at the TWTT instant
        xs(n) = cfg(n).T0 + drift(1) + (G(n).sys(tt(1)) + fsys(i0))/(2*pi*f0_sys);
        % beamforming-carrier phase over the pulse
        pb(:,n) = 2*pi*o.f_bf*(Toff + drift(2:end)) + kbf*(G(n).lo(tt(2:end)) + flo(ibf));
    end
    Tnm(k)  = xs(2) - xs(1);                           % eq. (13)
    That(k) = Tnm(k) + sigT*randn;                     % eq. (18)
    if k == 1, continue; end
    dfh(k) = (That(k) - That(k-1))/o.tau_twtt;        % eq. (28)
    phinm  = pb(:,2) - pb(:,1);
    pred   = 2*pi*o.f_bf*(That(k) + dfh(k)*tbf);       % eq. (32)
    e      = angle(exp(1j*(phinm - pred)));
    Gc(k)       = mean((1 + cos(e))/2);                % eq. (36), equal amplitudes
    eps_mean(k) = angle(mean(exp(1j*e)));
    eps_std(k)  = std(e);
end
tloop = toc;

%% Summary
res.T = T; res.K = K; res.tloop = tloop; res.sameBlock = same;
res.df_true   = cfg(2).df0 - cfg(1).df0;
res.df_mean   = mean(dfh, 'omitnan');
res.df_std    = std(dfh, 'omitnan');
res.time_std  = std(That - Tnm);
res.phase_rms_deg = rad2deg(rms(eps_mean, 'omitnan'));
res.phase_std_deg = rad2deg(std(eps_mean, 'omitnan'));
res.intra_std_deg = rad2deg(median(eps_std, 'omitnan'));
res.Gc_median = median(Gc, 'omitnan');
res.Gc_p5     = prctile(Gc, 5);
res.epoch = table(tk, Tnm, That, dfh, Gc, eps_mean, eps_std);
if o.verbose
    fprintf('Record %.1f s, %d epochs, bf %.2f GHz, pulse %g us at +%g ms, timing %s: sigT %.1f ps (CRLB %.1f ps at %g dB) (loop %.1f s)\n', ...
        T, K, o.f_bf/1e9, 1e6*o.L_bf, 1e3*o.t_bf, o.timing, 1e12*sigT, 1e12*sig_crlb, o.snr_dB, tloop);
    fprintf('  Delta f: true %.2f ppb, est %.2f ppb, std %.2f ppb\n', ...
        1e9*res.df_true, 1e9*res.df_mean, 1e9*res.df_std);
    fprintf('  Phase at bf carrier: pulse-mean RMS %.2f deg (std %.2f), intra-pulse %.3f deg\n', ...
        res.phase_rms_deg, res.phase_std_deg, res.intra_std_deg);
    fprintf('  Coherent gain: median %.4f, 5th pct %.4f\n', res.Gc_median, res.Gc_p5);
end

%% PSD check (always computed: slow + fast parts vs. the analytic chain)
nseg = min(2^18, N_s/4);
[Pslow, fws] = pwelch([slow(1).osc slow(1).sys slow(1).lo], hann(nseg), nseg/2, nseg, o.fs_slow, 'onesided');
kb    = (2:Nb/2).';
Pfast = 2*Pacc(kb,:)/nacc/(o.fs_fast*Nb);
edges = logspace(log10(fws(2)), log10(o.fs_fast/2), round(30*log10(o.fs_fast/2/fws(2))) + 1).';
fc    = sqrt(edges(1:end-1).*edges(2:end));
Ptot  = zeros(numel(fc), 3);
for c = 1:3
    Ps = logbin(fws(2:end), Pslow(2:end,c), edges);
    Pf = logbin(f_b(kb),    Pfast(:,c),     edges);
    inF = fc > f_b(2) & fc < o.fs_fast/2;
    okF = ~isnan(Pf);
    Pf(inF & ~okF) = exp(interp1(log(fc(okF)), log(Pf(okF)), log(fc(inF & ~okF))));
    Ps(isnan(Ps)) = 0;  Pf(isnan(Pf)) = 0;
    Ptot(:,c) = Ps + Pf;
end
Sm = chain_psd(ch, Sosc, fc);
res.psd = struct('f', fc, 'sim', Ptot, 'model', Sm);
ok = fc > 1 & fc < 1e6 & all(Ptot > 0, 2);
res.psd_err_dB = mean(10*log10(Ptot(ok,:)./Sm(ok,:)));          % mean sim/model, per stage
if o.verbose
    fprintf('  PSD check 1 Hz-1 MHz, mean sim/model [osc sys lo]: %+.2f %+.2f %+.2f dB\n', res.psd_err_dB);
end

%% Figures
if o.makeFigures
    dB = @(S) 10*log10(S/2);
    figure('Name', 'Phase noise (two-rate)');
    semilogx(fc, dB(Ptot)); hold on; set(gca, 'ColorOrderIndex', 1);
    semilogx(fc, dB(Sm), 'k--');
    xline(o.fsplit, ':', 'f_{split}');
    grid on; xlabel('Offset frequency (Hz)'); ylabel('L(f) (dBc/Hz)');
    legend(sprintf('Ref osc %.0f MHz', f_osc/1e6), sprintf('SYS %.0f MHz', f0_sys/1e6), ...
        sprintf('LO %.2f GHz', f0_lo/1e9), 'Analytic', 'Location', 'southwest');
    title(sprintf('Slow + fast parts vs. model (%s)', ch.name), 'Interpreter', 'none');

    figure('Name', 'Per-epoch results');
    subplot(3,1,1);
    plot(tk, 1e6*Tnm, '-', tk(1:20:end), 1e6*That(1:20:end), 'o'); grid on;
    ylabel('T^{(n,m)}_{sys} (\mus)'); legend('True', 'TWTT estimate (every 20th)'); title('Eqs. (13), (18)');
    subplot(3,1,2);
    plot(tk, rad2deg(eps_mean), '.'); grid on;
    ylabel('Residual phase (deg)');
    title(sprintf('Mean residual over each %g \\mus pulse at %.1f GHz, %g ms after TWTT', ...
        1e6*o.L_bf, o.f_bf/1e9, 1e3*o.t_bf));
    subplot(3,1,3);
    plot(tk, Gc, '.'); grid on; ylim([0 1]); yline(res.Gc_median, '--', 'median');
    xlabel('Time (s)'); ylabel('G_c'); title('Eq. (36), per beamforming pulse');

    m_list = unique(round(logspace(0, log10(N_s/4), 50)));
    [tau, adev] = oadev(slow(1).sys/(2*pi*f0_sys), o.fs_slow, m_list);
    res.adev = struct('tau', tau, 'adev', adev);
    figure('Name', 'ADEV (two-rate)');
    loglog(tau, adev, 'o-'); grid on;
    xline(1/o.fsplit, ':', 'below: fast part not included');
    xlabel('\tau (s)'); ylabel('\sigma_y(\tau)'); title('System clock, overlapping ADEV, slow part');
end

%% Save
if o.saveResults
    if ~isfolder(o.outDir), mkdir(o.outDir); end
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    fn = fullfile(o.outDir, ['clock_tworate_' stamp '.mat']);
    out = rmfield(res, 'analytic_psd'); out.cfg = cfg; out.slow = slow;   %#ok<STRNU>
    save(fn, '-struct', 'out', '-v7.3');
    if o.makeFigures
        savefig(findobj('Type', 'figure'), fullfile(o.outDir, ['clock_tworate_' stamp '.fig']));
    end
    dd = dir(fn);
    res.file = fn;
    if o.verbose, fprintf('Saved %s (%.0f MB)\n', fn, dd.bytes/1e6); end
end
end

%% ----------------------------------------------------------------------
function ch = default_chain()
% My original tables: 10 MHz -> SYS PLL (x20, 200 MHz) -> LO PLL (x10.5, 2.1 GHz).
% Sinb is the PLL in-band floor (output-referred, low-passed by the loop).
Ltab = @(fm, L) @(af) S_from_L(fm, L, af);
st(1) = stage('SYS PLL 200 MHz', 'pll', 20, 100e3, 0.707, ...
    Ltab([1e3 1e4 1e5 1e6 1e7], [-65 -95 -120 -140 -155]), @(af) floor_S(-115, af), 0);
st(2) = stage('LO PLL 2.1 GHz', 'pll', 10.5, 50e3, 0.707, ...
    Ltab([1e3 1e4 1e5 1e6 1e7], [-45 -75 -102 -125 -145]), @(af) floor_S(-100, af), 0);
ch = struct('name', 'default two-PLL tables', 'stages', st, 'i_sys', 1, 'sys_div', 1);
end

function s = stage(name, type, kappa, fn, zeta, Svco, Sinb, Sfloor)
s = struct('name', name, 'type', type, 'kappa', kappa, 'fn', fn, 'zeta', zeta, ...
           'Svco', Svco, 'Sinb', Sinb, 'Sfloor', Sfloor);
end

function [sig, info] = twtt_crlb(snr_dB, ptt)
% ToA CRLB (Eq. 22) for the PTT waveform (Eq. 25), DC-centred so mu_f = 0:
%   var_1way = 1 / (2 SNR_post zeta_f^2/E_s),  zeta_f^2/E_s = (pi beta)^2
% SNR_post = pre-integration SNR x samples in the pulse (matched filter gain).
% Two-way offset T = (tof_fwd - tof_rev)/2  ->  var_2way = var_1way / 2.
N        = round(ptt.tau_pd*ptt.fs) + 1;
snr_post = 10^(snr_dB/10)*N;
wbar2    = (pi*ptt.beta)^2;
v1       = 1/(2*snr_post*wbar2);
sig      = sqrt(v1/2);
info     = struct('N', N, 'snr_post', snr_post, 'sig_1way', sqrt(v1), 'sig_2way', sig);
end

function f = fftfreq(N, fs)
f = [0:N/2, -(N/2-1):-1].'*fs/N;
end

function A = chain_amps(ch, Sosc, f, fs, g)
% Amplitude spectra |A|^2 = fs*S*g/2 for every noise source, plus loop TFs.
af = abs(f);
amp = @(S) zero_dc(sqrt(fs/2*g.*S));
A.osc = amp(Sosc(af));
for i = 1:numel(ch.stages)
    st = ch.stages(i);
    if strcmp(st.type, 'pll')
        A.st(i).H     = pll_H(f, st.fn, st.zeta);
        A.st(i).inb   = amp(st.Sinb(af));
        A.st(i).vco   = amp(st.Svco(af));
        A.st(i).floor = amp(st.Sfloor*ones(size(af)));
    else
        A.st(i).H = []; A.st(i).inb = []; A.st(i).vco = []; A.st(i).floor = [];
    end
end
end

function a = zero_dc(a)
a(1) = 0;                       % no DC: static phases are deterministic
a(~isfinite(a)) = 0;
end

function [Xo, Xs, Xl] = chain_gen(A, ch, N)
% One realization of reference -> ... -> LO phase noise (spectra).
W  = @() fft(randn(N,1));
Xo = A.osc.*W();
X  = Xo;  Xs = [];
for i = 1:numel(ch.stages)
    st = ch.stages(i);
    if strcmp(st.type, 'pll')
        a = A.st(i);
        X = a.H.*(st.kappa*X + a.inb.*W()) + (1 - a.H).*(a.vco.*W());
        if st.Sfloor > 0, X = X + a.floor.*W(); end
    else
        X = st.kappa*X;
    end
    if i == ch.i_sys, Xs = X/ch.sys_div; end
end
Xl = X;
end

function S = chain_psd(ch, Sosc, af)
% Analytic one-sided PSDs [S_osc, S_sys, S_lo] at |f| = af (column).
af = af(:);
So = Sosc(af);  Sx = So;  Ss = [];
for i = 1:numel(ch.stages)
    st = ch.stages(i);
    if strcmp(st.type, 'pll')
        H2 = abs(pll_H(af, st.fn, st.zeta)).^2;
        G2 = abs(1 - pll_H(af, st.fn, st.zeta)).^2;
        Sx = H2.*(st.kappa^2*Sx + st.Sinb(af)) + G2.*st.Svco(af) + st.Sfloor;
    else
        Sx = st.kappa^2*Sx;
    end
    if i == ch.i_sys, Ss = Sx/ch.sys_div^2; end
end
S = [So Ss Sx];
end

function S = S_from_L(fm, L, af)
S  = zeros(size(af));
k  = af > 0;
lf = min(log10(af(k)), log10(fm(end)));
S(k) = 2*10.^(interp1(log10(fm), L, lf, 'linear', 'extrap')/10);
end

function S = S_from_h(f0, h, af)
% One-sided S_phi (rad^2/Hz) at carrier f0 from S_y(f) = sum h_b f^b, b = 2..-2.
S = zeros(size(af));
k = af > 0;
S(k) = f0^2*(af(k).^((2:-1:-2) - 2))*h(:);
end

function [xo, xs, xl] = osc_kasdin(ch, f0, h, N, fs, fsplit, nsplit)
% Slow part of the power-law reference and its path to SYS and LO, in the time
% domain. Each term h_b is white noise through Kasdin's (1 - z^-1)^(-alpha/2),
% alpha = 2 - b (N. J. Kasdin, Proc. IEEE 83(5), 1995), whose one-sided PSD
% 2Q/fs |2 sin(pi f/fs)|^-alpha matches f0^2 h_b f^-alpha for f << fs. Then the
% split filter (Butterworth, |B|^2 = w(f)) and each PLL's H(s), bilinear at fs.
M  = 2*N;
xo = zeros(N,1);
for k = find(h(:).' ~= 0)
    alpha = k - 1;
    Q = f0^2*h(k)*fs/2*(2*pi/fs)^alpha;
    g = cumprod([1; (alpha/2 + (0:N-2).')./(1:N-1).']);
    x = ifft(fft(sqrt(Q)*randn(N,1), M).*fft(g, M), 'symmetric');
    xo = xo + x(1:N);
end
[bw, aw] = butter(nsplit/2, fsplit/(fs/2));
xo = filter(bw, aw, xo);
x  = xo;  xs = [];
for i = 1:numel(ch.stages)
    st = ch.stages(i);
    x  = st.kappa*x;
    if strcmp(st.type, 'pll')
        wn = 2*pi*st.fn;
        [bd, ad] = bilinear([2*st.zeta*wn wn^2], [1 2*st.zeta*wn wn^2], fs);
        x = filter(bd, ad, x);
    end
    if i == ch.i_sys, xs = x/ch.sys_div; end
end
xl = x;
end

function S = floor_S(Lfloor, af)
S = 2*10^(Lfloor/10)*ones(size(af));
end

function H = pll_H(f, fn, zeta)
s  = 1j*2*pi*f;
wn = 2*pi*fn;
H  = (2*zeta*wn*s + wn^2)./(s.^2 + 2*zeta*wn*s + wn^2);
end

function Pb = logbin(f, P, edges)
b  = discretize(f, edges);
ok = ~isnan(b);
Pb = accumarray(b(ok), P(ok), [numel(edges)-1 1], @mean, NaN);
end

function [tau, adev] = oadev(x, fs, m_list)
tau0 = 1/fs;
tau  = m_list(:)*tau0;
adev = zeros(size(tau));
for i = 1:numel(m_list)
    m = m_list(i);
    d = x(1+2*m:end) - 2*x(1+m:end-m) + x(1:end-2*m);
    adev(i) = sqrt(sum(d.^2)/(2*(m*tau0)^2*numel(d)));
end
end
