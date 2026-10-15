# SDR clock model

A MATLAB model of two free-running software-defined-radio nodes whose clocks carry realistic oscillator and PLL phase noise, synchronized by two-way time transfer (TWTT). It follows the signal model of Merlo et al. (2026) and predicts time error, frequency error, residual carrier phase and coherent gain for a two-node coherent distributed array.

> J. M. Merlo, S. Wagner, J. B. Lancaster, J. A. Nanzer, "Real-Time High-Accuracy Digital Wireless Time, Frequency, and Phase Calibration for Coherent Distributed Antenna Arrays," *IEEE Trans. Microw. Theory Techn.*, vol. 74, no. 2, Feb. 2026. [doi:10.1109/TMTT.2025.3639461](https://doi.org/10.1109/TMTT.2025.3639461)

Equation, table and figure numbers in the code and docs refer to that paper.

## Requirements

- MATLAB (developed and tested on R2026b)
- Signal Processing Toolbox (`pwelch`, `hann`)
- About 1 GB of free RAM for a 100 s run
- Optional: a local copy of [merlo_flow](#merlo_flow-dependency), only for the X310 + UBX-160 noise chain and for `compare_merlo_flow.m`

## Quick start

```matlab
% 100 s run: default noise chain, TWTT error from the CRLB at 27 dB,
% 1 GHz beamforming pulses 1 ms after each exchange. Saves a .mat and .fig to outDir.
res = sdr_clock_model_tworate();

% 20 s run, nothing saved
res = sdr_clock_model_tworate(struct('T_req', 20, 'saveResults', false));

% X310 + UBX-160 chain (needs the merlo_flow copy), paper-level timing error
ch  = chain_x310_from_merlo_flow();   % merlo_flow folder from clockmodel_paths
res = sdr_clock_model_tworate(struct('chain', ch, 'crlb_excess', 3.17));
```

Headless, from a terminal:

```powershell
matlab -batch "res = sdr_clock_model_tworate(struct('T_req', 20, 'saveResults', false))"
```

### Main options (`opts` fields)

| Field | Default | Meaning |
| --- | --- | --- |
| `T_req` | 100 | Record length (s); rounded up to a power-of-two sample count |
| `chain` | `[]` | Noise chain from the 10 MHz reference to the LO; `[]` = built-in two-PLL tables |
| `osc` | TCXO-like `L(f)` table | Reference-oscillator phase noise at `osc.f0` = 10 MHz |
| `timing` | `'crlb'` | `'crlb'`: TWTT error from Eqs. 22, 24 at `snr_dB`; `'fixed'`: use `sigT` |
| `snr_dB` | 27 | Pre-integration SNR of each TWTT pulse (dB) |
| `crlb_excess` | 1 | Estimator std / CRLB std (3.17 reproduces the paper's ~65 ps at 27 dB) |
| `sigT` | 30e-12 | TWTT time-error std (s) when `timing = 'fixed'` |
| `tau_twtt` | 44e-3 | Resynchronization interval (s) |
| `f_bf`, `L_bf`, `t_bf` | 1e9, 2e-6, 1e-3 | Beamforming carrier (Hz), pulse length (s), pulse start after each TWTT (s, 0 to `tau_twtt`) |
| `static_tau` | 0 | Uncalibrated static time offset between nodes (s) |
| `outDir`, `saveResults`, `makeFigures`, `verbose` | `''` (= data folder, see [Paths](#paths)), true, true, true | Output control |
| `paramsOnly` | false | Return parameters, CRLB and the analytic PSD handle without simulating |

The result struct `res` holds the summary metrics (`time_std`, `df_std`, `phase_std_deg`, `Gc_median`, `Gc_p5`, ...), a per-epoch table `res.epoch`, the PSD self-check `res.psd` / `res.psd_err_dB`, and `res.analytic_psd(f)`, which returns `[S_osc, S_sys, S_lo]` in rad²/Hz.

## Files

| File | What it is |
| --- | --- |
| `sdr_clock_model_tworate.m` | The model: two-rate phase-noise generator, stage-list noise chain, TWTT, frequency estimate, carrier compensation, coherent gain |
| `chain_x310_from_merlo_flow.m` | Builds the X310 + UBX-160 chain from merlo_flow's datasheet parameters (read-only use) |
| `compare_merlo_flow.m` | Comparison against merlo_flow and the paper (noise models, LO wander, end-to-end metrics) |
| `run_studies.m` | Follow-up studies: CRLB check, X310 chain check, SNR sweep, pulse-timing sweep |
| `clockmodel_paths.m`, `clockmodel_config_example.m` | Per-machine data and merlo_flow folders (see [Paths](#paths)) |
| `sdr_clock_model.m` | First single-rate version (kept for reference; superseded by the two-rate model) |
| `docs/MODEL.md` | How the model works, its assumptions and limits |
| `docs/RESULTS.md` | Comparison and study results, with the numbers and where they come from |
| `RULES.md` | Design rules for changes: keep code small, efficient and consistent |
| `CLAUDE.md` | Working notes for Claude Code sessions on this repo |

## Outputs

## Paths

Two folders are set per machine and resolved by `clockmodel_paths.m`:

| Folder | Environment variable | `clockmodel_config.m` field | Default |
| --- | --- | --- | --- |
| Data (outputs) | `CLOCKMODEL_DATA` | `data` | `<repo>\output` |
| merlo_flow copy | `MERLO_FLOW_DIR` | `mf` | `<data>\merlo-flow-main\merlo_flow` |

Environment variables win over the config file. To use the file, copy `clockmodel_config_example.m` to `clockmodel_config.m`, rename the function inside, and edit the paths; git ignores it. Point the data folder somewhere with space that is not synced, since a 100 s run writes about 80 MB. From MATLAB, `setenv('CLOCKMODEL_DATA', 'E:\clock-out')` works for one session.

Large results are written to the data folder (or to `opts.outDir` if given): timestamped `.mat` / `.fig` files from the model, `comparison\` from `compare_merlo_flow.m`, and `studies\` from `run_studies.m`. Each script also writes a `*_log.txt` there with everything it printed.

## Results at a glance

Details and sources: [docs/RESULTS.md](docs/RESULTS.md).

- With the same inputs, this model and merlo_flow agree on median coherent gain to 0.2% (0.990 vs 0.991).
- The paper's reported spreads (about 65 ps, 23° and 2 ppb at 27 dB) are reproduced by a TWTT time error of 3.2× the CRLB. Oscillator and PLL noise add only about 1° at 5 ms.
- Median coherent gain passes 0.99 at 21 dB SNR at the CRLB, but needs 30 dB at paper-level error.
- Coherence falls the later a pulse fires in the 44 ms epoch, because Δf comes from two noisy timestamps. At paper-level error the median drops from 0.98 to 0.91.

## merlo_flow dependency

`chain_x310_from_merlo_flow.m` and `compare_merlo_flow.m` read [prettysick/merlo-flow](https://github.com/prettysick/merlo-flow), a private repository owned by someone else. It is used read-only, from a local copy whose location is set as in [Paths](#paths). It is not part of this repository and must not be committed here. The core model runs without it.

## Status

Done and verified: two-rate generator, stage-list noise chain with the X310 option, CRLB-based timing error, pulse timing anywhere in the epoch, the 1 GHz beamforming carrier (Table I).

Open:
- Estimate Δf over several exchanges (longer baseline or Kalman filter) to cut the late-epoch loss.
- Replace the guessed TCXO reference profile with measured data.
- Decide between a multiplicative CRLB excess and a fixed hardware floor using the paper's Fig. 11 data.
