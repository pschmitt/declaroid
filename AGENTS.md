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
  both only showed up on a real `apply`.
- **Per-app data flows through `CURRENT_NAME`/`CURRENT_PKG`/`CURRENT_STORE`/
  `CURRENT_REPO`/`CURRENT_ASSET`/`CURRENT_PATH`, not positional arguments.**
  `for_each_app` sets these (via a plain, non-`local` `read`, so they're
  visible to whatever it calls) before invoking `app_fn`; `install_app`,
  `uninstall_app`, and the per-store `install_*` functions are all
  effectively zero-arg and just read these plus `DEVICE_SERIAL`/`DRY_RUN`/
  `FORCE_DOWNLOAD` (set once per device/run by `cmd_apply`/`cmd_uninstall`).
  This replaced a positional chain that had grown to 8-9 params and was
  getting worse with every store added -- don't bring positional args back
  for this data; add a new `CURRENT_*` variable instead. Values that are
  genuinely computed/local (a resolved cache dir, a list of matched APK
  files) should stay real function arguments, not `CURRENT_*` -- that
  convention is specifically for per-app config data and run-wide context.
- **The TSV-ish rows `app_rows`/`module_rows`/`obtainium_rows`/etc emit are
  joined with `$ROW_SEP` (a single raw byte, ASCII Unit Separator `0x1F`),
  never a real tab and, as of this codebase's own CI investigation, never
  a printable character like `§` either.** `repo`/`asset`/`path` are
  legitimately empty for most stores, and bash's `read` collapses
  consecutive *whitespace* IFS delimiters -- tab included -- no matter
  what you set `IFS` to; there is no way to make `IFS=$'\t' read` preserve
  an empty field between two tabs. This silently shifted every field after
  the first empty one, which broke `github` and `local` (both depend on
  fields that are empty for other stores) while `gplay`/`fdroid` looked
  fine, since neither of them reads the shifted-into-garbage fields. If
  you add a new per-app config field, put it in the relevant `*_rows`
  function's `join(...)` list (via the same `'"$ROW_SEP"'` quote-splice
  used everywhere else there -- `$ROW_SEP` can't be interpolated directly
  into a single-quoted yq expression) and read it out with `IFS="$ROW_SEP"
  read` -- never `IFS=$'\t'`, and never a literal printable separator
  character either, per the next bullet.
- **`§` (U+00A7) was the original row separator here, and is a real,
  shipped, locale-dependent bug, not just a style choice -- caught only by
  adding a `nix flake check`-driven bats suite (see "Testing / CI" below)
  and noticing it failed in that sandboxed build but not in an interactive
  dev shell.** `§` is 2 bytes in UTF-8 (`0xC2 0xA7`); under a UTF-8 locale
  bash's IFS field-splitting correctly treats it as one delimiter
  character, but under a non-UTF-8 locale (`LC_ALL=C`, the Nix build
  sandbox's default, and also common for cron jobs/systemd services/
  minimal containers) bash splits on *each of its two raw bytes
  independently*, inserting a silent extra empty field and shifting
  everything after it over by one -- reproduced directly: `IFS='§' read -r
  a b c d <<< "x§y§z§w"` yields `b=""` under `LC_ALL=C` but the correct
  `b="y"` under a UTF-8 locale. Fixed by switching every row separator in
  this file from `§` to `$ROW_SEP` (declared once, near the top of the
  file, as `$'\x1f'`) -- a single byte has no multi-byte encoding to begin
  with, so it's immune to locale entirely, not just fixed for the common
  case. If you're ever tempted to reach for another printable-character
  separator here (`|`, `☃`, whatever) for readability during
  debugging: don't -- this is exactly the class of bug that hides
  perfectly under every interactive shell you'll ever test in and only
  shows up on a caller with a different locale.
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
- **`generate-config` entries that would fail a real `apply` are written
  out commented out, with a `# TODO: <reason>` line above them** -- not
  emitted active with `store` silently defaulted to `gplay`. Concretely:
  unknown-store entries (no way to tell `local`/`fdroid`/`github` apart) and
  `github` entries with an empty `repo: ""` placeholder (Obtainium doesn't
  expose the source repo). The point is that feeding a freshly generated
  config straight into `apply` should never itself produce errors; if you
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
- **`grant_permissions:`/`-g` follows the exact same dynamic-scope pattern as
  `DRY_RUN`/`FORCE_DOWNLOAD`/`VERBOSE`, not `enforce`'s** -- it's declared
  `local GRANT_PERMISSIONS=""` in `cmd_apply` itself (uppercase, the flag
  variable *is* the value, no separate lowercase mirror var), so it stays
  visible, dynamically scoped, all the way down through
  `for_each_app`/`install_app` to `install_apk_files`/`install_github`/
  `install_url` without being threaded through as a parameter anywhere.
  Appended to `adb install`/`install-multiple` as its own `grant_args=()`
  array (`[[ -n "${GRANT_PERMISSIONS:-}" ]] && grant_args=(-g)`), spliced
  in right next to the existing `user_args` array at each of those three
  call sites -- `install_local` needs no separate handling, it already
  routes through `install_apk_files`. `fdroidcl install --help` (checked
  directly) has no `-g`-equivalent flag at all, so `install_fdroid`/
  `install_izzyondroid` are untouched -- documented as a real, permanent
  no-op for `store: fdroid`/`izzyondroid`, not an oversight.
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
  killed the entire `apply` command (no error, just exit 1) when run
  through the packaged/wrapped nix binary -- traced by diffing four
  combinations of {raw source, wrapped binary} x {interactive PATH, wrapped
  PATH} until the failure was isolated to that exact construct under the
  wrapped bash's execution context. The root cause was never fully pinned
  down mechanistically, but the fix (switch to `mapfile` + `for`, as
  `for_each_app`/`cmd_diff`/`list_extra_pkgs` already did) reliably resolved
  it, and this class of bug -- like the `compgen` one above -- will not show
  up in interactive-shell testing. Treat `while read <(...)` as banned in
  this codebase, not just a style preference.
- `list_extra_pkgs` (shared by `diff --full` and `apply --enforce`) finds
  device-installed, non-plumbing packages absent from the config via a
  single `pm list packages -3` call with no `--user` -- it isn't trying to
  be precise about *which* profile an app lives in like `generate-config`
  is, just "is this pkg configured anywhere at all". `apply --enforce`
  prompts once per device for the whole batch of extra packages, not once
  per package, mirroring `cmd_uninstall`'s existing confirmation pattern
  (skippable with the same `-y|--yes|--noconfirm|--no-confirm`).
- `apply` builds a plan before touching anything: `build_install_plan`
  does a read-only pass (`is_installed` per configured app, no logging) to
  find what's actually missing on the device, `print_install_plan` shows
  that (pending apps plus a count of already-installed ones) and `cmd_apply`
  prompts per device before calling the *existing* `for_each_app "$config"
  install_app` unchanged -- the plan doesn't feed installs directly, it's
  purely a preview/confirm gate in front of the same install path as before.
  `install_app` still re-checks `is_installed` itself during the real pass
  (a second, cheap `pm list packages` call, not worth avoiding); its
  already-installed skip message is now gated on a new `VERBOSE` local
  (`-v|--verbose`, set in `cmd_apply` alongside `DRY_RUN`/`FORCE_DOWNLOAD`
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
- **`download`/`dl`/`fetch` only ever searches gplay/fdroid/izzyondroid,
  never github/local/url** -- this isn't an arbitrary restriction, it
  matches reality: `search`/`add` can only ever surface results from those
  three stores in the first place (`search_gplay`/`search_fdroid`/
  `search_izzyondroid` are the only search backends that exist), since
  github/local/url apps are always hand-configured, never discovered by
  searching. `cmd_add`'s search+pick logic was extracted into a shared
  `search_stores` (row-producing) function and a generalized
  `pick_search_result` (now takes a leading `mode` ("add"/"download") and
  `context` (config path or output dir) instead of a config-only
  signature) so `cmd_download` reuses both verbatim instead of duplicating
  ~35 lines of search accumulation and the whole mktemp-preview-script
  picker.
- **`download`'s gplay path reuses `fetch_app` verbatim by shadowing
  `CURRENT_PKG`/`FORCE_DOWNLOAD` as locals inside `cmd_download`** --
  same trick `resolve_module_zip` already uses to reuse
  `fetch_github_release` for modules (see its own comment). `fetch_app`
  has zero device coupling to begin with (confirmed while building this),
  so no other changes were needed to make it reusable outside the
  apply/install path.
- **`fdroidcl download`'s progress bar goes to its own *stdout*, not
  stderr** (confirmed empirically, same class of noise as gplaydl's) --
  but unlike `fetch_app` (which never needs to read gplaydl's stdout at
  all, since it already knows the cache dir path up front), `download`'s
  fdroid/izzyondroid path genuinely needs to read fdroidcl's own final
  "APK available in `<path>`" line, which is *also* on that same stdout,
  interleaved with the progress noise. `fetch_fdroid_apk` captures both
  streams with a plain `2>&1` and parses the result afterward -- no live
  progress display for this path. **The progress updates are
  `\r`-separated, not `\n`** (confirmed via `xxd` against a real capture)
  -- `tr '\r' '\n'` first is required before grepping out the final line,
  or it's all one "line" as far as `sed`/`grep` are concerned.
- **Do not pipe an external command through `tee /dev/stderr` inside a
  `$(...)` capture to get "live progress + still capture the output" --
  confirmed as a real, reproducible corruption bug, not a theoretical
  risk.** The obvious-looking `out="$(cmd | tee /dev/stderr)"` (tried
  first for `fetch_fdroid_apk`, to show fdroidcl's download progress live
  while still capturing its final "APK available in ..." line) silently
  corrupted stderr output whenever the *whole script's own* stderr was
  itself redirected to a regular file -- which covers any non-interactive
  invocation: piped output, `2> log`, a test harness, cron, etc, not just
  a contrived case. Root cause: `tee`'s `open("/dev/stderr")` (itself
  `/proc/self/fd/2` on Linux) creates a *new*, independently-offset open
  file description against the same underlying regular file, rather than
  reusing the shell's existing fd 2 -- so `tee`'s writes and the rest of
  the script's own later stderr writes (`log_step`/`log_ok`/etc, all
  writing through the original fd 2) race and overwrite each other's bytes
  at arbitrary offsets. Reproduced with a minimal two-marker repro
  (`echo marker1 >&2; out="$(cmd | tee /dev/stderr)"; echo marker2 >&2`,
  whole thing redirected to a file): `marker1` and parts of the piped
  output vanished or landed scrambled/out of order. This does *not*
  reproduce when stderr is a real terminal (no fixed byte offset to race
  over) -- which is exactly why it's easy to miss in ad hoc manual
  testing and only surfaces once something redirects/logs the run.
  Swapped for a plain `cmd 2>&1` full capture (see `fetch_fdroid_apk`):
  no live progress, but correct and safe regardless of how the calling
  script's own stderr is connected.
- **`fdroidcl download` needs no adb/device at all** -- confirmed by
  reading fdroidcl's own Go source (`download.go`): it calls
  `maybeOneDevice()` only to pick the *best-matching* APK variant if a
  device happens to be connected, and explicitly ignores the error if none
  is ("don't fail a download if adb is not installed" per its own
  comment). This is what makes `download` genuinely device-independent,
  same positioning as `search` ("no device or config needed").
- **`imports:` (config file A pulling in apps:/modules:/profiles: from
  file B) is resolved by declaroid itself, not yq/YAML** -- `yq --help`
  confirms there's no `!include`-style tag support at all, only
  `load(file)` inside an expression and `eval-all` for multi-file
  merging. `collect_imports` (recursive, cycle-guarded by realpath via a
  `SEEN` associative array) and `resolve_config` (the actual merge) are
  the one place this happens; every `cmd_apply`/`cmd_uninstall`/
  `cmd_diff`/`cmd_modules` reassigns its own local `config` to
  `resolve_config`'s output right after its existing config-file-exists
  check, so every other `yq`/`app_rows`/`module_rows`/`list_extra_pkgs`/
  etc call site downstream keeps treating `$config` as an opaque path --
  no changes needed anywhere else. `add`/`download` deliberately don't
  call this at all: `add` writes into the real file directly (a merged
  temp copy would just be discarded after the run), so its duplicate-pkg
  check only ever sees that one file's own `apps:`, not anything pulled
  in via `imports:` -- documented as a known limitation, not fixed, since
  fixing it would mean either resolving twice (once merged for the check,
  once raw for the write) or threading a second config value through
  `cmd_add`/`add_app_to_config`, and it hasn't been worth it yet.
- **`enforce:`/`grant_permissions:`/`store:` cascade in from imports too,
  but as a scalar override, not the list-key concatenation above** --
  added so a shared `imports/base.yaml` can carry `enforce: true`/
  `grant_permissions: true`/`store: gplay` for every device config that
  imports it, without each one repeating it. `resolve_config`'s second
  loop (`for scalar_key in enforce grant_permissions store`) checks `yq
  'has("$key")'` against the *original* `$config` first -- if it's set
  there at all (even to `false`), that wins outright and no import is
  consulted; only an absent key falls through to the last import (in
  listed order) that has it. Deliberately only these three keys --
  `device:`/`adb:`/`root:`/`profile:` stay squarely per-device, never
  cascaded.
  **The value is round-tripped through its own one-line temp file and
  `load(strenv(...))`, not extracted via `yq -r` and spliced back in as
  bare text** -- confirmed necessary while adding `store:` to the list,
  not just tidier: bare-text splicing (`.enforce = $value`) happens to
  work for a boolean (`true`/`false` are valid bare yq-expression
  literals) but genuinely breaks for any string (`.store = gplay` errors
  with "invalid input text" -- yq's *expression* language has no
  bare-unquoted-string syntax, unlike YAML itself). Reproduced the break
  with a two-file test before switching to `load()`, same fix shape as
  the list-key merge above.
  Verified via `bash -x` against a real device: a config importing a
  `base.yaml` with `enforce`/`grant_permissions` set to `true`, itself
  setting neither, correctly ended up with `enforce=1`/
  `GRANT_PERMISSIONS=1` in the trace, and a real `apply --dry-run`
  against it genuinely ran `enforce_config` (listed every
  installed-but-unconfigured app, exactly `--enforce`'s behavior).
- **`yq eval-all '[(.$key // [])[]]' file1 file2 ...' -- confirmed as the
  working idiom for "concatenate this one array key across N files, in
  file order."** Verified empirically (a 3-file test, `.apps` from each,
  correct order, and a 4th file entirely missing the key contributing
  nothing rather than erroring). `resolve_config` writes each merged
  array to its own temp file and pulls it back into the resolved copy via
  `load(strenv(...))` (env-var-scoped, same convention as
  `add_app_to_config`'s `DECLAROID_NAME`/`DECLAROID_PKG`) rather than
  inlining a potentially large array as a literal expression.
- **`configs:` (a meta-config fanning one invocation out over several
  independent device configs) is deliberately a separate mechanism from
  `imports:`, not an extension of it** -- `imports:` merges fragments *into*
  one resolved config (`resolve_config`, apps: dedup-by-pkg and all);
  `configs:` never merges anything, it just runs `cmd_apply`/
  `cmd_uninstall`/`cmd_diff`/`cmd_modules` once per listed leaf, each
  through the *normal*, unmodified single-config pipeline (own
  `resolve_config`, own `resolve_devices`, own everything). Detected via
  `is_meta_config` against the *raw* `$config`, before `resolve_config` is
  ever called on it -- checking post-merge would be meaningless since a
  meta-config has no `apps:`/`device:` of its own to resolve in the first
  place. `collect_meta_configs` mirrors `collect_imports`'s recursive,
  realpath-keyed `SEEN`-map cycle guard almost exactly, but through its own
  map (`META_SEEN`) -- confirmed, not assumed, that reusing the same `SEEN`
  array as `imports:` would be wrong: `imports:` cycle-checks are scoped to
  one `resolve_config` call's own import graph, while `configs:` fan-out
  spans multiple independent `resolve_config` calls (one per leaf) that
  must each start with a clean slate.
  Each `cmd_*` captures `orig_args=("$@")` as its very first line (before
  its own option-parsing loop consumes `$@` via `shift`), specifically so
  `run_meta_config` can still forward the *original*, unconsumed argv to
  every leaf -- `strip_config_flag` then removes just the `-c`/`--config`
  pair from that copy before each leaf call swaps in its own `-c <leaf>`.
  `run_meta_config` runs every leaf regardless of an earlier one's exit
  status and rolls up a nonzero return if any failed, matching
  `resolve_devices`/`--bulk`'s existing "keep going across multiple
  matched devices, aggregate at the end" convention rather than aborting
  the whole run on the first bad leaf (e.g. one device not currently
  connected).
  A meta-config combined with its own `apps:`/`device:` is rejected
  outright (`run_meta_config`'s own guard) rather than picking one
  behavior silently -- there's no non-surprising way to decide whether
  such a file's `apps:` means anything once `configs:` is also fanning out
  to other files that have their own.
- **A `trap ... EXIT` (or `RETURN`) referencing a `local` variable in
  single-quoted form is broken, and this was caught the hard way, not
  reasoned out in advance.** `resolve_config`'s resolved-path temp file
  needed cleanup that survives every early `return` in
  `cmd_apply`/etc, so the first attempt was `trap 'rm -f
  "$resolved_config"' RETURN` -- single-quoted, deferring `$resolved_config`
  expansion until the trap actually *fires*. This is wrong on two
  separate counts, both confirmed against the real script, not a
  simulation: (1) a `RETURN` trap set inside a function is **not**
  scoped to that function's own return -- it re-fires on every
  subsequent function return up the call stack (including `main()`'s),
  because bash's trap table is a single global, not saved/restored per
  call frame; swapping to `EXIT` fixes that specific symptom (only one
  process exit, ever, since each invocation runs exactly one `cmd_*`
  before the process ends). But (2) by the time *any* trap actually
  fires -- `RETURN` or `EXIT` alike -- the function that declared
  `resolved_config` as `local` has already returned and unwound, so that
  variable no longer exists in *any* live scope; a single-quoted
  deferred-reference trap command hits `set -u`'s "unbound variable" at
  that point, confirmed with both `RETURN` (fired early, mid-command,
  from an unrelated frame) and `EXIT` (fired once, cleanly, but still
  hit the same unbound-variable error). **The fix is `trap "rm -f
  '$resolved_config'" EXIT`** -- double-quoted, so `$resolved_config`
  expands immediately, at the moment `trap` itself runs, baking the
  literal path into the registered command as a plain string with no
  variable reference left to re-evaluate later. Confirmed with a minimal
  two-line repro (`local f=...; touch "$f"; trap "rm -f \"$f\"" EXIT`)
  before reapplying to the real script. `shellcheck`'s SC2064 (which
  recommends single-quoting `trap` arguments) is *wrong for this specific
  case* -- its default advice assumes you want deferred evaluation (the
  common signal-handler idiom, e.g. `trap 'log $LINENO' ERR`), which is
  exactly the bug here; disabled with a comment explaining why, not
  fixed by following the warning.

## Root modules (APatch/Magisk)

- **`adb shell su -c 'shell syntax here'` only works if the *entire*
  `su -c '...'` reaches `adb shell` as ONE argument, not split across
  `shell su -c '...'` as separate words.** Confirmed empirically: `su -c`
  execs its argument directly (no shell involved) when adb hands it over
  as several bare words -- fine for a plain binary + args (`su -c apd
  module list` genuinely works that way, since Android's `su -c CMD arg
  arg...` execs CMD with the trailing words as its own argv, no shell
  needed), but a `for`/`;`/glob-bearing command silently breaks: adb
  reconstructs the remote command line by rejoining `su`/`-c`/the (already
  bash-parsed-away) quoted string with plain spaces, so shell keywords
  land as bare top-level statements in the *outer* shell instead of inside
  `-c`'s string, failing with `syntax error: unexpected 'do'`. Wrapping the
  whole `su -c '...'` in an *outer* pair of double quotes before it ever
  reaches `adb shell` (`adb shell "su -c '...'"` -- see `run_root_shell`)
  fixes it: now adb receives one argument, so it can't rejoin/re-split
  anything, and `su -c` gets the *whole* string, which is when it actually
  invokes a shell to interpret it.
- **Don't detect APatch/Magisk via their app package id.** Magisk
  explicitly supports hiding/repackaging its own manager app under a
  random package id, specifically to evade checks like `pm list packages
  com.topjohnwu.magisk` -- confirmed against a real device: Magisk fully
  installed and functional (`magisk -v` worked fine through a root shell),
  but its app package was nowhere in `pm list packages` output.
  `detect_root_framework` instead probes the root shell directly for the
  `apd`/`magisk` CLI binary (`command -v`), the only signal that's
  actually reliable for both.
- **`command -v apd` needs its stderr silenced to work at all** -- without
  `2>/dev/null`, a bare `su -c 'command -v apd'` (through the multi-word
  form above, before finding the single-string fix) printed `apd:
  inaccessible or not found` to stderr on a real device and the whole
  probe read as a failure even though apd genuinely was on `$PATH`
  (`/data/adb/ap/bin/apd`) once the single-string form was used and stderr
  silenced.
- **APatch's `apd module list` emits real JSON, with every field
  (including booleans like `"enabled"`) as a *string*, not a JSON
  boolean** -- confirmed against a real device's actual output
  (`"enabled": "true"`, not `"enabled": true`). `list_apatch_modules`'s jq
  filter compares against the string `"true"`, not the boolean.
- **`apd module list`'s JSON is the source of truth for APatch, not a raw
  `module.prop` directory scan.** A real device had a "TA_utl" module
  directory (a Tricky Store companion) whose `module.prop` is
  permission-denied even to a root shell -- `apd module list` simply
  omits it from its JSON, which is the behavior worth matching, not
  fighting.
- **This build of Magisk's own CLI has no module-listing subcommand at
  all** -- checked `magisk --help` against a real, running Magisk v30.7:
  only `--install-module`/`--remove-modules` exist for modules, nothing
  that lists them (unlike APatch's `apd module list`). `list_magisk_modules`
  falls back to the traditional method every Magisk module itself relies
  on: read `module.prop` out of each `/data/adb/modules/<id>/` directory,
  check for a `disable` marker file. This also works against APatch
  devices (confirmed): both frameworks use the identical directory/
  `module.prop`/marker-file convention, `apd`'s JSON is just APatch's own
  nicer wrapper around the same data.
- **`list_magisk_modules` pushes a real script to the device via `adb
  push` and runs that, instead of inlining the for-loop through
  `run_root_shell` directly.** The loop needs to quote each module's own
  path (`"${d}module.prop"`), which would have to nest inside the single
  quotes `run_root_shell`'s `su -c '...'` already needs -- the same
  escaping-inside-escaping problem `pick_search_result`'s fzf preview
  script hit, solved the same way here.
- **Untested against real Magisk module *content*.** The only Magisk
  device available while building this had zero modules installed, so the
  empty-list path is verified for real, but the actual `module.prop`
  key=value parsing in `list_magisk_modules` is only verified against
  real-world `module.prop` files pulled from an *APatch* device (same
  format, per the point above) -- re-verify against a real Magisk device
  with modules installed if one becomes available.
- **`.root.enabled // ""` is wrong and was a real bug here** -- jq/yq's
  `//` treats a `false` *value* the same as a *missing* key (both
  falsy), so it silently discarded an explicit `root.enabled: false` and
  fell through to auto-detection anyway, doing the opposite of what the
  config asked for (caught by testing against a real config with
  `root.enabled: false` set: it still queried the device and returned
  results). Fixed by comparing directly (`.root.enabled == false`)
  instead of coalescing with `//` -- the third time this exact class of
  bug has shown up in this file (see the `asset: ''` and the `$ROW_SEP`-
  vs-tab entries above): jq/yq's `//` cannot distinguish "present but falsy"
  from "absent," so never reach for it when that distinction matters.
- `cmd_modules` stays read-only (drift reporting only, same shape as
  `cmd_diff`) -- but `apply` *does* install missing modules now (see
  below). Still deliberately no enable/disable/uninstall support: module
  state changes only take effect on next boot for both frameworks (`apply`
  never reboots on its own unless `--reboot` is given -- a `WRN ... reboot
  required` reminder is printed instead otherwise), and APatch's own CLI `module
  install` has a documented failure mode
  ([bmax121/APatch#633](https://github.com/bmax121/APatch/issues/633))
  that its GUI app doesn't hit, with no known root cause -- untested here
  since both real installs done while building this were against a Magisk
  device, not APatch; be extra careful testing the APatch install path.
- **`fetch_github_release` is reused verbatim for modules, not
  duplicated** -- `resolve_module_zip`'s `github` branch shadows
  `CURRENT_REPO`/`CURRENT_ASSET` as locals from `CURRENT_MODULE_REPO`/
  `CURRENT_MODULE_ASSET` right before calling it. This works because
  `fetch_github_release` only ever reads those two globals (plus a
  `cache_dir` argument) -- it has no `.apk`-specific assumption baked in
  anywhere in its own body, the `.apk`/`.zip` default is entirely a
  property of what `app_rows`/`module_rows` default `CURRENT_ASSET`/
  `CURRENT_MODULE_ASSET` to when the config doesn't set one. Same
  CURRENT_*-as-dynamic-scope convention already used throughout this file,
  just shadowed one level deeper than usual.
- **`run_root_shell`'s exit status genuinely reflects the remote apd/
  magisk command's own exit code**, confirmed against a real device for
  both outcomes (a real module install: exit 0, stdout showing install
  progress; a deliberately corrupt/non-module zip: exit 1, `magisk`'s own
  `! This zip is not a Magisk module!` on stdout) -- even though the
  function pipes through `tr -d '\r'`. This isn't an accident: this
  script runs under `set -o pipefail`, which reports the exit status of
  the *last command in the pipeline that actually failed*, not simply the
  rightmost stage -- since `tr` essentially never fails, a failing `adb
  shell` stage still wins. Relied on directly in `install_module_zip`
  (`output="$(run_root_shell ...)" || rc=$?`) instead of re-deriving
  success from output text.
- `run_root_shell` takes an optional third argument overriding its
  default 15s timeout -- too short for an actual module install
  (extracting/running a module's own scripts can take longer than a quick
  `command -v`/`module list` probe); `install_module_zip` passes 60.
- **`yq -r` emits one blank line, not zero output, for `(.foo // [])[] |
  ... | join(...)` over an empty/absent list** -- confirmed empirically
  and it's specifically about `join(...)` being the final step: `.apps[]`
  (or `.modules[]`) alone over `[]` correctly produces zero output, but
  piping that through `[...] | join("'"$ROW_SEP"'")` produces exactly one blank
  line instead of nothing. Every row-consuming loop over `app_rows`/
  `module_rows` (`for_each_app`, `for_each_module`, `build_install_plan`,
  `build_module_plan`, `cmd_diff`) now guards against this (`[[ -z "$row"
  ]] && continue` or equivalent on the parsed pkg/id) -- without it, an
  `apps: []` or `modules: []` (or omitted key entirely) config spins up
  one phantom iteration with every CURRENT_* field empty. This was a
  latent bug in the pre-existing app-side functions too, only surfaced by
  actually testing a modules-only config (`apps: []`) while building this
  feature -- worth remembering for any *other* `(.x // [])[] | ... |
  join(...)` pattern added later.
- **Per-app `state.installed`/`state.disabled` were added as two more
  trailing `app_rows` fields, not a separate query/loop.** `state.installed:
  false` means the app isn't desired at all (still listed, just marked
  unwanted): `build_install_plan` excludes these rows entirely (neither
  pending nor a skip-count), and a new mirror-image `build_removal_plan`
  finds the ones still actually present and feeds them through `uninstall_app`
  via its own plan+confirm step in `cmd_apply` -- deliberately *not* gated
  behind `--enforce`, since this is an explicit per-app choice, unlike
  `--enforce`'s "anything undeclared". `install_app` itself also returns
  immediately for these (it's called unconditionally by `for_each_app`
  regardless of the plan, same as ever).
- **`state.disabled: true` converges via `pm disable-user`/`pm enable`, not
  `pm archive`** -- archiving frees the APK's storage, but un-archiving
  depends on the installer supporting an unarchive request (confirmed via
  `pm help` on a real device: both `disable-user` and `archive` exist on
  SDK 35/36), which is only a safe assumption for `gplay`; `disable-user` is
  universal across every store this tool supports and always reversible via
  `pm enable`, so it's the one that doesn't risk stranding a github/local/url
  app. `sync_app_disabled_state` (called from `install_app`, right after the
  existing install-or-already-installed branch, only when that branch
  succeeded) is deliberately symmetric: it re-enables a currently-disabled
  app when `state.disabled` is false/absent too, not just the disable
  direction -- otherwise flipping the config back would silently do nothing,
  which would contradict the "declarative" framing the rest of this tool
  uses everywhere else. "Install it, then disable" (rather than skipping the
  install entirely for a disabled-desired app) was a deliberate choice: a
  disabled app is still a *present* app, just dormant.
- **`bash -c "$start_cmd"` inside `resolve_devices` must redirect to
  stderr (`>&2`), confirmed as a real bug against a real device, not just a
  theoretical risk.** `resolve_devices`'s own return value is captured via
  `$(...)` by every caller (see the "log to stderr, data to stdout" rule
  above) -- `start_cmd` is an arbitrary, user-supplied shell command, and a
  real one (`zhj adb::connect <host>`, which calls out to a Home
  Assistant/Tasker intent) printed a stray JSON `[]` to stdout as a side
  effect. Without the redirect, that line silently became part of the
  "connected device" list this function returns, and the device serial
  downstream code tried to use ended up literally being the string `[]`
  -- every subsequent `adb -s '[]' ...` call then failed silently (stderr
  discarded, per existing convention), so the whole run proceeded as if
  every configured app were missing, no error surfaced anywhere. Only
  caught by testing against a real disconnected device with a real
  `start_cmd`, not by reasoning about it or dry-running.
- **`adb.start_cmd` retries device resolution exactly once, never loops.**
  `resolve_devices` tries discovery/matching as-is first; only if that comes
  up completely empty (no devices at all, or none matching the query) *and*
  `adb.start_cmd` is set does it run the command (`bash -c`) and try again --
  capped at one retry by construction (a `for attempt in 1 2` loop, not a
  `while`), so a `start_cmd` that doesn't actually fix the connection fails
  exactly the same way it would without one configured, just slower by
  however long the command takes. Deliberately just an arbitrary shell
  string, not a structured "connect to host:port" field -- real-world
  start commands vary (plain `adb connect host:port`, `zhj adb::connect
  <host>` which itself nmap-scans for the currently-listening port *and*
  can trigger a Home Assistant/Tasker intent to enable wireless adb first),
  and trying to model that structurally would just end up re-inventing
  shell.
- `enforce: true` in the config and `--enforce` on the CLI OR together in
  `cmd_apply` -- reads `.enforce == true` from the config right after the
  config-file-exists check, only when the CLI flag wasn't already given (no
  point querying yq if it's already on). Same `== true` (not `//`)
  convention as every other optional boolean field in this file.
- **`-k`/`--dry-run`/`--dryrun` is accepted by every subcommand now, not
  just `apply`/`uninstall`.** Real behavior for the ones that mutate
  something (`apply`, `uninstall`, `clear-cache`, `add`, `generate-config`
  with `-o`); a parsed-but-ignored no-op for the ones that were already
  read-only (`devices`, `diff`, `modules`, `search`) so a script that always
  passes `-k`/`--dry-run` doesn't have to know which subcommand it's
  calling. `add --dry-run` prints the YAML entry it would append to stdout
  (real data output, not a log line) instead of running the `yq -i`
  mutation -- computed the same way the fzf preview script already renders
  it (double-quoted name, `store:` only when it differs from the config's
  default), just without the ANSI/preview-script machinery.
- **`adb.stop_cmd`/`adb.auto_stop` are the teardown mirror of
  `adb.start_cmd`, via a shared `maybe_run_adb_stop_cmd` helper called at
  the end of `cmd_apply`/`cmd_uninstall`/`cmd_diff`/`cmd_modules`** (every
  command that resolves a device via a real config path -- `cmd_generate_config`
  passes `resolve_devices` an empty config string, so `adb.start_cmd`
  doesn't apply there either; consistent to skip `stop_cmd` there too).
  Deliberately best-effort/fire-and-forget: a failing `stop_cmd` only logs,
  it never flips the calling command's own exit status -- disconnecting
  wireless adb again is cleanup, not something worth failing an otherwise-
  successful run over. `auto_stop` defaults to `false` so a bare
  `start_cmd` (no `auto_stop`) never disconnects anything on its own --
  it's opt-in on both ends, not implied by having `start_cmd` set.
  `cmd_diff`/`cmd_modules` didn't previously track a real `DRY_RUN` local
  (their `-k`/`--dry-run`/`--dryrun` case was a parsed-but-ignored no-op,
  added when that flag went global) -- upgraded to a genuine local so
  `maybe_run_adb_stop_cmd` can respect it there too (preview only, don't
  actually run `stop_cmd`), same as it already does in `cmd_apply`/
  `cmd_uninstall`.

## Obtainium repo tracking (`obtainium:`)

- **Schema reverse-engineered from Obtainium's own Dart source, not
  guessed** -- `class App`'s `fromJson` (`lib/providers/source_provider.dart`)
  casts `id`/`url`/`author`/`name`/`additionalSettings` directly (throws
  `TypeError` if any is missing or the wrong type); everything else
  (`latestVersion`, `apkUrls`, `preferredApkIndex`, `pinned`, ...) has an
  in-code default and can be omitted. `additionalSettings` must itself be a
  JSON-encoded *string* (decoded via `jsonDecode` inside `fromJson`), not a
  nested object -- `jq`'s `| tojson` on the `settings:` config key handles
  that. Minimal working JSON: `{"id":"<pkg>","url":"<url>","author":"",
  "name":"","additionalSettings":"{}"}`.
- **`loadApps()` (`app_data_provider.dart`) scans the app's own
  `<external-files-dir>/app_data/*.json` on load** -- this is why
  `sync_obtainium_repos` writes directly into
  `/storage/emulated/0/Android/data/<pkg>/files/app_data/<tracked-pkg>.json`
  rather than going through any Obtainium API/intent; there isn't one for
  this (see below). If the entry's `url` fails to resolve to a known source
  non-transiently, Obtainium deletes the file itself on next load -- so a
  bad `url:` in the config silently stops being tracked rather than erroring
  loudly; not handled specially here, matches Obtainium's own behavior.
- **No headless "force check/fetch" exists, checked in the source before
  concluding this** -- only interactive deep-links
  (`obtainium://add/<url>`, `obtainium://app/<json>`), both requiring a
  confirmation-dialog tap per `docs/DEVELOPER_GUIDE.md`. Real background
  checks run via a WorkManager periodic task (~15 min), not triggerable via
  adb/broadcast. `sync_obtainium_repos` therefore only ever seeds the
  pointer file; it does not attempt to force Obtainium to populate
  `latestVersion`/etc immediately, and the README says so rather than
  implying it's instant.
- **Does NOT actually require root -- this was the original assumption
  going in, and it was wrong, corrected only after testing it live
  against a real non-rooted device (zf10, stock `user` build).**
  `run-as` was tried first and refuses outright there ("package not
  debuggable": Obtainium's release APK isn't debuggable, and `user`
  builds only allow `run-as` for debuggable/profileable apps or on a
  debuggable/eng build). But plain, unprivileged `adb shell` (uid 2000)
  turned out to already be a *supplementary* member of both `sdcard_rw`
  and `ext_data_rw` by stock AOSP default (confirmed via `id`) -- exactly
  the groups that own every app's `Android/data/<pkg>` tree (`drwxrws---
  ... ext_data_rw`, confirmed via `ls -la`). The `s` in `rws` is SGID: a
  file plain shell creates under that directory inherits the directory's
  *group* automatically, regardless of shell's own primary group, so it
  ends up group-readable by the app (which has that same group as one of
  *its* own supplementary groups) with zero elevated privilege anywhere
  in the chain. Live-verified end to end: seeded a real entry via plain
  `adb shell`/`adb push` only, and a screenshot of Obtainium's own Apps
  list on that device showed it picked up immediately, indistinguishable
  from the rooted case. `sync_obtainium_repos` now calls
  `resolve_root_framework` only to decide whether root is *available*
  (setting `use_root`, used purely to prefer the marginally more precise
  `chown`-to-exact-UID write when possible) -- never as a hard
  requirement; `obtainium_shell` is the small wrapper that picks `su -c`
  vs. plain `adb shell` based on that flag, used at every step (dir-exists
  checks, the launch-if-missing dance, the actual write). The one thing
  that's still an error rather than a silent skip: if *neither* root
  *nor* plain shell can write to the directory (checked via `[ -w ... ]`
  when `use_root` is unset) -- possible in principle on some
  non-stock/hardened ROM, just not observed on any real device tested so
  far.
- **Ownership/permissions are read from the live device when root is
  available, never hardcoded** -- `stat -c '%U:%G'
  /storage/emulated/0/Android/data/<pkg>` gives the app's actual UID:GID
  (e.g. `u0_a197:sdcard_rw` on a real device), then the pushed JSON gets
  `chown`'d to match and `chmod 660`; skipped (no `chown` at all) on the
  non-root path, which relies on SGID group inheritance instead (see
  above) -- both end up group-readable by the app either way, just via a
  different mechanism. A mismatched owner/group on the root path would
  mean Obtainium's own process can't read the file back even though it's
  technically present -- this is why it's read from the app's own storage
  dir at write time rather than hardcoded.
- **Supports both `dev.imranr.obtainium` and `dev.imranr.obtainium.fdroid`**
  -- checks `is_installed` for the F-Droid variant first, falls back to the
  base package, and **errors out** (`return 1`, not a skip) if neither is
  present -- unlike the `root.enabled: false` case (an `OK`-level skip,
  since the feature is inherently unavailable there), a rooted device with
  `obtainium:` configured but Obtainium itself missing is a real
  misconfiguration (the config forgot to also install Obtainium via
  `apps:`), so `apply` should fail loudly rather than silently no-op.
  Consistent with
  `apps.yaml`'s own Obtainium entry always being `store: fdroid` (see the
  `INSTALL_FAILED_VERSION_DOWNGRADE` bug below) -- GitHub's own release
  APK is internally `dev.imranr.obtainium`, never the `.fdroid`-suffixed
  package, confirmed via `aapt2 dump badging` on the actual downloaded
  APK; a `store: github` + `pkg: dev.imranr.obtainium.fdroid` config can
  never successfully install.
- **Already-tracked entries are skipped, not diffed/updated** -- existence
  of `<app_data>/<pkg>.json` on-device is the entire signal (no content
  comparison against `url:`/`settings:` in the config). Changing an
  already-tracked entry's `url:`/`settings:` in the config has no effect on
  a subsequent `apply`; only a first-seed is supported. Acceptable for now
  since this mirrors modules' own "install if missing, no drift
  convergence" behavior, not a special-cased limitation just for this
  feature.
- **Live-verified end to end against a real device (mi pad 4, `magisk`,
  brand-new empty Obtainium install)**, not just `bash -n`/shellcheck:
  `--dry-run` correctly distinguished an already-tracked pkg (`SKP ...
  already tracked`) from a new one (`would seed Obtainium tracking for
  ...`); a real run wrote the JSON with correct content, `660` perms, and
  ownership matching the app's actual UID/GID (confirmed via `stat`); a
  second real run correctly no-op'd (`SKP` for both); and the same config
  against a non-rooted device (zf10) correctly skipped with `OK Root not
  enabled/detected on ..., skipping configured Obtainium repo(s)` rather
  than erroring.
- **Two real bugs found by the user hitting them for real, both fixed and
  re-verified live:**
  1. **`Android/data/<pkg>` doesn't exist right after a fresh install --
     confirmed empirically** (`stat`/`ls` on it: "No such file or
     directory" immediately after `apply` had just installed
     `dev.imranr.obtainium.fdroid` in the same run). Android only creates
     an app's scoped-storage dir the first time the app itself actually
     runs, not at install time -- there's no `pm`/`stat`-only way around
     this. Fixed by launching the app once via `monkey -p <pkg> -c
     android.intent.category.LAUNCHER 1` (headless, no launcher-activity
     name to resolve/hardcode) then `am force-stop`-ing it right back
     before the owner-detection `stat` -- confirmed the dir (and
     Obtainium's own `app_data/` subdirectory inside it) exists
     immediately after. Only done outside `--dry-run` (a preview never
     needs `$owner` or a directory that might not exist yet, so it skips
     this dance entirely).
  2. **`list_extra_pkgs` (backing both `--enforce` and `diff`'s
     "unconfigured" reporting) only ever checked `.apps[].pkg`, not
     `.obtainium[].pkg`** -- so a device with a repo declared *only* under
     `obtainium:` (by design: `obtainium:` is a tracking pointer, not an
     install directive, see the README) got flagged as an unrecognized
     app and **was actually uninstalled** by `--enforce` in a real run
     (`com.kieronquinn.app.smartspacer`, confirmed gone via `pm list
     packages` afterward -- a real, user-visible regression, not just a
     false positive in a report). Fixed by also folding
     `(.obtainium // [])[].pkg` into `list_extra_pkgs`'s `configured` set.
     `obtainium:` entries still never get *installed* by declaroid itself
     (that stays exclusively `apps:`'s job) -- this fix only stops
     `--enforce` from removing an app it doesn't recognize as configured
     when it actually is, just under a different key.
  3. **A fixed `sleep 2` after launching Obtainium wasn't reliably long
     enough for its own `files/app_data` subdirectory to actually
     appear** -- that directory is created by Obtainium's own Dart init
     code partway through its startup, not by Android at process launch,
     and its timing isn't guaranteed. Confirmed live: worked once, then
     failed (every configured repo's write erroring) on a later run
     against the very same app on the very same device. Fixed by polling
     for `$app_data_dir` itself (not just the top-level storage dir) for
     up to 10s instead of a single fixed sleep, erroring cleanly if it
     never appears rather than letting every individual write fail with a
     vague, per-repo error.
  4. **A real `--dry-run` false-positive**: since `--dry-run` never
     actually installs anything, a config that both installs Obtainium
     via `apps:` and configures `obtainium:` repos spuriously errored
     ("neither ... is installed") on a fresh device's very first preview,
     even though the real run right after it would work fine (confirmed
     live). Softened for `--dry-run` only: if Obtainium is configured to
     be installed at all (present in `apps:` with `state.installed` not
     `false`), note it and continue instead of erroring; still errors in
     `--dry-run` if `obtainium:` is configured without installing
     Obtainium anywhere, since no real run would fix that either.
- **`yq -r 'expr | tostring'` is not valid yq-go syntax -- `tostring`
  doesn't exist as a function there** (unlike jq, which does have one).
  Hit this writing `effective_obtainium_rows`'s `has("obtainium") |
  tostring` -- errored with a cryptic `invalid input text "tostring)"`
  that doesn't even name the missing function. Fix: don't call it at
  all -- `yq -r` already stringifies a bare scalar/boolean node on output
  (`true`/`false` print as plain text), so there's nothing to convert in
  the first place for this use case.
- **`obtainium_auto_track:` (config-driven auto-add of every `store:
  github` app to Obtainium tracking) + per-app `obtainium: true|false`
  override, implemented as `effective_obtainium_rows`, layered in front of
  `obtainium_rows`** -- explicit `obtainium:` entries are collected first
  into a `seen` associative array keyed by pkg (and always printed
  as-is, settings intact); the `apps: store: github` scan then skips
  anything already in `seen`, and for the rest resolves
  `effective = has_override ? override_val : auto_track` per app, only
  emitting a row (with a derived `https://github.com/$repo` URL and empty
  `{}` settings) when that resolves to `true`. This is what makes "an app
  explicitly listed under both `apps:` (github) and `obtainium:` (with its
  own `settings:`) never gets a second, settings-less duplicate row"
  actually hold, and what makes a per-app `obtainium: true` override work
  even with the top-level default `false` (and vice versa for `false`).
  `cmd_apply`'s own `obtainium_needed` gate (deciding whether to even call
  `sync_obtainium_repos`/`check_deps jq` at all) has to independently check
  all three of "explicit `obtainium:` list non-empty",
  "`obtainium_auto_track: true`", and "any app has `obtainium: true`" --
  checking only the first (as the original, pre-auto-track code did) would
  silently skip the whole feature on a device with zero explicit
  `obtainium:` entries but `obtainium_auto_track: true` or a lone per-app
  override, which was a real bug caught while wiring this in, before ever
  shipping it.
- **Obtainium's `settings:` map (an app's `additionalSettings` override)
  deliberately passes keys straight through using Obtainium's own upstream
  names (e.g. `includePrereleases`), not a declaroid-translated
  vocabulary** -- a real, user-driven decision, not an oversight: a
  translation layer would need to be kept in sync by hand as Obtainium
  adds/renames settings over time, for no benefit over just writing the
  real key name once. (`include_pre_releases: true|false` as a first-class,
  separately-merged field was tried first and reverted for exactly this
  reason -- if resurrecting anything like it, don't; point people at
  `settings:` instead.)
- **Root-caused a real Obtainium "Could not find a suitable release"
  error via Obtainium's own source, not guesswork**: `github_source.dart`
  skips prerelease-flagged GitHub releases entirely unless
  `additionalSettings['includePrereleases'] == true`; a live check via
  `gh api 'repos/pschmitt/findroidplus/releases?per_page=5'` showed that
  repo's *only* release is tagged `latest` but has GitHub's own
  `"prerelease": true` -- so every release was being filtered out before
  Obtainium ever got to asset-matching, `_selectGitHubTargetRelease`
  returned `null`, and `NoReleasesError` (localized as "Could not find a
  suitable release") followed. Not an APK-naming/multi-flavor-release
  issue (a first, wrong hypothesis) -- `filterApks` with no
  `apkFilterRegEx` set just passes every apk-like asset through
  unfiltered, it doesn't error on ambiguity.

## Testing / CI

- **`nix develop`** provides everything needed to lint/test locally:
  `shellcheck`, `nixfmt`, `statix`, `actionlint`, `bats`, plus declaroid's
  own runtime deps (`android-tools`, `yq-go`, `jq`, `aapt`, `fdroidcl`,
  `fzf` -- not `gplaydl`, deliberately: it's a whole extra Python
  derivation and nothing in the test suite needs `store: gplay`).
- **`nix flake check`** builds three checks -- `shellcheck` (`bash -n` +
  `shellcheck` against `declaroid` and every file under `tests/`),
  `actionlint` (against every file under `.github/workflows/`), and
  `bats-unit` (the whole `tests/unit` suite) -- and is deliberately run
  with no LANG/LC_ALL override. That's not an oversight: the Nix build sandbox's
  effectively-`C` locale is exactly what caught the real `$ROW_SEP`/`§`
  locale bug documented above, and pinning a UTF-8 locale here would mask
  any future regression of that same class instead of catching it.
- **`tests/unit/`** is a bats suite covering the pure config/yq logic that
  doesn't need a device at all: `resolve_config` (the `imports:`
  concatenation + scalar-override cascade), `app_rows`, `obtainium_rows`/
  `effective_obtainium_rows`, and `list_extra_pkgs`. Each `.bats` file
  `source`s the real `declaroid` script (via `helpers/load_declaroid.bash`)
  and calls its functions directly against fixture YAML under
  `fixtures/<function>/` -- `main` is a no-op when sourced, since it's
  guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, which is only true for
  a direct execve, never a `source`. `list_extra_pkgs.bats` stubs `adb` as
  a plain bash *function* defined in `setup()`, not a PATH-prepended
  external script -- a function is resolved before any `$PATH` lookup, so
  it works identically whether or not the environment has a real `adb` or
  even `/usr/bin/env` (the Nix build sandbox notably has neither).
- **`tests/e2e/`** is a bats suite that runs the real built binary against
  a real device/emulator (numbered `01_`/`02_`/`03_` -- bats runs `.bats`
  files in that order, and each file's state depends on the previous
  one: install, then enforce, then uninstall, against the same live
  device within one job). Deliberately avoids `store: gplay` (no Play
  Store on a bare AVD) -- Obtainium itself installs via `store: github`
  directly (`ImranR98/Obtainium`, same asset regex `generate-config`'s
  `known_pkg_override` uses) rather than `store: fdroid`, so the suite
  doesn't need a real F-Droid index sync either. `$GITHUB_TOKEN` (CI's
  ambient one is fine, no extra secret needed) keeps `install_github`'s
  GitHub API calls off the unauthenticated rate limit. Run locally against
  a real connected device with `DECLAROID_BIN=/path/to/declaroid bats
  tests/e2e` -- but note this really does install/enforce/uninstall for
  real; don't point it at a device with anything you care about still on
  it. (This is exactly why CI runs it against a disposable emulator,
  never real hardware.)
- **`.github/workflows/` is six separate workflow files, not one job with
  many steps** -- `shellcheck.yml`, `actionlint.yml`, `nixfmt.yml`,
  `statix.yml`, `unit-tests.yml` (each `nix build`s the matching flake
  `check`, or runs the matching formatter/linter directly), and `e2e.yml`
  (boots a real AVD via `reactivecircus/android-emulator-runner`, `nix
  build`s `declaroid` + `bats`, then runs `tests/e2e` against it). All six
  run on every push/PR, independently -- deliberately not gated behind
  each other (no cross-file `needs:`; GitHub Actions can't express that
  across separate workflow files without a slower `workflow_run` trigger
  anyway), so a red X always points at exactly one failing concern
  instead of a bundled log to scroll through. `e2e` is the slow one, but
  it's the only tier that actually exercises real `adb install`/
  `--enforce`/Obtainium-JSON-seeding code paths -- exactly the class of
  bug that kept slipping through earlier in this file *despite* being
  live-tested, just never through an automated, repeatable harness. Its
  AVD is cached (keyed on api-level/target/arch) with a one-time warm-up
  run to populate the cache on a miss, matching
  `reactivecircus/android-emulator-runner`'s own recommended pattern --
  without it, every single run pays the emulator's full cold boot time.

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
