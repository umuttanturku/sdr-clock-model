%% Stochastic clock model of a distributed-array SDR node
% Follows the signal model of Merlo et al., "Real-Time High-Accuracy Digital
% Wireless Time, Frequency, and Phase Calibration for Coherent Distributed
% Antenna Arrays," IEEE TMTT, vol. 74, no. 2, 2026. Equation numbers below
% refer to that paper.
%
% Chain modelled for each node:
%   reference oscillator  (eq. 1)  -> phase noise from a known PSD / L(f)
%   SYS PLL, x k_sys      (eqs. 2-3) -> ref noise low-passed, VCO high-passed
%   TX/RX LO PLL, x k_lo  (eqs. 4-5) -> same again at the carrier
%   clock time T(t)       (eq. 6)  -> T = t + dphi/(2*pi*f0)
% Then two nodes are compared (eqs. 12-13), the TWTT estimator samples the
% internode time offset (eqs. 18, 28), and the LO phase is compensated with
% the linear drift model (eq. 32) to get the residual phase and coherent gain.
clear; clc; close all;
rng(1);

%% 1) Simulation grid
% fs/2 = highest offset frequency represented; T = record length (lowest
% offset ~ 1/T). Noise above fs/2 is simply not in the realization.
fs = 4e6;                         % phase-process sample rate (Hz)
T  = 1;                           % requested duration (s)
N  = 2^nextpow2(fs*T);            % FFT length
T  = N/fs;
t  = (0:N-1).'/fs;
f  = [0:N/2, -(N/2-1):-1].'*fs/N; % FFT-ordered signed frequency grid

%% 2) Reference oscillator, eq. (1) -- replace with your crystal's PSD
p.f0_osc = 10e6;                                  % Hz
p.osc.fm = [1    10   100  1e3  1e4  1e5  1e6];   % offsets (Hz)
p.osc.L  = [-65  -95 -120 -140 -150 -155 -155];   % L(f), dBc/Hz

%% 3) SYS PLL, eqs. (2)-(3), Fig. 3
p.k_sys     = 20;                 % 10 MHz -> 200 MHz system clock
p.sys.fn    = 100e3;              % loop natural frequency ~ cutoff f_c (Hz)
p.sys.zeta  = 0.707;
p.sys.Lfloor = -115;              % in-band floor S_phi,0 at the PLL output (dBc/Hz)
p.sys.vco.fm = [1e3 1e4 1e5 1e6 1e7];
p.sys.vco.L  = [-65 -95 -120 -140 -155];          % free-running VCO, dBc/Hz

%% 4) TX/RX LO PLL, eqs. (4)-(5)
p.k_lo      = 10.5;               % 200 MHz -> 2.1 GHz carrier
p.lo.fn     = 50e3;
p.lo.zeta   = 0.707;
p.lo.Lfloor = -100;
p.lo.vco.fm = [1e3 1e4 1e5 1e6 1e7];
p.lo.vco.L  = [-45 -75 -102 -125 -145];

f0_sys = p.k_sys*p.f0_osc;
f0_lo  = p.k_lo*f0_sys;

%% 5) Deterministic per-node parameters
% df0: fractional frequency error (manufacturing), D: aging (1/s),
% T0: initial time offset of the system clock (s).
cfg(1) = struct('df0', +1.00e-7, 'D', 0,            'T0', 0);
cfg(2) = struct('df0', -0.82e-7, 'D', 1e-10/86400,  'T0', 3e-9);

%% 6) Build each node's clock
for n = 1:2
    [nu_osc, nu_sys, nu_lo] = node_phase_noise(p, f, fs, N);
    % Integral of Delta f_osc(t) over [0,t]: frequency offset + aging
    drift = cfg(n).df0*t + 0.5*cfg(n).D*t.^2;
    % Time error of the system clock, eq. (6): x = T_sys(t) - t
    node(n).x_sys   = cfg(n).T0 + drift + nu_sys/(2*pi*f0_sys);  %#ok<SAGROW>
    % LO phase error, eq. (5). The static phase phi_0,lo is assumed
    % calibrated, so it is tied to the clock offset T0 (Sec. III-A1).
    node(n).dphi_lo = 2*pi*f0_lo*(cfg(n).T0 + drift) + nu_lo;
    node(n).nu_osc  = nu_osc;
    node(n).nu_sys  = nu_sys;
    node(n).nu_lo   = nu_lo;
end

%% 7) Internode quantities, eqs. (12)-(13)
Tnm   = node(2).x_sys   - node(1).x_sys;     % T_sys^(n,m)(t)
phinm = node(2).dphi_lo - node(1).dphi_lo;   % phi_lo^(n,m)(t)
dfnm  = cfg(2).df0 - cfg(1).df0;             % true Delta f_osc^(n,m) at t = 0

%% 8) TWTT time and frequency estimation, eqs. (18) and (28)
tau_twtt = 44e-3;                 % resynchronization interval (s)
sigT     = 30e-12;                % TWTT time-estimate std (s), set by SNR / CRLB (22)-(24)
tk   = (0:tau_twtt:t(end)).';
ik   = round(tk*fs) + 1;
That = Tnm(ik) + sigT*randn(size(tk));       % eq. (18)
dfh  = [NaN; diff(That)/tau_twtt];           % eq. (28)

%% 9) Carrier phase compensation with the linear drift model, eq. (32)
% Between epochs k and k+1 the LO phase difference is predicted as
% 2*pi*f0_lo*(That_k + dfh_k*(t - t_k)).
kk    = floor(t/tau_twtt) + 1;
valid = kk >= 2 & kk <= numel(tk);
pred  = nan(N,1);
pred(valid) = 2*pi*f0_lo*(That(kk(valid)) + dfh(kk(valid)).*(t(valid) - tk(kk(valid))));
eps_phi = angle(exp(1j*(phinm - pred)));     % residual carrier phase (rad)
Gc      = (1 + cos(eps_phi))/2;              % eq. (36) for two equal-amplitude CW signals

fprintf('True Delta f^(n,m)            : %.2f ppb\n', 1e9*dfnm);
fprintf('Estimated Delta f (mean, std) : %.2f ppb, %.2f ppb\n', ...
        1e9*mean(dfh(2:end)), 1e9*std(dfh(2:end)));
fprintf('Residual LO phase std         : %.1f deg\n', rad2deg(std(eps_phi(valid))));
fprintf('Median coherent gain          : %.4f\n', median(Gc(valid)));

%% 10) Checks: simulated PSDs vs. the analytic model
nseg = 2^20;
fp   = logspace(log10(fs/nseg), log10(fs/2), 400).';
[Sosc_th, Ssys_th, Slo_th] = analytic_psd(p, fp);
[Po, fw] = pwelch(node(1).nu_osc, hann(nseg), nseg/2, nseg, fs, 'onesided');
Ps = pwelch(node(1).nu_sys, hann(nseg), nseg/2, nseg, fs, 'onesided');
Pl = pwelch(node(1).nu_lo,  hann(nseg), nseg/2, nseg, fs, 'onesided');
dB = @(S) 10*log10(S/2);          % S_phi -> L(f)

figure('Name', 'Phase noise');
semilogx(fw(2:end), dB(Po(2:end)), fw(2:end), dB(Ps(2:end)), fw(2:end), dB(Pl(2:end)));
hold on; set(gca, 'ColorOrderIndex', 1);
semilogx(fp, dB(Sosc_th), 'k--', fp, dB(Ssys_th), 'k--', fp, dB(Slo_th), 'k--');
grid on; xlabel('Offset frequency (Hz)'); ylabel('L(f) (dBc/Hz)');
legend('Ref osc 10 MHz', 'SYS PLL 200 MHz', 'LO 2.1 GHz', 'Analytic', 'Location', 'southwest');
title('Simulated phase noise vs. model');

figure('Name', 'Internode time and phase');
subplot(3,1,1);
plot(t, 1e9*Tnm, tk, 1e9*That, 'o'); grid on;
ylabel('T^{(n,m)}_{sys} (ns)'); legend('True', 'TWTT estimate'); title('Eq. (13) and (18)');
subplot(3,1,2);
plot(t(valid), rad2deg(eps_phi(valid))); grid on;
ylabel('Residual phase (deg)'); title('After compensation with eq. (32)');
subplot(3,1,3);
plot(t(valid), Gc(valid)); grid on; ylim([0 1]);
xlabel('Time (s)'); ylabel('G_c'); title('Eq. (36)');

% Overlapping Allan deviation of one node's system clock (noise only)
m_list = unique(round(logspace(0, log10(N/4), 40)));
[tau, adev] = oadev(node(1).nu_sys/(2*pi*f0_sys), fs, m_list);
figure('Name', 'ADEV');
loglog(tau, adev, 'o-'); grid on;
xlabel('\tau (s)'); ylabel('\sigma_y(\tau)'); title('System clock, overlapping ADEV');

%% ----------------------------------------------------------------------
function [nu_osc, nu_sys, nu_lo] = node_phase_noise(p, f, fs, N)
% One node's phase-noise realizations (rad) at the oscillator, SYS PLL and LO.
% Everything is built in the frequency domain so the same oscillator
% realization drives both PLLs (noise is correlated, as in the paper).
af = abs(f);
Hs = pll_H(f, p.sys.fn, p.sys.zeta);
Hl = pll_H(f, p.lo.fn,  p.lo.zeta);

X_osc = shaped_white(S_from_L(p.osc.fm, p.osc.L, af), fs, N);
% SYS PLL: k*[nu_in + nu_osc]_lpf + [nu_vco]_hpf (text after eq. 3)
X_sys = Hs.*(p.k_sys*X_osc + shaped_white(floor_S(p.sys.Lfloor, af), fs, N)) ...
      + (1 - Hs).*shaped_white(S_from_L(p.sys.vco.fm, p.sys.vco.L, af), fs, N);
% LO PLL, referenced to the SYS PLL output
X_lo  = Hl.*(p.k_lo*X_sys + shaped_white(floor_S(p.lo.Lfloor, af), fs, N)) ...
      + (1 - Hl).*shaped_white(S_from_L(p.lo.vco.fm, p.lo.vco.L, af), fs, N);

nu_osc = ifft(X_osc, 'symmetric');
nu_sys = ifft(X_sys, 'symmetric');
nu_lo  = ifft(X_lo,  'symmetric');
end

function X = shaped_white(S, fs, N)
% Spectrum of a real Gaussian process with one-sided PSD S (rad^2/Hz),
% evaluated on the FFT grid. |A|^2 = fs*S/2 gives an output PSD of S.
A = sqrt(fs*S/2);
A(1) = 0;                         % no DC: the static phase is deterministic
X = fft(randn(N,1)).*A;
end

function S = S_from_L(fm, L, af)
% L(f) table -> S_phi(f) = 2*10^(L/10), log-log interpolation.
% Below the first point the first slope is extrapolated; above the last
% point the last value is held.
S  = zeros(size(af));
k  = af > 0;
lf = min(log10(af(k)), log10(fm(end)));
S(k) = 2*10.^(interp1(log10(fm), L, lf, 'linear', 'extrap')/10);
end

function S = floor_S(Lfloor, af)
% White PLL in-band noise, given at the PLL output; the loop multiplies it
% by k^2 and H, so it is entered here as already output-referred (k = 1).
S = 2*10^(Lfloor/10)*ones(size(af));
end

function H = pll_H(f, fn, zeta)
% Type-II, 2nd-order closed-loop transfer function. H -> 1 in-band (low-pass
% for reference noise); 1 - H is the high-pass applied to VCO noise.
s  = 1j*2*pi*f;
wn = 2*pi*fn;
H  = (2*zeta*wn*s + wn^2)./(s.^2 + 2*zeta*wn*s + wn^2);
end

function [So, Ss, Sl] = analytic_psd(p, fp)
Hs = pll_H(fp, p.sys.fn, p.sys.zeta);
Hl = pll_H(fp, p.lo.fn,  p.lo.zeta);
So = S_from_L(p.osc.fm, p.osc.L, fp);
Ss = abs(Hs).^2.*(p.k_sys^2*So + floor_S(p.sys.Lfloor, fp)) ...
   + abs(1 - Hs).^2.*S_from_L(p.sys.vco.fm, p.sys.vco.L, fp);
Sl = abs(Hl).^2.*(p.k_lo^2*Ss + floor_S(p.lo.Lfloor, fp)) ...
   + abs(1 - Hl).^2.*S_from_L(p.lo.vco.fm, p.lo.vco.L, fp);
end

function [tau, adev] = oadev(x, fs, m_list)
% Overlapping Allan deviation from time-error samples x (s)
tau0 = 1/fs;
tau  = m_list(:)*tau0;
adev = zeros(size(tau));
for i = 1:numel(m_list)
    m = m_list(i);
    d = x(1+2*m:end) - 2*x(1+m:end-m) + x(1:end-2*m);
    adev(i) = sqrt(sum(d.^2)/(2*(m*tau0)^2*numel(d)));
end
end
