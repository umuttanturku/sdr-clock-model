# Design rules

How code in this repo should be written. These apply to every change, by a person or by Claude. Project facts, paths and ground rules (merlo_flow, paper PDFs, run-before-you-report) are in `CLAUDE.md`; this file is about the shape of the code.

## Keep it small

- Solve the problem in front of you. No speculative options, hooks or generality "for later"; add them when a second real use appears.
- Prefer editing an existing function over adding a new one. Before writing a helper, search the repo for one that already does it (`grep`), and check whether MATLAB or the Signal Processing Toolbox already has it.
- No near-duplicate functions. If two functions differ by a parameter, make it one function with that parameter. If a new version supersedes an old one, delete the old one or mark it as kept for reference (as `sdr_clock_model.m` is), never keep both live.
- A local function at the bottom of the file that uses it beats a new file. Create a new `.m` file only when two or more files need it.
- No wrapper functions that only rename or forward arguments.
- Delete dead code, unused variables and commented-out blocks rather than leaving them. Git keeps the history.

## Keep it efficient

- Memory is the tight constraint (about 3 GB free). Estimate array sizes before allocating; keep any single array well under 1 GB. Generate long records in blocks or at a lower rate, as the two-rate model does, instead of at full rate.
- Vectorize where it is clear. Use loops where vectorizing would build a large temporary or hide the logic; preallocate anything grown in a loop.
- Don't recompute in a loop what can be computed once outside it (PSD tables, filter responses, chain products).
- Save only what a later step reads. Use `paramsOnly` or short `T_req` runs for checks; reserve long runs for results that go into the docs.
- Use built-in functions (`pwelch`, `interp1`, `fft`, `cumsum`) rather than reimplementing them.

## Keep it consistent

- Match the surrounding code: naming, comment density, the `opts` defaults pattern, stage-list chains.
- New behavior goes in as an `opts` field whose default keeps existing results unchanged (see `CLAUDE.md`).
- One source of truth for each number or path: parameters in the defaults block, paths in `clockmodel_paths.m`, results in `docs/RESULTS.md`. Reference them; don't copy them.
- Comments say why, or which paper equation, table or datasheet a value comes from. Don't restate what the code does.

## Dependencies

- MATLAB and the Signal Processing Toolbox only. Adding another toolbox or third-party code needs the owner's agreement first.
- Never copy code from merlo_flow; read its parameters at run time only (see `CLAUDE.md`).

## Before calling a change done

- It runs headless (`matlab -batch`) and the PSD self-check (`res.psd_err_dB`) stays within about ±0.1 dB on a run long enough to judge it (20 s or more).
- The diff contains no new function that duplicates an existing one, no unused code, and no files that should be ignored.
- If the change alters behavior or results, `README.md`, `docs/MODEL.md` or `docs/RESULTS.md` is updated in the same change.
