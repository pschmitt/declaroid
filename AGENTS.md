# Agent Guide

## What this is

`declaroid` is a single bash script (repo root, no extension) that installs
and uninstalls Android apps on a device from a declarative YAML config, using
`gplaydl` (Google Play), `fdroidcl` (F-Droid), or GitHub release assets as
the source. Packaged via `flake.nix` + `pkgs/declaroid` (a `makeWrapper`
derivation) and `pkgs/gplaydl` (not in nixpkgs, so vendored here).

## Keep the README up to date

**Whenever you change a flag, subcommand, config field, default path, cache
behavior, or store's fetch/install mechanics in `declaroid`, update
`README.md` in the same change.** The README is the only documentation this
project has; treat a behavior change that isn't reflected there as an
incomplete change, not a follow-up.

## Working on the script

- Style: see the `shell` conventions this author uses elsewhere -- 2-space
  indent, `then`/`do` on their own line, `[[ ]]` not `[ ]`, functions as
  `name() { }`, no `exit` inside functions (use `return`), a `main()` guarded
  by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`.
- Run `shellcheck declaroid` after any change and fix everything it flags
  (or add a targeted `# shellcheck disable=SC####` with a comment on *why*,
  as already done for the two `yq` expressions using `$d` -- that's a yq
  variable, not a bash one, and the false positive is intentional).
- **Log messages go to stderr, data goes to stdout.** Every function whose
  return value is captured via `$(...)` (`fetch_app`, `resolve_devices`,
  `cache_dir_for`, etc.) must not let anything else leak onto stdout --
  including any external command it shells out to (see `fetch_app`'s
  `gplaydl download ... >&2`). Getting this wrong once already broke the
  cache-hit path silently (corrupted the captured path with progress-bar
  output); don't reintroduce it.
- **Never feed a `while read` loop from a process substitution and then run
  an interactive/stdin-touching command inside the loop body without
  redirecting its stdin away.** `adb shell` is the concrete case here (see
  `is_installed`'s `</dev/null`); it silently consumes the loop's remaining
  input otherwise, truncating iteration after the first entry. The `for_each_app`
  loop reads from fd 3, not stdin, specifically so nothing in the loop body
  can ever repeat that bug.
- Test against a real adb device when touching install/uninstall/cache
  logic, not just `--dry-run` -- `--dry-run` does not exercise the actual
  download/cache/install code paths and has previously let bugs through.

## Nix packaging

- `pkgs/declaroid/default.nix` wraps the script with `makeWrapper`, prefixing
  `PATH` with every runtime dependency (`android-tools`, `yq-go`, `gplaydl`,
  `fdroidcl`, `curl`, `jq`, coreutils, etc). If the script starts shelling
  out to something new, add it there.
- `pkgs/gplaydl/default.nix` tracks upstream releases from
  https://github.com/rehmatworks/gplaydl (PyPI package `gplaydl`). Bump
  `version` and `hash` together; get the hash via
  `nix hash convert --to sri sha256:<hex from PyPI JSON API>` or by letting a
  build fail once and copying the hash from the mismatch.
- `fdroidcl` is `Hoverth/fdroidcl`, already packaged in nixpkgs as
  `pkgs.fdroidcl` -- don't vendor it.
