# CLAUDE.md

MATLAB model of two free-running SDR clocks with oscillator and PLL phase noise, synchronized by two-way time transfer, after Merlo et al., IEEE TMTT 74(2), 2026. Read `README.md` first, then `docs/MODEL.md` (method) and `docs/RESULTS.md` (current numbers).

## Environment

- Windows laptop, MATLAB R2026b at `D:\ProgramFiles\bin\matlab.exe`, with Signal Processing, Communications, DSP System, RF, Optimization, Statistics, Control System and Simulink. This project uses only MATLAB and Signal Processing.
- Run MATLAB headless from the repo folder:
  `& "D:\ProgramFiles\bin\matlab.exe" -batch "run_studies"`
  Each `-batch` call starts MATLAB fresh (20–30 s), so put several runs in one script rather than calling MATLAB many times.
- Scripts write a `*_log.txt` with `diary`. Read the log for results instead of parsing console output.
- RAM is tight (about 3 GB free with MATLAB open). Keep arrays well under 1 GB; a 100 s two-rate run is fine, single-rate runs longer than about 1 s at 4 MHz are not.

## Where things live

- This folder is inside OneDrive (`C:\Users\umutt\OneDrive\Documents\MATLAB\ClockModel`). Never write large outputs here; C: has only about 13 GB free.
- Paths come from `clockmodel_paths.m` (env vars `CLOCKMODEL_DATA` / `MERLO_FLOW_DIR`, else the untracked `clockmodel_config.m`, else `<repo>\output`). On this laptop `clockmodel_config.m` points both at `D:\`; never let outputs fall back to `<repo>\output` here.
- Outputs go to `D:\ClockModelData` (local drive, not synced): model runs at the top level, `comparison\` from `compare_merlo_flow.m`, `studies\` from `run_studies.m`.
- merlo_flow (read-only reference) is extracted at `D:\ClockModelData\merlo-flow-main`. Its zip, `merlo-flow-main.zip`, is also in this folder.
- The paper and its appendix PDFs are in the claude.ai project "Oscillator Phase Noise Model and Clock Generation", along with copies of the scripts. The written comparison with charts is the claude.ai doc "Clock model vs. merlo_flow vs. Merlo 2026".

## Ground rules

- **merlo_flow belongs to someone else** (private repo `prettysick/merlo-flow`). Read and run it only from the extracted copy. Never modify it, never copy its code into this repo, and never commit the zip or the extracted folder. `chain_x310_from_merlo_flow.m` reads its parameters at run time; that is the only coupling.
- **Never commit the paper PDFs**; cite the DOI.
- **Run before you report.** Only put a number in a doc after running the MATLAB that produces it, and update `docs/RESULTS.md` when results change.
- Equation, table and figure numbers refer to the paper. Ground modeling choices in the paper, its appendix, or datasheets, and say which.
- Coherent gain and residual phase are evaluated at the **1.0 GHz beamforming carrier** (Table I), not the 2.1 GHz TWTT LO.

## Code conventions

- `sdr_clock_model_tworate(opts)` is a function with a defaults block at the top. Add a new behavior as an `opts` field with a default that keeps the existing results, rather than changing defaults silently. `compare_merlo_flow.m` relies on `timing = 'fixed'`.
- Noise chains are stage lists (`type`, `kappa`, `fn`, `zeta`, `Svco`, `Sinb`, `Sfloor`, plus `i_sys`, `sys_div`); see `default_chain` in the model and `docs/MODEL.md`.
- Keep the PSD self-check (`res.psd_err_dB`) passing: within about ±0.1 dB over 1 Hz–1 MHz. A larger value means the generator or a chain is wrong.
- `paramsOnly = true` returns parameters, the CRLB and `analytic_psd` without simulating; use it for quick checks.
- Scripts start with `clear`, which wipes workspace variables (including timers set before calling them).

## Known gotchas

- If an `.m` file is open in the MATLAB editor while it is changed on disk, MATLAB can keep running the old version. Close the tab, or run `clear functions; rehash` before rerunning.
- Huawei PC Manager (`hwmdcui.exe`) sometimes takes window focus; irrelevant in `-batch` mode.

## Open items (in priority order)

1. Estimate Δf over several exchanges (longer baseline or Kalman filter) instead of from two timestamps, to cut the late-epoch coherence loss.
2. Decide between a multiplicative CRLB excess (`crlb_excess`) and a fixed hardware floor, using the paper's Fig. 11 data.
3. Replace the guessed TCXO reference profile with measured data (the Collmann X310 dataset on IEEE DataPort is subscription-only).
4. Possible later: vibration term, separate TX/RX LOs, N > 2 nodes.

## Before pushing to GitHub

- Check `.gitignore` covers the zip, logs, `.mat`, `.fig` and `.asv` files.
- Confirm there is no merlo_flow code or data in the commit (`git status`, `git diff --cached --stat`).
- A LICENSE has not been chosen yet; ask the owner.
