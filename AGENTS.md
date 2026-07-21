# Agent Guide

## What this is

`declaroid` is a single bash script (repo root, no extension) that installs
and uninstalls Android apps on a device from a declarative YAML config, using
`gplaydl` (Google Play), `fdroidcl` (F-Droid), a GitHub repo's release
assets, or a local APK file as the source. Packaged via `flake.nix` +
`pkgs/declaroid` (a `makeWrapper` derivation) and `pkgs/gplaydl` (not in
nixpkgs, so vendored here). Zsh completion lives at `completions/_declaroid`.

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
  Specifically: `--dry-run` never exposed either of the two bugs below --
  both only showed up on a real `install`.
- **Per-app data flows through `CURRENT_NAME`/`CURRENT_PKG`/`CURRENT_STORE`/
  `CURRENT_REPO`/`CURRENT_ASSET`/`CURRENT_PATH`, not positional arguments.**
  `for_each_app` sets these (via a plain, non-`local` `read`, so they're
  visible to whatever it calls) before invoking `app_fn`; `install_app`,
  `uninstall_app`, and the per-store `install_*` functions are all
  effectively zero-arg and just read these plus `DEVICE_SERIAL`/`DRY_RUN`/
  `FORCE_DOWNLOAD` (set once per device/run by `cmd_install`/`cmd_uninstall`).
  This replaced a positional chain that had grown to 8-9 params and was
  getting worse with every store added -- don't bring positional args back
  for this data; add a new `CURRENT_*` variable instead. Values that are
  genuinely computed/local (a resolved cache dir, a list of matched APK
  files) should stay real function arguments, not `CURRENT_*` -- that
  convention is specifically for per-app config data and run-wide context.
- **The TSV-ish rows `app_rows` emits are joined with `§` (U+00A7), not a
  real tab.** `repo`/`asset`/`path` are legitimately empty for most stores,
  and bash's `read` collapses consecutive *whitespace* IFS delimiters --
  tab included -- no matter what you set `IFS` to; there is no way to make
  `IFS=$'\t' read` preserve an empty field between two tabs. This silently
  shifted every field after the first empty one, which broke `github` and
  `local` (both depend on fields that are empty for other stores) while
  `gplay`/`fdroid` looked fine, since neither of them reads the
  shifted-into-garbage fields. If you add a new per-app config field, put it
  in `app_rows`'s `join("§")` list and read it out with `IFS='§' read`
  (already done in `for_each_app` and `cmd_diff`) -- never `IFS=$'\t'`.
- **Don't use `compgen`.** Nixpkgs' plain `bash` (what the packaged
  `declaroid` actually runs under once wrapped) is built without
  programmable-completion support, so `compgen` doesn't exist there even
  though it works fine in an interactive dev shell. Use `has_apk_files()`
  (array-glob + `[[ -e "${arr[0]}" ]]`) for "does this dir have any APKs",
  and `find "$(dirname -- "$p")" -name "$(basename -- "$p")"` for "expand
  this possibly-glob, possibly-literal path" -- see `install_local`. This
  class of bug will not show up when testing against your own interactive
  shell; it only shows up running the actual Nix-built binary.
- `is_system_plumbing_pkg` (used by `generate-config`) is a best-effort,
  hand-maintained denylist of GMS/AOSP package IDs that show up in
  `pm list packages -3` despite not being real apps (they get updated via
  Play but never lose their system-plumbing nature). There is no reliable
  *technical* signal to detect these -- their install path is `/data/app/…`
  just like a real sideloaded app once updated, so path-based detection
  doesn't work either (checked and ruled out). If a new one shows up in
  someone's `generate-config` output, add its exact package ID to the case
  statement; don't switch to a path- or prefix-based heuristic without
  re-verifying against real device output first.
- **`generate-config` entries that would fail a real `install` are written
  out commented out, with a `# TODO: <reason>` line above them** -- not
  emitted active with `store` silently defaulted to `gplay`. Concretely:
  unknown-store entries (no way to tell `local`/`fdroid`/`github` apart) and
  `github` entries with an empty `repo: ""` placeholder (Obtainium doesn't
  expose the source repo). The point is that feeding a freshly generated
  config straight into `install` should never itself produce errors; if you
  add a new "we don't actually have enough info" case, comment it out the
  same way rather than emitting a guess.
- **`adb install -i <id>`'s installer attribution only sticks if `<id>` is a
  real, currently-installed package** -- tested against a real device with a
  made-up id ("declaroid.store.whatever"), which silently ends up
  installer=null, same as passing no `-i` at all. This is why declaroid only
  ever passes `-i com.android.vending` (gplay, genuinely always installed)
  and never a synthetic "this came from declaroid" id for github/local --
  there's no existing package it could truthfully claim to be. Don't
  reintroduce a synthetic installer id without re-verifying this; it looked
  like a good idea and silently does nothing.
- **`adb install-multiple -i <id>` hangs**, tested twice with different flag
  orders, real installer id, real device -- not a rejection, an actual hang.
  `install`'s `-i` works fine; `install-multiple`'s doesn't. This is why `-i`
  is only ever used for the single-remaining-file-after-dedup case in
  `install_apk_files`, routed through plain `install` instead of
  `install-multiple`. See that function's comment before touching this.
- **`wait -n` returns the exit status of whichever backgrounded job just
  finished, and `set -e` treats that as a script failure.** `generate-config`
  parallelizes label resolution with a `job & ... wait -n`-based semaphore
  (see `cmd_generate_config`); since `resolve_app_label` failing for any
  given app is normal (not every package has a base.apk that's readable/
  present), the very first job to fail silently killed the whole command --
  no error message, just a truncated/empty result, because `set -e` fired
  inside a command substitution and nothing surfaced it. Plain `wait` (no
  args, waiting for everything) is fine and always returns 0 regardless of
  child exit codes; only `wait -n` needs the `|| true`. Confirmed both ways
  with a two-line repro before and after the fix -- don't trust reasoning
  about this from bash's docs alone, it's exactly the kind of interaction
  that's easy to get backwards.
- **`adb install`/`install-multiple` without `--user` is not reliably "the
  current profile" on a device with a secondary Android user profile** (a
  Work Profile, [Island](https://github.com/oasisfeng/island), a second full
  user account). Confirmed on a real device (`pm list users` showed user 0
  "personal" + user 10 an Island-managed profile): a single-APK `adb
  install` with no `--user` landed the app in *both* profiles, while an
  `adb install-multiple` with no `--user`, same device, same session,
  landed it in *only* the secondary profile -- not even consistent with
  itself between the two install commands. `resolve_target_user` (`adb
  shell am get-current-user`) plus always passing `--user` explicitly (see
  `effective_target_user`, and install_apk_files/install_github/
  install_fdroid's calls) is what makes this deterministic. Don't drop the
  explicit `--user` and rely on the adb/pm default again without re-testing
  against a real multi-profile device -- the "obvious" fallback behavior
  demonstrably isn't there.
- `profile: all` (or a specific id) in the config takes priority over the
  auto-detected current profile (see `effective_target_user`) -- but the
  *unset* case must keep resolving to the single auto-detected profile, not
  "all". Installing into every profile has to be an explicit per-app choice.
- `generate-config`'s profile detection enumerates every profile up front
  (`pm list users`) and does one bulk `pm list packages ... --user <id>`
  call *per profile*, not one call per (app, profile) pair -- don't rewrite
  this into a per-app loop that shells out to adb per profile per package,
  it'll be needlessly slow for a device with many apps. If an app turns up
  in more than one enumerated profile but not literally all of them, it
  still gets `profile: all` (the closest value a single `--user` flag can
  express) rather than trying to encode a specific subset.
- `--sort-by` (`cmd_diff`, `cmd_devices`) pipes the *data rows only* through
  `sort -t $'\t' -k<N>,<N> -f` -- the header row (`printf` outside that
  inner pipe) must never enter the sort, or it'll end up sorted into the
  data instead of staying first. `-f` gives case-insensitive comparison.

## Nix packaging

- `pkgs/declaroid/default.nix` wraps the script with `makeWrapper`, prefixing
  `PATH` with every runtime dependency (`android-tools`, `yq-go`, `gplaydl`,
  `fdroidcl`, `curl`, `jq`, `util-linux` for `column`, `aapt` -- which,
  confusingly, only actually provides an `aapt2` binary -- for
  `generate-config`'s name resolution, coreutils, etc) and installs
  `completions/_declaroid` to `share/zsh/site-functions/_declaroid`.
  If the script starts shelling out to something new, add it to the
  `makeBinPath` list too -- and remember the wrapped runtime is plain
  nixpkgs `bash`, not your interactive shell's bash (see the `compgen` note
  above).
- `pkgs/gplaydl/default.nix` tracks upstream releases from
  https://github.com/rehmatworks/gplaydl (PyPI package `gplaydl`). Bump
  `version` and `hash` together; get the hash via
  `nix hash convert --to sri sha256:<hex from PyPI JSON API>` or by letting a
  build fail once and copying the hash from the mismatch.
- `fdroidcl` is `Hoverth/fdroidcl`, already packaged in nixpkgs as
  `pkgs.fdroidcl` -- don't vendor it.
