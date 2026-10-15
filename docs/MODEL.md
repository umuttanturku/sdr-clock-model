# How the model works

`sdr_clock_model_tworate.m` simulates two SDR nodes, each with its own free-running reference oscillator and PLL chain, synchronized by two-way time transfer (TWTT) every `tau_twtt`. Equation numbers refer to Merlo et al., IEEE TMTT 74(2), 2026.

## Signal model

Each node follows the paper's Fig. 2 chain.

| Quantity | Paper | In the code |
| --- | --- | --- |
| Reference oscillator phase | Eq. 1 | Deterministic offset and aging (`cfg(n).df0`, `cfg(n).D`) plus phase noise from the `osc` L(f) table |
| SYS clock (200 MHz) and LO phase | Eqs. 2–5 | The reference noise pushed through the stage list in `opts.chain` |
| Clock time | Eq. 6 | x(t) = T(t) − t = T0 + drift + φ_sys(t)/(2π f_sys) |
| Internode time and LO phase | Eqs. 12–13 | Node 2 minus node 1 |
| TWTT time estimate | Eq. 18 | True internode offset + Gaussian error with std σT |
| Frequency estimate | Eq. 28 | Difference of successive time estimates / `tau_twtt` |
| Carrier compensation | Eq. 32 | Predicted phase 2π f_bf (T̂_k + Δf̂_k t) at each pulse sample |
| Coherent gain | Eq. 36 | Mean of (1 + cos ε)/2 over the pulse, for two equal-amplitude signals |

The two nodes use the fractional frequency offsets +100 ppb and −82 ppb, so the true internode offset is −182 ppb, the typical value the paper reports. Node 2 also has 1e-10/day aging and a 3 ns initial offset.

### Beamforming carrier

TWTT runs on the 2.1 GHz LO. The pulses that define coherent gain are at **1.0 GHz** (Table I, Config A, 2.0 µs PTT pulses). The LO phase noise is scaled to the beamforming carrier by f_bf / f_lo, assuming the same fractional stability. An earlier version evaluated coherence at 2.1 GHz, which roughly doubled the residual phase.

## Noise chain

The chain is a list of stages from the 10 MHz reference to the LO.

```
pll:  out = H(f) · (κ · in + n_inband) + (1 − H(f)) · n_vco + n_floor
div:  out = κ · in
```

H(f) is a type-II, second-order closed loop with natural frequency `fn` and damping `zeta`. Each stage carries three PSD handles in rad²/Hz at its output: `Sinb` (in-band PFD/charge-pump/divider noise, low-passed by the loop), `Svco` (open-loop VCO, high-passed), and `Sfloor` (white, added after the loop). The SYS clock is the output of stage `i_sys`, divided by `sys_div`.

- **Default chain** (`default_chain` in the model): SYS PLL ×20 to 200 MHz (100 kHz loop) and LO PLL ×10.5 to 2.1 GHz (50 kHz loop), with hand-picked VCO tables and in-band floors of −115 and −100 dBc/Hz. It sits about 10 dB above Ettus' measured UBX LO noise from 10 kHz to 1 MHz.
- **X310 + UBX-160 chain** (`chain_x310_from_merlo_flow.m`): 10 MHz → PLL1 → 96 MHz VCXO → PLL2 → 2400 MHz → /48 → MAX2871 → 2.1 GHz, with SYS = 2400 MHz / 12. Stage values come from LMK04816, CVHD-950 and MAX2871 datasheets and UHD settings, with three constants fitted to Ettus' measured UBX phase noise. These were assembled by merlo_flow; this repo only reads them. It sits within 1.5 dB RMS of the measured curve.

The reference oscillator is a guessed TCXO-like profile (−65 dBc/Hz at 1 Hz, ADEV floor about 9e-11). The X310's internal reference is a 2.5 ppm TCXO, but no measured profile is published.

## Two-rate generation

The phase-noise PSD runs from about 0.01 Hz (oscillator wander) to MHz offsets (VCO noise). A single sample rate would need fs·T samples, for example 4 MHz × 100 s = 4e8 per signal. The model splits every noise source's PSD at `fsplit` = 2 kHz:

```
S(f) = w(f) S(f) + (1 − w(f)) S(f),    w(f) = 1 / (1 + (f / fsplit)^8)
```

- **Slow part**: generated at `fs_slow` = 20 kHz over the whole record by FFT shaping of white Gaussian noise, then spline-interpolated to any instant needed.
- **Fast part**: generated at `fs_fast` = 4 MHz in blocks of `Nb` = 2^15 samples (8.2 ms), one fresh block per node per TWTT epoch, covering the exchange and the pulse after it. When the pulse falls outside the block, it gets its own fresh block.

The two parts come from independent noise, so their PSDs add back to exactly S(f). The fast part has no content below about 2 kHz, so its correlation time is well under 1 ms and blocks 44 ms apart are effectively independent. The split is applied per noise source, before the PLL filtering, so the correlation between the SYS clock and the LO of one node is kept.

**Check**: the model compares the simulated PSDs (slow + fast) with the analytic chain on every run and reports `res.psd_err_dB`. On 15 Oct 2026 the mean difference over 1 Hz–1 MHz was +0.02 to +0.03 dB for both chains.

## TWTT time error

With `timing = 'crlb'`, σT comes from the ToA Cramér–Rao bound (Eq. 22) for the PTT waveform (Eq. 25):

```
var_1way = 1 / (2 · SNR_post · (π β)²),   SNR_post = SNR_pre · N,   N = τ_pd · f_s + 1
σT       = crlb_excess · sqrt(var_1way / 2)          (two-way offset = (fwd − rev)/2)
```

With β = 20 MHz, τ_pd = 1.5 µs and f_s = 200 MSa/s (Table I, Config A), N = 301 and σT = 20.5 ps at 27 dB. merlo_flow's numerical bound, which includes the rectangular pulse edges, gives 20.6 ps. Its full waveform simulation measures 26.4 ps (1.29× the bound). The paper's ~65 ps is about 3.2× the bound, a hardware floor this model does not simulate. `crlb_excess` scales it in.

## Pulse timing

Eq. 32 extrapolates the frequency estimate from the TWTT instant to the pulse. Because Δf̂ is the difference of two noisy timestamps, the time error at a delay t after the exchange is

```
σ(t) = σT · sqrt( (1 + t/τ)² + (t/τ)² ),   τ = tau_twtt
```

That is about 2.1× σT at the end of a 44 ms epoch. LO wander over the same interval adds about 1° at 5 ms and 1–5° at 44 ms at 1 GHz, depending on the chain.

## Assumptions and limits

- TWTT error is Gaussian and white from exchange to exchange. No waveform, matched filter or QLS is simulated (merlo_flow does this).
- No acquisition phase (Table B-I), multipath, Doppler, vibration, spurs or hardware non-idealities.
- One LO per node for transmit and receive. Static phase offsets are assumed calibrated out.
- Phase noise is treated as additive phase (small-angle); the PSDs are S_φ, not the measured L(f) of a signal near the carrier.
- Offsets below about 1/T are not represented, and offsets above `fs_fast`/2 = 2 MHz are not either.
- Two nodes only.
