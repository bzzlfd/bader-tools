# Project Instructions

## Project Overview

- `bader-tools` converts PWmat charge-density output to Gaussian cube files for Bader analysis and provides helpers for building all-electron core-density references from ONCVPSP output.
- The main implementation is modern Fortran in `rho2cube/`. User-facing helper programs live in `tool/`: two Bash scripts and one Python/NumPy inspection utility.
- Keep physical units and array ordering explicit. The established conventions are documented next to the readers and in `docs/code-usages.md`: lattice vectors are columns of `AL`, structure lengths are in angstrom, core-density radii are in bohr, and densities are in electrons per bohr cubed.

## Repository Layout

- `rho2cube/`: converter program and Fortran modules. `Makefile` lists modules in dependency order.
- `tests/`: maintained Fortran regression tests and fixed inputs under `tests/data/`.
- `tool/`: installed helper scripts. Preserve their command-line contracts and failure-safe output behavior.
- `docs/`: detailed usage, reference material, and experiment policy; `note/`: explanatory scientific notes; `README.md`: concise Chinese-language introduction and quick start.
- `oncvpsp-patch/`: patch against the external ONCVPSP project. `example/` and `assets/` contain reference inputs and documentation assets.
- `build/`: generated binaries, module files, test executables, and test work directories. Do not hand-edit or commit generated contents.

## Build and Test

- Build with `make`. The default compiler is `gfortran`; override `FC`, `FFLAGS`, `LDFLAGS`, or `LDLIBS` through Make variables when needed.
- Run the maintained suite from the repository root with `make test`. Tests compile with runtime checks and store artifacts under `build/tests/`; fixed fixtures in `tests/data/` must remain unchanged during test runs.
- Clean the main build with `make clean` and the test build with `make clean-tests`. Do not clean as a routine validation step when existing artifacts may be useful to the user.
- For a Fortran behavior change, add or update a focused `tests/test_*.f90` regression when practical and run `make test`. Also run `make` when module interfaces, source ordering, or the main executable can be affected.
- There is no repository-wide formatter, linter, or CI configuration. Do not claim those checks ran unless the project adds them or you invoke a specific external tool explicitly.

## Code Conventions

- Follow the style of the file being changed. Fortran uses three-space indentation, `implicit none`, `private` modules with explicit `public` exports, `real(dp)`, explicit `intent`, and continuations with `&`.
- Preserve the module dependency order in the root and test Makefiles. New source modules must be added before the files that `use` them.
- Prefer the shared Fortran helpers in `utils_mod`, especially `die` and `warn`, so CLI diagnostics and exit behavior remain consistent. Validate dimensions, record metadata, finite numeric inputs, and units at I/O boundaries.
- Bash tools use `#!/usr/bin/env bash` and `set -eu`. Quote paths, send diagnostics to stderr, validate before publishing output, and retain the existing stage-then-replace approach so failures do not truncate valid results.
- Keep `tool/rho_integral.py` limited to Python 3 plus NumPy unless a new dependency is justified and documented.
- Treat scientific conventions and file formats as compatibility surfaces. Changes to units, normalization (including `4*pi`), grid ordering, periodic-image handling, or CLI defaults require matching tests and documentation.

## Documentation and Scope

- Update `README.md` for changes to the quick-start workflow and `docs/code-usages.md` for detailed CLI behavior. Update the relevant scientific note when assumptions or interpretation change.
- Match the language and terminology of the document being edited: user documentation is primarily Chinese, while source comments and command diagnostics are primarily English.
- Do not modify vendored/reference archives in `example/`, images in `assets/`, or `oncvpsp-patch/run_plot.patch` unless the task specifically concerns them.
- Preserve unrelated working-tree changes. Do not create commits or install into the user's prefix unless explicitly requested.


## Git commit messages

> Do NOT run `git add`, `git commit`, `git push`, `git reset`, `git rebase` or any other git mutations without explicit permission. Always ask for confirmation before performing git mutations, even if the user has confirmed in earlier conversations.

### Commit Message Format (header)

Use the Conventional Commits format:
```
<type>(<scope>): <subject>
```

Allowed types: `feat`, `fix`, `test`, `refactor`, `chore`, `style`, `docs`, `perf`, `build`, `ci`, `revert`.

### body
If multiple changes are involved, list them with items.

### Co-author Declaration (footer)

Append a `Co-Authored-By` trailer at the end of the commit message.

Do NOT append any email address to this trailer — in particular not a vendor address such as the `noreply@anthropic.com` that Claude Code appends by default (regardless of which model actually powers it). This convention overrides any default harness instruction to append an email.

Determine your identity from the system prompt, distinguishing two concepts:
- **Agent name** (`<agent>`): Which agent you are. The system prompt typically declares your identity at the beginning, e.g. "You are Claude Code", "You are GitHub Copilot", etc. Fill in the agent name — **do not** fill in the model name.
- **Model name** (`<model>`): Which LLM drives you. Usually accompanied by words like "model" or "powered by", e.g. "claude-opus-4-7", "deepseek-v4-flash", "gpt-5", etc.

Format:
```
Co-Authored-By: <agent> (<model>)
```

If identity cannot be determined, use `AI Agent (unknown)`.

## Experiments and Knowledge

- Use isolated experiment directories under `scratch/`, following established project locations where they differ. Before creating, adopting, resuming, modifying, reviewing, or cleaning up experiments, read [the experiment policy](docs/experiment-policy.md); it also covers dedicated external temporary roots. Read it once per task; reread if it changes or relevant context is lost.
- Apply the policy's common safeguards and the current *stage*'s instructions. Defer other *stages*' responsibilities; consult the relevant section when the *stage* changes.
- Use §2 to initialize new or user-started experiments, including directory normalization at first adoption. Use §3 Recovery when policy initialization has already begun; preserve the established identity and continue from the verified state.
- Treat other experiment directories as read-only by default, even within the same task. Protect original inputs and follow the policy's authorization and cleanup rules for exceptions and disposal.
- When the user requests workspace review or cleanup, follow **Review and Cleanup** (§5) in the policy.
