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
  express) rather than trying to encode a specific subset. **The "all"
  check must be guarded by `${#profile_ids[@]} -gt 1`** -- on a
  single-profile device, every found app trivially has `app_profiles`
  length 1, which satisfies `-ge ${#profile_ids[@]}` (also 1) for every
  single app, so nearly the whole config came out `profile: all` on a real
  single-profile device before this guard was added (24 of 25 apps).
  `profile_field` must stay unset whenever there's only one profile to
  begin with -- there's nothing to distinguish.
- `--sort-by` (`cmd_diff`, `cmd_devices`) pipes the *data rows only* through
  `sort -t $'\t' -k<N>,<N> -f` -- the header row (`printf` outside that
  inner pipe) must never enter the sort, or it'll end up sorted into the
  data instead of staying first. `-f` gives case-insensitive comparison.
- **Never write `while read ... < <(process substitution)` anywhere in this
  script -- always `mapfile -t arr < <(cmd)` followed by a plain `for` loop
  instead.** `load_profile_aliases` used the `while read` form and worked
  fine when run as the raw script under an interactive bash, but silently
  killed the entire `install` command (no error, just exit 1) when run
  through the packaged/wrapped nix binary -- traced by diffing four
  combinations of {raw source, wrapped binary} x {interactive PATH, wrapped
  PATH} until the failure was isolated to that exact construct under the
  wrapped bash's execution context. The root cause was never fully pinned
  down mechanistically, but the fix (switch to `mapfile` + `for`, as
  `for_each_app`/`cmd_diff`/`list_extra_pkgs` already did) reliably resolved
  it, and this class of bug -- like the `compgen` one above -- will not show
  up in interactive-shell testing. Treat `while read <(...)` as banned in
  this codebase, not just a style preference.
- `list_extra_pkgs` (shared by `diff --full` and `install --enforce`) finds
  device-installed, non-plumbing packages absent from the config via a
  single `pm list packages -3` call with no `--user` -- it isn't trying to
  be precise about *which* profile an app lives in like `generate-config`
  is, just "is this pkg configured anywhere at all". `install --enforce`
  prompts once per device for the whole batch of extra packages, not once
  per package, mirroring `cmd_uninstall`'s existing confirmation pattern
  (skippable with the same `-y|--yes|--noconfirm|--no-confirm`).
- `install` builds a plan before touching anything: `build_install_plan`
  does a read-only pass (`is_installed` per configured app, no logging) to
  find what's actually missing on the device, `print_install_plan` shows
  that (pending apps plus a count of already-installed ones) and `cmd_install`
  prompts per device before calling the *existing* `for_each_app "$config"
  install_app` unchanged -- the plan doesn't feed installs directly, it's
  purely a preview/confirm gate in front of the same install path as before.
  `install_app` still re-checks `is_installed` itself during the real pass
  (a second, cheap `pm list packages` call, not worth avoiding); its
  already-installed skip message is now gated on a new `VERBOSE` local
  (`-v|--verbose`, set in `cmd_install` alongside `DRY_RUN`/`FORCE_DOWNLOAD`
  and read the same dynamically-scoped way) so it's silent by default --
  the plan's count already covers that case, no need for per-app spam too.
  `build_install_plan` uses `mapfile` + `for`, not `while read < <(...)`, per
  the ban above.
- **`-t 1` must never be tested inside a function that gets called from
  `$(...)`** -- it reads the tty-ness of the *current* file descriptor 1,
  and inside a command substitution that's always the pipe capturing the
  output, never the real terminal, regardless of what fd 1 was in the
  calling context. `hyperlink()` (used by `cmd_search`) originally did
  `[[ -t 1 ]]` internally and silently never emitted a single OSC 8 link
  even when run in a real terminal -- caught by testing through `script
  -qec` (a real pty) instead of trusting that plain manual testing would
  surface it. Fixed by computing `HYPERLINKS` once at the top level
  alongside the `C_*` color vars (same reasoning as those: a plain variable
  read inside a subshell reflects the value from when it was set, unlike a
  live fd test) and having `hyperlink()` only ever branch on that variable.
  If you add another OSC-code-emitting helper, gate it the same way -- not
  with its own `-t 1` check.
- `search_gplay` parses `gplaydl search`'s only output format: a Rich-
  rendered 3-column table (no `--json`/plain mode exists). Rich sizes
  columns to the terminal width it detects via `shutil.get_terminal_size`
  (confirmed by testing `COLUMNS=40` vs `COLUMNS=1000` against the same
  query), and a pipe/mapfile capture reports width 80 by default, which can
  wrap a long title across multiple box-drawn lines and break the "one
  data row = one output line" assumption -- `COLUMNS=1000` before the call
  avoids this in all realistic cases. Data rows are recognized by starting
  with the *light* vertical bar `│` (U+2502); the header row uses the
  *heavy* `┃` instead, so filtering on the light one skips header/border/
  title lines for free without needing to hardcode a line count to skip.
- `search_fdroid` needs its own client-side result cap -- `fdroidcl search`
  (checked `--help`) has no `--limit`/`-l` flag at all, unlike `gplaydl
  search`. Each result is two lines (an unindented `pkgid  title - version
  (versioncode)` line, then a 4-space-indented summary line, distinguished
  by leading whitespace); a title can itself legitimately contain " - "
  (e.g. an app literally titled "WhatsApp Web To Go - Mobile Client for
  WhatsApp We - 1.7.5 (39)"), so the title/version split uses bash's
  greedy `=~` backtracking (`^(.*) - (.+)$`) to find the *last* " - "
  rather than naively splitting on the first one.
- **Every command that emits a table (`devices`, `diff`, `search`) must go
  through `render_table`, and any per-cell coloring should happen *after*
  it returns (via `colorize_word`), not before.** `colorize_word` only
  touches already-aligned text and can't change a cell's width, so it's
  safe with either renderer (tsvtool or the `column -t` fallback); pre-
  embedding color codes would make the raw byte length of a cell diverge
  from its visible width, which `column -t` can't account for (it doesn't
  understand ANSI at all). `search`'s NAME column is the one necessary
  exception -- each row's OSC 8 hyperlink points at a *different* URL, so
  it can't be expressed as a single fixed-word `colorize_word` pass and has
  to be embedded before rendering.
- **tsvtool strips ANSI/OSC 8 escape sequences out of its input by
  default** (checked its source: `extract_tsv_rows` calls `strip_ansi`
  unless `--keep-escape-sequences`/`-k` is passed) -- `render_table` always
  passes `--keep-escape-sequences` to it now, since `search`'s pre-embedded
  OSC 8 hyperlinks were silently vanishing before this was added (visible
  width was still computed correctly either way, since tsvtool's width
  calculation independently strips-for-measurement regardless of this
  flag; the flag only controls whether the codes survive into the
  *output*). Harmless for devices/diff, which never pre-embed anything for
  tsvtool to strip in the first place.
- **`add`'s duplicate-pkg check used to pipe yq through `| head -1`, and
  that silently killed the whole command.** Under `set -euo pipefail`,
  `head -1` closing its read end after one line can SIGPIPE the upstream
  producer before it's done writing; pipefail then reports that non-zero
  exit as the *pipeline's* status, and since the whole thing was a plain
  assignment (not an `if`/`while` condition), `set -e` aborted the script
  right there with zero error output. Confirmed with a minimal repro
  (`existing="$(cmd | head -1)"` under `set -euo pipefail` swallowing even
  a bare `echo` after it). Fixed by doing the "just the first match" logic
  inside the yq expression itself (`[...] | .[0] // ""`) instead of piping
  through an external process at all -- no pipe, no SIGPIPE risk. This is
  the same failure class as the `wait -n` bug above; the general lesson is
  **never pipe a `set -e`-covered assignment through a command that exits
  before consuming all of its input** (`head`, `sed q`, etc. are all
  suspect).
- **This yq (mikefarah/yq-go) has no jq-style `--arg NAME value` flag at
  all.** `add_app_to_config` originally used `--arg` to pass `$name`/`$pkg`
  into a yq expression, copying jq's convention without checking --
  `yq --arg ...` just errors `unknown flag: --arg` (checked `yq --help`'s
  full flag list, `--arg` isn't in it). The correct mechanism is yq's own
  `env(VAR)` expression function, reading an actual process environment
  variable: `VAR="$val" yq '...env(VAR)...'` (a command-prefix assignment)
  scopes it to just that one invocation. Variable names are prefixed
  `DECLAROID_` to avoid colliding with an unrelated already-set env var.
- **`store: izzyondroid` runs every fdroidcl call through an isolated
  XDG_CONFIG_HOME/XDG_CACHE_HOME, never the user's real fdroidcl config.**
  fdroidcl merges every *enabled* repo in whichever config it's pointed at
  into one combined index -- there's no per-repo scoping in `search`/
  `show`/`install` at all -- and `fdroidcl repo add` isn't idempotent (it
  errors if the name already exists) and permanently mutates that config.
  Registering IzzyOnDroid in the real `~/.config/fdroidcl` would therefore
  leak it into every future plain `store: fdroid` search/install too --
  this isn't hypothetical, it actually happened once while building this
  feature and had to be undone by hand (`fdroidcl repo remove izzyondroid`
  against the real config, plus deleting the stray `izzyondroid.jar`/
  `-etag` files it had already downloaded there). Two things to remember:
  (1) overriding bare `$HOME` alone does **not** redirect fdroidcl -- it
  reads `XDG_CONFIG_HOME`/`XDG_CACHE_HOME` directly, and those were already
  set in the environment, taking priority; both must be overridden
  together, which is what `izzyondroid_fdroidcl()` does. (2) The isolated
  config also has F-Droid's own default repos (`f-droid`, `f-droid-archive`)
  removed from it on first setup, leaving *only* IzzyOnDroid registered --
  this is what makes `search --store izzyondroid` naturally scoped to just
  that repo with zero extra filtering, instead of needing an extra
  `fdroidcl show <pkg>` call per candidate to tell which repo a merged
  result actually came from.
- `fdroidcl setup` looks like it might help with repo management at a
  glance ("mass installs onto an android device, excellent for backups")
  but it's a different feature entirely -- named groups of apps+repos for
  bulk provisioning (fdroidcl's own answer to what declaroid already does
  at a higher level), and its `setup add-repo <NAME> <REPO-NAME>` only
  *references* an already-registered repo by name, it doesn't add a new
  repo URL. There's no shortcut around `fdroidcl repo add` for actually
  registering IzzyOnDroid.
- **A multi-statement `--preview` script for fzf must go in an executable
  temp file, not be inlined as a quoted string.** The preview script's own
  `printf` calls need single-quoted format strings (to keep `\033` etc
  literal), and nesting those inside an outer `bash -c '...'` wrapper
  breaks immediately: the *first* single quote inside the script
  prematurely closes the outer one, spilling the rest of the script out as
  unquoted text for the shell fzf spawns (zsh here) to choke on --
  confirmed via real "bad pattern"/"command not found" errors from zsh
  when tried inline, only visible by actually running the interactive
  picker (a real pty, e.g. via `script -qec` or tmux -- this class of bug
  does not show up from just reading the code). `pick_search_result` writes
  the preview script to `mktemp`, `chmod +x`s it, and points `--preview` at
  the file path directly, sidestepping the quoting-nesting problem
  entirely since there's no shell re-parsing of the script's own content
  involved.
- **`generate-config` writes apps sorted by resolved name, not package id**
  -- `keep_pkgs` is initially pkg-sorted (needed early on so per-pkg work is
  deterministic), then re-sorted by name in a second pass once names are
  resolved (resolve_app_label's cache is already warm from the parallel
  pass just before it, so this is cache-hit-cheap, not a second round of
  `adb pull`+`aapt2`). **That second sort forces `LC_ALL=C`.** Confirmed
  against the packaged binary's bundled coreutils 9.11: under a UTF-8
  locale's collation, `sort -f` put "Firefox Nightly" *before* "Firefox" --
  a real, reproducible collation quirk in how a trailing space is weighted
  relative to no-more-characters, not a hypothetical. `sort -f` without
  `LC_ALL=C` is used elsewhere in this script too (`--sort-by` in
  `cmd_diff`/`cmd_devices`), inherited from before this was found -- same
  quirk likely applies there, just not yet fixed.

## Nix packaging

- `pkgs/declaroid/default.nix` wraps the script with `makeWrapper`, prefixing
  `PATH` with every runtime dependency (`android-tools`, `yq-go`, `gplaydl`,
  `fdroidcl`, `fzf` (used by `add`'s picker), `curl`, `jq`, `util-linux` for
  `column`, `aapt` -- which, confusingly, only actually provides an `aapt2`
  binary -- for `generate-config`'s name resolution, coreutils, etc) and installs
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
