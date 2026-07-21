# declaroid

Declarative Android app provisioning. Define the apps you want on a device in
a YAML file, then `declaroid install` fetches and installs them, `declaroid
uninstall` removes them, and already-installed apps are skipped automatically.

Apps can come from four sources:

- **Google Play**, via [gplaydl](https://github.com/rehmatworks/gplaydl)
  (anonymous authentication, no Google account needed)
- **F-Droid**, via [fdroidcl](https://github.com/Hoverth/fdroidcl)
- **GitHub releases**, downloaded directly from a repo's release assets
  (à la [Obtainium](https://github.com/ImranR98/Obtainium))
- **Local APK files** already on disk

## Why

Re-flashing or re-provisioning an Android device (a spare phone, a tablet, a
test device) shouldn't mean manually hunting down APKs and clicking through
installs one by one. Declare what you want once, run `declaroid install`.

## Example

```yaml
# ~/.config/declaroid/apps.yaml
device: redfin
store: gplay

apps:
  - name: DB Navigator
    pkg: de.hafas.android.db

  - name: Google Maps
    pkg: com.google.android.apps.maps

  - name: Aurora Store
    pkg: com.aurora.store
    store: fdroid

  - name: Findroid Plus
    pkg: dev.pschmitt.findroidplus
    store: github
    repo: pschmitt/findroidplus
    asset: 'phone-arm64-v8a-release\.apk$'
```

```console
$ declaroid install
==> Target device: 10.5.0.110:43411
[skip] DB Navigator (de.hafas.android.db) already installed
==> Installing Google Maps (com.google.android.apps.maps) [gplay]
[ok] Google Maps (com.google.android.apps.maps) installed
==> Installing Aurora Store (com.aurora.store) [fdroid]
[ok] Aurora Store (com.aurora.store) installed
==> Installing Findroid Plus (dev.pschmitt.findroidplus) [github]
[ok] Findroid Plus (dev.pschmitt.findroidplus) installed
[ok] All apps processed successfully
```

See [`apps.yaml.example`](./apps.yaml.example) for a copy-pasteable starting
point.

## Installation

### Nix flake

```console
$ nix run github:pschmitt/declaroid -- install
```

Or add it as a flake input and use `packages.<system>.declaroid` /
`packages.<system>.default`:

```nix
{
  inputs.declaroid.url = "github:pschmitt/declaroid";

  outputs = { self, nixpkgs, declaroid, ... }: {
    # e.g. in a Home Manager module
    home.packages = [
      declaroid.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
```

The flake also exposes `packages.<system>.gplaydl` on its own, in case you
just want that.

### Manually

`declaroid` is a single bash script with no build step. Its runtime
dependencies are:

- [`adb`](https://developer.android.com/tools/adb) (`android-tools`)
- [`yq`](https://github.com/mikefarah/yq) (the Go/mikefarah one, not the
  Python/kislyuk one)
- `curl`, `jq`, coreutils (`sha256sum`, `mkdir`, ...), `find`
- [`gplaydl`](https://github.com/rehmatworks/gplaydl) -- only needed for
  `store: gplay` apps
- [`fdroidcl`](https://github.com/Hoverth/fdroidcl) -- only needed for
  `store: fdroid` apps (declaroid checks for it lazily, only if your config
  actually uses the fdroid store)
- `aapt2` (nixpkgs: `aapt`) -- optional, only used by `generate-config` to
  read human-readable app names; falls back to the package ID if missing
- [`tsvtool`](https://github.com/pschmitt/tsvtool) -- optional, prettier
  table output for `devices`/`diff`; falls back to `column -t`

Put `declaroid` on your `$PATH` and make sure the above are too.

## Usage

```console
$ declaroid COMMAND [OPTIONS]
```

### Commands

| Command | Description |
|---|---|
| `install` | Download (if not already cached) and install configured apps |
| `uninstall` | Uninstall configured apps (no download) |
| `diff` | Show which configured apps are installed vs missing, no changes made (`--full`: also list device apps not in the config) |
| `search QUERY` | Search Google Play and/or F-Droid; no device or config needed |
| `devices`, `list` | List connected adb devices (serial, model, codename, connection) |
| `clear-cache [PKG...]` | Remove cached APK downloads, all of them or just the given package(s) |
| `generate-config`, `dump` | Print a YAML config seeded from what's installed on a device |

### Options

| Flag | Applies to | Description |
|---|---|---|
| `-c, --config FILE` | all | Path to the apps YAML config |
| `-d, --device QUERY` | all | Target device (see [device matching](#device-matching)) |
| `--dry-run` | install, uninstall | Print what would happen, don't do it |
| `-f, --force-download` | install | Re-download even if a cached copy exists |
| `--enforce` | install | Also uninstall device apps that aren't in the config (prompts once per device) |
| `-y, --yes, --noconfirm, --no-confirm` | install --enforce, uninstall, clear-cache | Skip the confirmation prompt |
| `-o, --output FILE` | generate-config | Write to FILE instead of stdout |
| `--system` | generate-config | Include system apps too (default: third-party only) |
| `--no-labels, --fast` | generate-config | Skip app name resolution, use the package id instead |
| `-j, --jobs N` | generate-config | Resolve up to N app names in parallel (default: 6) |
| `--full` | diff | Also list device apps that aren't in the config, as `extra` |
| `--store gplay\|fdroid\|all` | search | Which store(s) to search (default: `all`) |
| `-l, --limit N` | search | Max results per store (default: 10) |
| `--sort-by KEY` | diff, devices | Sort output case-insensitively. diff: `name` (default) or `pkg`. devices: `serial` (default), `model`, `codename`, or `connection` |
| `--bulk, --all-devices, --all` | all | Target every matching device instead of erroring out on ambiguity |
| `-h, --help` | all | Show help |

### Generating a config from an existing device

Already have a phone set up the way you want and just want a starting
`apps.yaml`? `generate-config` lists installed packages (`pm list packages`,
third-party only by default) and writes one app entry per package:

```console
$ declaroid generate-config --device redfin -o ~/.config/declaroid/apps.yaml
```

App names are read from each APK's `application-label` via
[`aapt2`](https://developer.android.com/tools/aapt2) (part of nixpkgs'
`aapt` package -- the Nix-built `declaroid` has it out of the box). This
means pulling every app's `base.apk` off the device, which is slow for large
apps and adds up across a big app list, so:

- resolution runs in parallel, up to `-j`/`--jobs` apps at a time (default 6)
- results are cached under `${XDG_CACHE_HOME:-$HOME/.cache}/declaroid/<package-id>/`
  (the same place APK downloads are cached), so re-running `generate-config`
  later is instant for any app it already resolved a name for --
  `declaroid clear-cache [pkg]` clears this too
- pass `--no-labels`/`--fast` to skip resolution entirely and just use the
  package ID as the name (also the automatic fallback if `aapt2` isn't
  installed)

Rename whatever comes out wrong or unhelpful.

`store` is guessed from each app's installer attribution
(`pm list packages -i`):

| Installer | Detected store |
|---|---|
| `com.android.vending` | `gplay` |
| `org.fdroid.fdroid` | `fdroid` |
| anything containing `obtainium` | `github`, but Obtainium doesn't expose which repo it used |
| anything else (`com.google.android.packageinstaller`, `null`, a browser, ...) | unknown -- there's no way to tell `local`/`fdroid`/`github` apart from this alone |

Since `gplay` is overwhelmingly the common case, the generated config sets
it as the top-level default (`store: gplay`) and only gives an app its own
`store:` line when it differs from that.

Reinstalling from this config as-is would fail for the last two cases (no
`repo` to fetch, or no `store` at all), so those entries are written out
**commented out**, with a `# TODO: ...` line explaining why right above
them -- fill in the missing piece and uncomment to include them.

Each app also gets a `profile:` (see [Android user/profile targeting](#android-userprofile-targeting))
if it's installed anywhere other than just the device's current profile:
`generate-config` enumerates every profile (`pm list users`) and checks
each app against all of them, so a secondary profile doesn't need to be
"the" other one -- if a device somehow has three or more, an app installed
in more than one (but not literally all) still gets `profile: all`, since
that's the closest value expressible via a single `--user` flag.

A small denylist filters out GMS/AOSP system plumbing that routinely leaks
into `pm list packages -3` ("third-party") because it's been updated via the
Play Store at some point (`com.google.android.gms`, `com.android.vending`
itself, Android Device Policy, Safety Core, and similar background
components -- see `is_system_plumbing_pkg` in the script). It's a
best-effort list, not exhaustive; extend it if something obviously-not-an-app
shows up in your output. Pass `--system` to include system apps in the scan
in the first place (the denylist still applies on top of that).

Review the output before using it either way -- this is a starting point,
not a guarantee.

### Config resolution

In order:

1. `--config FILE`
2. `$DECLAROID_CONFIG`
3. `${XDG_CONFIG_HOME:-$HOME/.config}/declaroid/apps.yaml`

### Device matching

Declaroid resolves a target device in this order: `--device`,
`$TARGET_DEVICE`, `.device` in the config. Whatever value it finds is matched
as a **case-insensitive substring** against every connected device's serial,
USB path, product, model, and codename (as reported by `adb devices -l`) --
so `redfin`, `clover`, part of a serial, or an IP address all work, and it
doesn't need to be an exact match.

- **Exactly one match** → that device is used.
- **Multiple matches** → declaroid errors out and lists what matched, unless
  `--bulk`/`--all-devices`/`--all` is given, in which case *every* matching
  device is targeted (install/uninstall runs once per device).
- **No query at all** (nothing set via flag, env, or config) and more than
  one device connected → you're prompted interactively to pick one, unless
  `--bulk` is given, in which case every connected device is targeted.
- **No query and exactly one device connected** → that device is used, no
  prompt.

### Android user/profile targeting

If a device has more than one Android user profile -- a Work Profile, a
profile created by something like [Island](https://github.com/oasisfeng/island),
a second full user account -- `adb install`/`install-multiple` without an
explicit `--user` were observed behaving inconsistently on a real device:
not reliably "the current profile", not reliably "all profiles", and not
even consistent with each other for the same app. So declaroid always
resolves a target explicitly rather than relying on that default:

1. The per-app `profile:` (or the top-level default) from the config, if set
   -- a user id (e.g. `0`), or the literal `all` or `current` (passed
   straight through to `adb`/`fdroidcl`'s own `--user`/`-user` flag,
   unvalidated).
2. Otherwise, the device's current profile as reported by
   `adb shell am get-current-user` -- normally the personal/parent profile,
   even when a secondary profile happens to be more "active" in some sense.
3. If that can't be determined either (no multi-user support, a transient
   adb hiccup), no `--user` is passed at all -- whatever the device's own
   default install behavior is.

**This never defaults to `all` on its own.** Installing into every profile
is an explicit opt-in (`profile: all`), not something that happens because
you didn't configure anything.

fdroidcl has its own `-user` flag (and its own "current user" default when
it's not given), so `store: fdroid` respects `profile:` too. `uninstall`
doesn't pass `--user` at all -- it removes the app from wherever it's
actually installed, on the theory that "uninstall X" should mean X is gone,
not "gone from one specific profile, possibly still present in another."

### Stores

Each app entry has a `store`, defaulting to whatever the top-level `store:`
key says (which itself defaults to `gplay` if omitted entirely).

#### `gplay` (default)

Uses `gplaydl download <pkg> -o <cache-dir>` to fetch the base APK plus any
split APKs, then `adb install-multiple`. gplaydl has a quirk where apps
without a real Play Asset Delivery pack still get a `-asset.apk` file that's
byte-identical to the base APK -- declaroid detects and skips exact
duplicate splits by checksum before installing, so this doesn't cause
`INSTALL_FAILED_INVALID_APK: Split null was defined multiple times`.

If an app has no splits left after deduping (just the base APK), it's
installed with `adb install -i com.android.vending` instead of
`install-multiple`, so a later `generate-config` run correctly recognizes it
as `gplay` (see [Generating a config](#generating-a-config-from-an-existing-device)).
This isn't done for split installs: `adb install-multiple -i ... ` was
tested against a real device and reliably hangs rather than erroring.

#### `fdroid`

Uses `fdroidcl install <pkg>` against the target device (via `$ANDROID_SERIAL`,
which is how fdroidcl itself picks a device). declaroid runs `fdroidcl update`
once per `install` invocation if any configured app uses this store.
fdroidcl manages its own APK cache; declaroid doesn't wrap it in its own
cache directory.

#### `github`

Fetches an APK straight from a GitHub repo's releases, no F-Droid/Play Store
listing required. Needs two extra fields on the app entry:

```yaml
- name: Some App
  pkg: com.example.app
  store: github
  repo: owner/reponame
  asset: 'some-regex\.apk$'   # optional, default: '\.apk$'
```

declaroid queries `GET /repos/<repo>/releases/latest` first; if that repo has
no non-prerelease release (404), it falls back to the most recent entry in
`GET /repos/<repo>/releases` (including prereleases) -- mirroring what you'd
get by just looking at the repo's releases page. The `asset` regex is
matched against release asset filenames via `jq`'s `test()`; it must match
**exactly one** asset, so narrow it down for repos that publish multiple
APKs per release (different ABIs, flavors, debug/release builds, etc). Set
`$GITHUB_TOKEN` to raise the unauthenticated rate limit or access private
repos.

`pkg` still has to be the real Android package ID (used for the
already-installed check and as the cache key) -- declaroid doesn't inspect
the downloaded APK to figure this out for you, so get it from `aapt dump
badging` or by installing once and checking `adb shell pm list packages`.

#### `local`

Installs an APK (or split APKs) already sitting on disk -- no download at
all. Needs a `path` on the app entry:

```yaml
- name: Some App
  pkg: com.example.app
  store: local
  path: /home/me/apks/some-app.apk        # a single file
  # path: /home/me/apks/some-app-*.apk    # or a glob matching several splits
  # path: /home/me/apks/some-app-splits/  # or a directory (every *.apk in it)
```

Like `gplay`, split APKs are deduped by checksum before `adb install-multiple`.

### Caching

Downloads for `gplay` and `github` apps are cached under
`${XDG_CACHE_HOME:-$HOME/.cache}/declaroid/<package-id>/`, keyed by package
ID. A cache hit skips the download entirely on the next `install` run,
which matters because gplay/github downloads can be tens to hundreds of MB.
Use `-f`/`--force-download` to bypass the cache for one run, or
`declaroid clear-cache` to wipe it (the whole thing, or just specific
packages: `declaroid clear-cache com.example.app`).

fdroid apps aren't cached by declaroid -- fdroidcl already caches its own
downloads. local apps aren't cached either -- there's nothing to download.

`generate-config`'s resolved app names are cached the same way (as
`<package-id>/.label`), regardless of store.

### `search`: finding a package id

Don't know an app's package id yet (needed for `pkg:` in the config)?
`declaroid search QUERY` looks it up on Google Play and/or F-Droid -- no
device or config required:

```console
$ declaroid search whatsapp --store gplay
NAME                 PKG            STORE
WhatsApp Messenger   com.whatsapp   gplay
```

Output is real TSV (tab-separated, header row included), so it's safe to
pipe into `cut`/`awk`/etc. In an interactive terminal it's additionally
colored, and the NAME column is an [OSC 8 hyperlink](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)
to the store listing (supported by kitty, wezterm, iTerm2, and VTE-based
terminals like foot/gnome-terminal) -- the app name is the clickable text,
there's no separate URL column. Piping or redirecting the output turns both
color and links off automatically (same as `NO_COLOR`), so scripted
consumers never see escape codes mixed into the data.

`--store` picks `gplay`, `fdroid`, or `all` (default). `-l`/`--limit` caps
results *per store* (default 10), so `--store all -l 10` can return up to
20 rows total. Google Play search comes from `gplaydl search`, which has no
version info to offer; F-Droid search comes from `fdroidcl search`, which
does a fuzzy full-text match against name/summary/description (a query like
"whatsapp" can surface apps that just mention it, not just apps named it).

Both stores are searched case-insensitively. Google Play's search is
case-insensitive on its own; F-Droid's isn't (its query is a regexp
matched case-sensitively by default), so declaroid prefixes it with the
Go regexp `(?i)` flag.

### Table output

`declaroid devices` and `declaroid diff` render as a table: using
[tsvtool](https://github.com/pschmitt/tsvtool) if it's on `$PATH`, falling
back to `column -t` (with a bolded header) otherwise. `diff` additionally
colors `installed` green, `missing` yellow, and (with `--full`) `extra` red,
regardless of which renderer was used.

### `diff --full`: what's installed but not configured

Plain `diff` only ever looks at apps *in the config* and reports
installed/missing for each. `--full` additionally lists every device app
that has no matching `pkg:` entry anywhere in the config, as a third status,
`extra` -- the same GMS/AOSP denylist `generate-config` uses keeps system
plumbing out of that list. This is a read against the device only (a single
`pm list packages -3`); it doesn't resolve app names via `aapt2`, so `extra`
rows show the package id in both the name and pkg columns.

### Uninstall confirmation

`uninstall` lists the apps and device(s) it's about to touch and asks for
confirmation, unless `--dry-run` or `-y`/`--yes`/`--noconfirm`/`--no-confirm`
is given.

### `install --enforce`: removing what's not configured

`install --enforce` runs the normal install, then -- per device -- finds the
same "extra" apps `diff --full` would report and offers to uninstall them,
prompting once for the whole batch (not once per app). Skip the prompt with
`-y`/`--yes`/`--noconfirm`/`--no-confirm`, or preview it without uninstalling
anything via `--dry-run`.

## Shell completion

A zsh completion function is at
[`completions/_declaroid`](./completions/_declaroid) -- it completes
commands, flags, and `-d`/`--device` from currently connected adb devices
(serial + model/codename). The Nix package installs it to
`share/zsh/site-functions/_declaroid` automatically; if `declaroid` is on
your `$fpath` via that or your own `.zshrc`, completion just works.

## Development

The whole tool is the `declaroid` bash script at the repo root, plus a Nix
flake that packages it and its dependencies (`gplaydl` isn't in nixpkgs, so
it's vendored here at `pkgs/gplaydl`; `fdroidcl` and everything else are
pulled straight from nixpkgs).

```console
$ nix build .#declaroid
$ nix flake check   # if/when checks are added
$ shellcheck declaroid
```

Keep this README in sync with the script's actual behavior -- see
[AGENTS.md](./AGENTS.md).

## License

GPL-3.0-or-later. See [LICENSE](./LICENSE).
