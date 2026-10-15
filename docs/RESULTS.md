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
| merlo_flow x310_ubx160 (datasheet stages, 3 constants fitted to this curve) | 1.5 | +0.2 |

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
| X310 chain vs Ettus measured (fit residual, not a validation; see MODEL.md) | 1.52 dB RMS (default chain: 10.83 dB) |
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

### Reference oscillator profile (X310 chain)

Section 5 of `run_studies.m`, `oscillator.csv`. The guessed TCXO table against a typical TCXO built from published power-law coefficients: h0 = 9.4e-20, h₋₂ = 3.8e-21 (Kassas, Ghadiok, Humphreys, ION GNSS+ 2014, Table I), and the same plus the flicker term h₋₁ = 1.8e-19 that source drops (Curran et al. 2012, Table I, after Van Dierendonck 1984). Both get the guessed table's −155 dBc/Hz white PM floor (as h2) and run on the Kasdin generator (`osc.h`); the guess runs on the FFT path.

| Profile | L(f) at 1 / 10 / 100 / 1k Hz (dBc/Hz, 10 MHz) | ADEV at 1 ms / 10 ms / 0.1 s / 1 s |
| --- | --- | --- |
| Guess (default) | −65 / −95 / −120 / −140 | 1.0e-9 / 1.6e-10 / 9.5e-11 / 9.4e-11 |
| h, 2 terms | −53 / −73 / −93 / −113 | 6.9e-9 / 2.2e-9 / 6.9e-10 / 2.7e-10 |
| h, 3 terms | −49 / −73 / −93 / −113 | 6.9e-9 / 2.2e-9 / 8.5e-10 / 5.7e-10 |

Clock-only residual (no TWTT error, σT = 0): spread of the pulse-mean phase at 1 GHz after compensating with the exchange's own Δf̂.

| Pulse after TWTT | Guess | h, 2 terms | h, 3 terms |
| --- | --- | --- | --- |
| 1 ms | 0.24° | 1.36° | 1.43° |
| 5 ms | 0.56° | 6.48° | 6.69° |
| 20 ms | 1.64° | 21.1° | 21.5° |
| 40 ms | 3.05° | 34.3° (median Gᴄ 0.960) | 35.5° (median Gᴄ 0.955) |
| Δf̂ std from clock noise alone | 0.25–0.32 ppb | 1.5–1.7 ppb | 2.0–2.4 ppb |

With TWTT error at 27 dB and the pulse at 1 ms, the profile hardly matters: phase std 7.27 / 7.32 / 7.64° at the bound and 23.0 / 23.0 / 23.8° at 3.17×. The Δf̂ spread does change, 0.69 / 1.64 / 2.44 ppb at the bound and 2.02 / 2.46 / 3.14 ppb at 3.17× (paper: 2.04 ppb).

- The "oscillator and PLL add about 1°" result holds only for the guessed reference. With the published typical-TCXO coefficients the clock adds about 6.5° at 5 ms and 34–36° at 40 ms, comparable to the TWTT error, and late pulses lose much more coherence.
- The two bracket the likely truth rather than settle it. The h-coefficients are a timekeeping fit, and their white FM term runs on to offsets where real TCXOs are quieter (−113 dBc/Hz at 1 kHz). Most of the reference's effect comes from below PLL1's 50 Hz loop bandwidth, where the two profiles differ by about 12–22 dB.
- At 3.17× the h profiles give a Δf̂ spread of 2.5–3.1 ppb, above the paper's 2.04 ppb; the guess gives 2.02 ppb. Either the X310 reference is quieter than the typical-TCXO coefficients, or less of the paper's error is TWTT excess. A measured profile would decide.
- An earlier run of this section generated the h profiles as L(f) tables on the FFT path; its numbers (e.g. 7.24° at 5 ms, 36.5° at 40 ms for 3 terms) agree with these within run-to-run scatter, as expected over milliseconds.

### Long-record wander: Kasdin vs. FFT generation

Section 6 of `run_studies.m`. The 3-term profile generated both ways; overlapping ADEV of the SYS clock's slow part over 105 s records, mean of 4 seeds, against the h-model σ_y² = h0/(2τ) + 2 ln2·h₋₁ + (2π²/3)·h₋₂·τ.

| τ (s) | 0.1 | 1 | 5 | 10 | 25 |
| --- | --- | --- | --- | --- | --- |
| h-model | 8.5e-10 | 5.7e-10 | 6.2e-10 | 7.1e-10 | 9.4e-10 |
| Kasdin (`osc.h`) | 8.8e-10 (1.0) | 5.6e-10 (0.99) | 6.4e-10 (1.0) | 7.4e-10 (1.0) | 1.0e-9 (1.1) |
| FFT (L table) | 8.8e-10 (1.0) | 5.3e-10 (0.94) | 5.9e-10 (0.94) | 6.3e-10 (0.89) | 5.9e-10 (0.63) |

Ratios to the h-model in brackets. Kasdin follows the random-walk rise out to τ = T/4; FFT generation loses it from a few seconds on and is 37% low at T/4. Use `osc.h` for holdover and any ADEV at τ comparable to the record.

## Open questions

- The reference oscillator profile sets the clock's contribution at pulse delays of 5 ms and more (see above); it needs a measured X310 TCXO profile.

- A 23° Gaussian phase spread gives a median Gᴄ of about 0.98, below the paper's "above 99%". The paper's figure may come from its best-SNR or optimized runs; check against the Fig. 11 data.
- The 3.17× excess is fitted to one paper point. A fixed hardware floor added to the bound would behave differently at low SNR; the paper's Fig. 11 data would decide between the two.
