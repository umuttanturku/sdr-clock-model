# Results

All numbers come from MATLAB R2026b runs on 15 Oct 2026. They can be regenerated with `compare_merlo_flow.m` (outputs in `<data>\comparison`) and `run_studies.m` (outputs in `<data>\studies`), where `<data>` is the data folder from `clockmodel_paths.m`; each writes a `*_log.txt` with every number below. A longer write-up with charts is in the comparison doc on claude.ai, "Clock model vs. merlo_flow vs. Merlo 2026" (private; ask the owner for access).

## 1. Comparison with merlo_flow and the paper

`compare_merlo_flow.m`. merlo_flow runs unmodified from a local copy (commit b2658bb), presets `merlo2026` and `x310_ubx160`, 27 dB, 40 epochs. This model runs 52 s (1,191 epochs) per case with a fixed σT.

| Case | Time error std (ps) | Phase std at 1 GHz (°) | Δf estimate std (ppb) | Median Gᴄ | 5th pct Gᴄ |
| --- | --- | --- | --- | --- | --- |
| C1 this model as first built (2.1 GHz, 100 µs, σT 30 ps) | 29.3 | 22.8 (at 2.1 GHz) | 1.00 | 0.982 | 0.859 |
| C2 Table I carrier (1 GHz, 2 µs, σT 30 ps) | 29.3 | 10.9 | 1.00 | 0.996 | 0.967 |
| C3 matched to merlo_flow (σT 26.4 ps, 5 ms latency, 30 ps static) | 25.8 | 10.5 | 0.89 | 0.990 | 0.941 |
| C4 paper-level time error (σT 65 ps) | 63.5 | 23.5 | 2.11 | 0.981 | 0.851 |
| merlo_flow merlo2026 | 26.4 | 9.57 | 0.88 | 0.991 | 0.937 |
| merlo_flow x310_ubx160 | 26.4 | 9.51 | 0.88 | 0.991 | 0.937 |
| Paper, Config A (Sec. V-D, Figs. 11–12) | 60–70 | ~23 | 2.04 | > 0.99 | — |

merlo_flow's phase is its interarrival phase (Sec. V-C); this model's is the spread of the pulse-mean residual.

- Given the same inputs (C3), the two simulators agree. This model's extra 1° comes from extrapolating with the estimated Δf (0.89 ppb over 5 ms ≈ 4.4 ps ≈ 1.6°), which merlo_flow does not do.
- C1 used the wrong carrier; Table I puts the beamforming pulses at 1.0 GHz.
- C4 reproduces the paper's time, phase and frequency spreads, so the paper is limited by TWTT time error.

### Noise models

LO L(f) at 2.1 GHz against Ettus' measured UBX TX phase noise (datasheet, 2.4 GHz, scaled by −1.2 dB), 1 kHz–1 MHz:

| LO model | RMS gap to measured (dB) | Mean gap (dB) |
| --- | --- | --- |
| This model, default chain | 10.8 | +9.9 |
| merlo_flow merlo2026 placeholder | 7.0 | −5.7 |
| merlo_flow x310_ubx160 (datasheet-fitted) | 1.5 | +0.2 |

Reference oscillator ADEV: this model (TCXO-like) flattens at 9.4e-11 from 0.1 s; merlo_flow's power-law profile (OCXO-like) is 1.0e-11 at 1 s and still falling. Neither is measured.

Internode LO phase wander at 1 GHz after a delay d (two independent nodes):

| LO model | 2 µs | 1 ms | 5 ms | 44 ms |
| --- | --- | --- | --- | --- |
| This model, default chain | 0.52° | 0.83° | 1.10° | 5.45° |
| merlo_flow merlo2026 | 0.04° | 0.20° | 0.38° | 1.08° |
| merlo_flow x310_ubx160 | 0.13° | 0.24° | 0.38° | 1.16° |

At the paper's latencies this is small next to the 9.6–23° from TWTT time error.

## 2. Follow-up studies

`run_studies.m`. 26 s runs (595 epochs), X310 chain unless noted.

### CRLB and chain checks

| Check | Result |
| --- | --- |
| CRLB two-way at 27 dB, analytic (this model) | 20.49 ps |
| CRLB two-way at 27 dB, numeric (merlo_flow `crlb_toa`) | 20.56 ps |
| merlo_flow measured / bound | 1.29× |
| Paper (~65 ps) / bound | 3.17× |
| X310 LO PSD, this model vs merlo_flow `pll_chain_psd`, 1 kHz–1 MHz | max 0.000 dB difference |
| X310 chain vs Ettus measured | 1.52 dB RMS (default chain: 10.83 dB) |
| Generator, simulated vs analytic PSD, 1 Hz–1 MHz [osc, SYS, LO] | +0.02, +0.02, +0.03 dB (X310); +0.02, +0.03, +0.03 dB (default) |

### SNR sweep (pulse 1 ms after TWTT)

| SNR (dB) | σT at bound (ps) | Median Gᴄ at bound | σT at 3.17× (ps) | Phase std at 3.17× (°) | Median Gᴄ at 3.17× |
| --- | --- | --- | --- | --- | --- |
| 6 | 229.9 | 0.759 | 729.3 | 102.8 | 0.533 |
| 9 | 162.7 | 0.882 | 516.3 | 100.5 | 0.535 |
| 12 | 115.2 | 0.939 | 365.5 | 98.7 | 0.589 |
| 15 | 81.6 | 0.974 | 258.8 | 84.4 | 0.763 |
| 18 | 57.7 | 0.982 | 183.2 | 68.1 | 0.831 |
| 21 | 40.9 | 0.993 | 129.7 | 46.0 | 0.935 |
| 24 | 28.9 | 0.996 | 91.8 | 35.0 | 0.960 |
| 27 | 20.5 | 0.998 | 65.0 | 22.8 | 0.983 |
| 30 | 14.5 | 0.999 | 46.0 | 16.7 | 0.991 |
| 33 | 10.3 | 0.999 | 32.6 | 11.6 | 0.995 |

All columns, including the 5th percentile and Δf spread, are in `snr_sweep.csv`. At 27 dB and 3.17×, the frequency-estimate std is 2.06 ppb (paper: 2.04 ppb).

### Pulse timing (27 dB)

| Pulse after TWTT (ms) | Median Gᴄ at bound | Median Gᴄ at 3.17× |
| --- | --- | --- |
| 0.1 | 0.9985 | 0.9849 |
| 1 | 0.9981 | 0.9806 |
| 5 | 0.9977 | 0.9764 |
| 10 | 0.9969 | 0.9707 |
| 20 | 0.9958 | 0.9597 |
| 30 | 0.9931 | 0.9353 |
| 40 | 0.9906 | 0.9105 |

The timing-only prediction σT·√((1 + t/τ)² + (t/τ)²) tracks these values; the default chain gives curves within 8%.

## Open questions

- A 23° Gaussian phase spread gives a median Gᴄ of about 0.98, below the paper's "above 99%". The paper's figure may come from its best-SNR or optimized runs; check against the Fig. 11 data.
- The 3.17× excess is fitted to one paper point. A fixed hardware floor added to the bound would behave differently at low SNR; the paper's Fig. 11 data would decide between the two.
