# declaroid

Declarative Android app provisioning. Define the apps you want on a device in
a YAML file, then `declaroid apply` fetches and installs them, `declaroid
uninstall` removes them, and already-installed apps are skipped automatically.

Apps can come from five sources:

- **Google Play**, via [gplaydl](https://github.com/rehmatworks/gplaydl)
  (anonymous authentication, no Google account needed)
- **F-Droid**, via [fdroidcl](https://github.com/Hoverth/fdroidcl)
- **IzzyOnDroid**, also via fdroidcl, through an isolated fdroidcl config so
  it never mixes into a plain `store: fdroid`
- **GitHub releases**, downloaded directly from a repo's release assets
  (à la [Obtainium](https://github.com/ImranR98/Obtainium))
- **Local APK files** already on disk

## Why

Re-flashing or re-provisioning an Android device (a spare phone, a tablet, a
test device) shouldn't mean manually hunting down APKs and clicking through
installs one by one. Declare what you want once, run `declaroid apply`.

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
$ declaroid apply
INF Target device: 10.5.0.110:43411
Install plan for 10.5.0.110:43411: 3 app(s) to install (1 already installed)
  Google Maps (com.google.android.apps.maps) [gplay]
  Aurora Store (com.aurora.store) [fdroid]
  Findroid Plus (dev.pschmitt.findroidplus) [github]
Install these 3 app(s) on 10.5.0.110:43411? [y/N] y
INF Installing Google Maps (com.google.android.apps.maps) [gplay]
OK Google Maps (com.google.android.apps.maps) installed
INF Installing Aurora Store (com.aurora.store) [fdroid]
OK Aurora Store (com.aurora.store) installed
INF Installing Findroid Plus (dev.pschmitt.findroidplus) [github]
OK Findroid Plus (dev.pschmitt.findroidplus) installed
OK All apps processed successfully
```

See [`apps.yaml.example`](./apps.yaml.example) for a copy-pasteable starting
point.

## Installation

### Nix flake

```console
$ nix run github:pschmitt/declaroid -- apply
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
  `store: fdroid`/`store: izzyondroid` apps (declaroid checks for it lazily,
  only if your config actually uses one of those stores)
- [`fzf`](https://github.com/junegunn/fzf) -- only needed by `add` when a
  search matches more than one app
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
| `apply` | Download (if not already cached) and install configured apps and root modules (shows a plan, prompts to confirm) |
| `uninstall` | Uninstall configured apps (no download) |
| `diff` | Show which configured apps are installed vs missing, no changes made (`--full`: also list device apps not in the config) |
| `modules` | Show configured root modules (APatch/Magisk) vs what's on the device, read-only (`--full`: also list device modules not in the config; `apply` actually installs a missing one) |
| `search QUERY` | Search Google Play and/or F-Droid; no device or config needed |
| `add QUERY` | Search, then append the picked app to the config (fzf picker if more than one match) |
| `download QUERY`, `dl`, `fetch` | Search, then download the picked app's APK(s) to `-o`/`--output` (default: `.`); no device or config needed |
| `devices`, `list` | List connected adb devices (serial, model, codename, connection) |
| `clear-cache [PKG...]` | Remove cached APK downloads, all of them or just the given package(s) |
| `generate-config`, `dump` | Print a YAML config seeded from what's installed on a device |

### Options

| Flag | Applies to | Description |
|---|---|---|
| `-c, --config FILE` | all | Path to the apps YAML config |
| `-d, --device QUERY` | all | Target device (see [device matching](#device-matching)) |
| `-k, --dry-run, --dryrun` | all | Print what would happen instead of doing it (apply/uninstall/clear-cache: what would be installed/removed; `add`: the YAML entry instead of writing it; `download`: what would be downloaded; `generate-config` with `-o`: print instead of writing the file). No-op on commands that are already read-only (`devices`/`diff`/`modules`/`search`) |
| `-f, --force-download` | apply, download | Re-download even if a cached copy exists (gplay only for `download` -- fdroid/izzyondroid cache on fdroidcl's own terms) |
| `--enforce` | apply | Also uninstall device apps that aren't in the config (prompts once per device); same as config `enforce: true` |
| `-g, --grant, --grant-permissions` | apply | Pass `-g` to `adb install`/`install-multiple`, granting every runtime permission at install time instead of prompting later (gplay/github/url/local only, no-op for fdroid/izzyondroid); same as config `grant_permissions: true` |
| `--reboot` | apply | Reboot the target device(s) at the end if any module(s) were installed (no-op otherwise) |
| `-y, --yes, --noconfirm, --no-confirm` | apply, apply --enforce, uninstall, clear-cache | Skip the confirmation prompt |
| `-v, --verbose` | apply | Also log each already-installed app as it's skipped, instead of just a count in the plan |
| `-o, --output FILE\|DIR` | generate-config, download | generate-config: write to FILE instead of stdout; download: DIR to save the APK(s) in (default: `.`) |
| `--system` | generate-config | Include system apps too (default: third-party only) |
| `--no-labels, --fast` | generate-config | Skip app name resolution, use the package id instead |
| `-j, --jobs N` | generate-config | Resolve up to N app names in parallel (default: 6) |
| `--full` | diff, modules | Also list device apps/modules that aren't in the config, as `extra` |
| `--root-framework apatch\|magisk` | apply, modules, generate-config | Force which root framework to use instead of the config's `root.framework`/auto-detection |
| `--store gplay\|fdroid\|izzyondroid\|any` | search, add, download | Which store(s) to search (default: `any`; `izzyondroid` is opt-in, not part of `any`) |
| `-l, --limit N` | search, add, download | Max results per store (default: 10) |
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

Rename whatever comes out wrong or unhelpful. Apps are written out sorted by
this resolved name, case-insensitively (falling back to the package ID, same
as above, wherever a name couldn't be resolved) -- with `--no-labels`/
`--fast`, that's the same as sorting by package ID, since that's what the
name is in that case.

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

### `imports:` -- sharing apps/modules across config files

Running one config per device is natural, but the `apps:`/`modules:` lists
tend to repeat a lot between them. `imports:` pulls in other config file(s)
to cut down on that:

```yaml
# px5.yaml
device: redfin
store: gplay
imports:
  - common-apps.yaml
  - common-modules.yaml

apps:
  - name: Camera
    pkg: com.google.android.GoogleCamera
```

```yaml
# common-apps.yaml -- just a fragment, no device:/store:/etc of its own
apps:
  - name: WhatsApp Messenger
    pkg: com.whatsapp
```

Paths are relative to the file that references them. Each import's
`apps:`/`modules:`/`profiles:`/`obtainium:` entries are merged in first (in
listed order), then the file's own -- pure concatenation, not an override or
a dedup by pkg/id, so listing the same app in both a shared file and the
device file gives you two rows, not one. An import can itself have its
own `imports:` (resolved recursively), and a cycle is detected and
rejected rather than hanging.

`enforce:`/`grant_permissions:`/`store:` cascade in differently -- as a
scalar override, not a concatenation: the importing file's own value wins
if it sets the key at all, otherwise the last import in the list that
sets it does. This is what lets a shared `imports/base.yaml` carry a
default like `enforce: true` for every device that imports it, without
repeating it in every device file:

```yaml
# imports/base.yaml
store: gplay
enforce: true
grant_permissions: true
```

```yaml
# px5.yaml
imports:
  - imports/base.yaml
# no store:/enforce:/grant_permissions: of its own -- inherits all three
```

Every other top-level key (`device:`, `adb:`, `root:`, `profile:`) only
ever comes from the file you actually pointed `--config`/`-c` at -- a
shared fragment is just a library of apps/modules/obtainium repos (plus,
optionally, `enforce:`/`grant_permissions:`/`store:` defaults), not a
device template of its own.

This only applies to `apply`/`uninstall`/`diff`/`modules` -- `add` and
`download` always read (and `add` writes) the file you point them at
exactly as it is on disk, with no merging. Concretely: `add`'s
already-in-config duplicate check only looks at that one file's own
`apps:`, not anything pulled in via `imports:` -- a known limitation, not
an oversight.

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
  device is targeted (apply/uninstall runs once per device).
- **No query at all** (nothing set via flag, env, or config) and more than
  one device connected → you're prompted interactively to pick one, unless
  `--bulk` is given, in which case every connected device is targeted.
- **No query and exactly one device connected** → that device is used, no
  prompt.

If no device is connected at all, or none match, and the config sets
`adb.start_cmd`, that command is run once (via `bash -c`) and device
resolution is retried exactly once more:

```yaml
adb:
  start_cmd: "zhj adb::connect px5.lan"
```

Useful for a wireless-adb device that isn't reliably already connected --
`start_cmd` can be anything (`adb connect host:port`, a wrapper script, a
Home Assistant/Tasker trigger to enable wireless adb first, ...). No further
retries beyond the one: if it still doesn't resolve, this fails the same way
it would without a `start_cmd` configured at all.

The teardown mirror: set `adb.auto_stop: true` and `adb.stop_cmd` to run a
command once a command's real device work is done, e.g. to disconnect
wireless adb again afterward:

```yaml
adb:
  start_cmd: "zhj adb::connect px5.lan"
  auto_stop: true
  stop_cmd: "adb disconnect px5.lan:5555"
```

Applies to `apply`, `uninstall`, `diff`, and `modules` -- whichever command
actually resolved a device via the config. `stop_cmd` is best-effort: a
failing one only logs, it never fails the command itself. `auto_stop`
defaults to `false`, so plain `start_cmd` without it never disconnects
anything on its own.

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

### Root modules (APatch/Magisk)

`declaroid modules` shows which configured root modules -- [APatch](https://github.com/bmax121/APatch)
APModules or [Magisk](https://github.com/topjohnwu/Magisk) modules, same
on-disk format for either -- are actually installed/enabled on the device,
read-only:

```console
$ declaroid modules
INF Target device: 10.5.0.110:42539
NAME                          ID              VERSION          ENABLED  STATUS
Play Integrity Fix [INJECT]   playintegrityfix  v4.7-1-inject-s  yes      installed
Tricky Store                  tricky_store      v1.4.1           yes      installed
```

`--full` also lists installed-but-unconfigured modules as `extra`, same as
`diff --full` does for apps. `modules` itself never installs/enables/
disables/uninstalls anything -- it's read-only drift reporting. To
actually install a missing module, run `apply`: it fetches and installs
any configured module that isn't already present, the same way it does
for apps (a plan first, then a confirmation prompt, skippable with
`-y`/`--yes`/`--noconfirm`/`--no-confirm`, previewable with `--dry-run`).
**declaroid never enables/disables/uninstalls a module, and module state
changes only take effect on next boot for both frameworks** -- it doesn't
reboot the device for you either, so a `WRN ... reboot the device(s) for
changes to take effect` reminder is printed instead after any module
install. Pass `--reboot` to turn that reminder into an actual reboot of
the targeted device(s) once the run finishes (no-op if no module was
installed).

Config schema:

```yaml
root:
  enabled: true|false   # optional; false skips root entirely, no auto-detection
                         # attempted. Omit to auto-detect whether the device has
                         # APatch or Magisk at all.
  framework: apatch|magisk  # optional; skips auto-detection if you already know.
                             # --root-framework overrides both of these, for a
                             # single invocation (also works with generate-config
                             # and apply).
modules:
  - id: <module id>       # matches the module's module.prop id= field
    name: <display name>   # optional, cosmetic only
    source: github|url|local  # optional, defaults to github -- where `apply`
                               # fetches the module zip from
    repo: <owner>/<repo>        # required when source is github
    asset: <regex>               # (github only) selects the release zip;
                                  # default '\.zip$', same multi-asset caveat
                                  # as apps' asset: (see below)
    url: <http(s) URL>            # required when source is url
    path: <file, glob, or dir>     # required when source is local
    enabled: false                 # optional, informational only for now
```

Framework detection (when `root.framework` isn't set) probes the device
directly for the `apd`/`magisk` CLI binary through a root shell, not for
either framework's own app package -- Magisk supports hiding/repackaging
its manager app specifically to evade exactly that kind of check (confirmed
against a real device: Magisk fully installed and running, `pm list
packages com.topjohnwu.magisk` found nothing).

`generate-config` picks this up automatically too: if a framework is
detected, the generated config gets a `root:` section and a `modules:`
list seeded from whatever's actually installed (skipped entirely for a
non-rooted device -- no empty `root:`/`modules:` clutter).

```console
$ declaroid apply
INF Target device: 10.5.0.159:37819
OK Nothing to install on 10.5.0.159:37819 (30 already installed)
Module install plan for 10.5.0.159:37819: 1 module(s) to install
  Play Integrity Fix [INJECT] (playintegrityfix) [github]
Install these 1 module(s) on 10.5.0.159:37819? [y/N] y
INF Installing module Play Integrity Fix [INJECT] (playintegrityfix) [github]
INF Using latest release for KOWX712/PlayIntegrityFix
INF Downloading PlayIntegrityFix_v4.7-1-inject-s.zip
OK Play Integrity Fix [INJECT] (playintegrityfix) installed
OK All modules processed successfully
WRN 1 module(s) installed -- reboot the device(s) for changes to take effect
```

### `obtainium:` -- tracking repos in the Obtainium app

[Obtainium](https://github.com/ImranR98/Obtainium) tracks apps installed from
outside an app store (GitHub releases, direct URLs, ...) and checks them for
updates. It keeps one JSON file per tracked app under its own scoped-storage
`app_data` directory on the device -- `apply` can seed that directly, so a
config can declare "Obtainium should be tracking this repo" the same way it
declares apps/modules:

```yaml
obtainium:
  - pkg: com.kieronquinn.app.smartspacer
    url: "https://github.com/KieronQuinn/Smartspacer"
```

This **requires root** (scoped storage is otherwise unreadable/unwritable
for anything but the owning app itself) and is skipped entirely, with a
notice, on a device with `root.enabled: false`. On a rooted device it's an
**error** (apply exits non-zero) if neither `dev.imranr.obtainium` nor
`dev.imranr.obtainium.fdroid` is installed there -- make sure your config
also installs Obtainium itself as a regular `apps:` entry (or via an
import) if it declares `obtainium:` entries.
`apply` only ever adds missing entries -- an already-tracked `pkg` is left
untouched, so re-running is a no-op. The JSON written is the minimal shape
Obtainium's own `App.fromJson` accepts (id/url/author/name/additionalSettings
-- everything else has an in-app default), not a full vendored copy of its
internal state, so this stays a thin pointer rather than a second source of
truth for the metadata Obtainium tracks on its own (`latestVersion`,
`apkUrls`, etc).

Declaring a repo here never installs the app itself -- that's what `apps:`
is for, same as any other app. `obtainium:` only ever writes Obtainium's
own tracking pointer; if a tracked app isn't actually installed on the
device, it stays that way (`apply` doesn't side-load it, and won't remove
it from Obtainium's tracking either). A tracked pkg does count as
"configured" for `--enforce`/`diff` purposes even without a matching
`apps:` entry, though -- otherwise `--enforce` would see it as an
unrecognized app and offer to uninstall it right out from under Obtainium.

There is no way to force Obtainium to fetch/refresh a newly-seeded entry's
metadata immediately -- it only happens the next time the app is opened, or
via its own ~15 minute background check. Obtainium exposes no headless
"check now" mechanism (only interactive deep-links that require a
confirmation tap), so this is a real, permanent limitation rather than
something declaroid works around.

An optional `settings:` map is merged into that entry's `additionalSettings`
(Obtainium's own per-app config -- track-only vs auto-update, prerelease
inclusion, asset filters, etc; see Obtainium's own UI for the available
keys):

```yaml
obtainium:
  - pkg: org.breezyweather
    url: "https://github.com/breezy-weather/breezy-weather"
    settings:
      trackOnly: true
```

`settings:` keys are Obtainium's own upstream setting names, used verbatim
(see Obtainium's own "Add App"/per-app settings UI for what's available) --
deliberately not translated into a declaroid-specific vocabulary, which
would just be another thing to keep in sync as Obtainium adds or renames
settings over time. `includePrereleases: true` is a common one: needed for
a repo whose only release(s) are marked prerelease on GitHub, since
Obtainium otherwise ignores those entirely by default -- confirmed for a
real repo whose sole release ships under the tag `latest` but with GitHub's
own `prerelease` flag set to `true`, surfacing as Obtainium's own "Could
not find a suitable release" error and no other symptom:

```yaml
obtainium:
  - pkg: dev.pschmitt.findroidplus
    url: "https://github.com/pschmitt/findroidplus"
    settings:
      includePrereleases: true
```

#### `obtainium_auto_track:` -- tracking every `store: github` app automatically

Rather than listing every GitHub-sourced app under `obtainium:` by hand,
set the top-level `obtainium_auto_track: true` to have `apply` track all of
them automatically -- as if each had its own `obtainium:` entry (repo URL
derived from that app's `repo:`, no `settings:`):

```yaml
obtainium_auto_track: true
```

Override it for one specific app with its own `obtainium: true`/`false` --
`true` tracks that app even with the top-level default off; `false` excludes
it even with the default on:

```yaml
apps:
  - name: "Findroid+"
    pkg: dev.pschmitt.findroidplus
    store: github
    repo: "pschmitt/findroidplus"
    obtainium: false   # e.g. already tracked with custom settings: below
```

An app that also has its own explicit `obtainium:` list entry is never
duplicated -- that entry (with whatever `settings:` it carries) always wins
over an auto-derived one for the same `pkg`, regardless of
`obtainium_auto_track:`/the app's own override. `obtainium_auto_track:`
cascades in from `imports:` the same way `enforce:`/`grant_permissions:`/
`store:` do (see the `imports:` section above).

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
once per `apply` invocation if any configured app uses this store.
fdroidcl manages its own APK cache; declaroid doesn't wrap it in its own
cache directory.

#### `izzyondroid`

[IzzyOnDroid](https://apt.izzysoft.de/fdroid/) is a separate F-Droid-format
repo (Aliucord, microG, and other apps that don't fit F-Droid's own
build-from-source policy). Mechanically identical to `fdroid` -- same
`fdroidcl install`/`fdroidcl search` -- but fdroidcl merges every *enabled*
repo in a given config into one combined index with no way to scope a
single command to just one repo, and `fdroidcl repo add` isn't idempotent
(it errors if the repo's already registered) and permanently mutates
whichever config it targets. Registering IzzyOnDroid in your real,
system-wide fdroidcl config would therefore leak its apps into every future
plain `store: fdroid` search/install too.

To avoid that, every `store: izzyondroid` operation runs through an
isolated fdroidcl config under
`${XDG_CACHE_HOME:-$HOME/.cache}/declaroid/fdroidcl-izzyondroid/`, seeded on
first use with *only* the IzzyOnDroid repo (F-Droid's own default repos are
removed from it). That isolation is also what makes `search`/`add
--store izzyondroid` correctly scoped to just IzzyOnDroid results with no
extra filtering -- there's nothing else registered in that config to mix
in. Your real `~/.config/fdroidcl` is never touched by this.

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
ID. A cache hit skips the download entirely on the next `apply` run,
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

Both stores' results are merged into a single table, like `devices`/`diff`
-- rendered with [tsvtool](https://github.com/pschmitt/tsvtool) if it's on
`$PATH`, falling back to `column -t` otherwise (same as `devices`/`diff`).
Redirecting/piping it (`declaroid search whatsapp | cut -f2`) still gets
plain, scriptable TSV: color and the hyperlink below turn off automatically
whenever stdout isn't a terminal (same as `NO_COLOR`).

In an interactive terminal, STORE is colored and the NAME column is an
[OSC 8 hyperlink](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)
to the store listing (supported by kitty, wezterm, iTerm2, and VTE-based
terminals like foot/gnome-terminal) -- the app name is the clickable text,
there's no separate URL column.

`--store` picks `gplay`, `fdroid`, `izzyondroid`, or `any` (default). `any`
means gplay + fdroid -- `izzyondroid` is a separate, explicit opt-in (see
[the izzyondroid store](#izzyondroid) for why), not folded into `any`.
`-l`/`--limit` caps results *per store* (default 10), so `--store any -l 10`
can return up to 20 rows total. Google Play search comes from `gplaydl
search`, which has no version info to offer; F-Droid/IzzyOnDroid search
comes from `fdroidcl search`, which does a fuzzy full-text match against
name/summary/description (a query like "whatsapp" can surface apps that
just mention it, not just apps named it).

All stores are searched case-insensitively. Google Play's search is
case-insensitive on its own; fdroidcl's isn't (its query is a regexp
matched case-sensitively by default), so declaroid prefixes it with the
Go regexp `(?i)` flag.

### `add`: search, then append to the config

`declaroid add QUERY [--store ...] [-c FILE]` runs the same search as
`declaroid search`, then appends the result you pick to the config's
`apps:` list:

```console
$ declaroid add whatsapp --store gplay
INF Searching Google Play for "whatsapp"
INF Found: WhatsApp Messenger (com.whatsapp) [gplay]
OK Added WhatsApp Messenger (com.whatsapp) to ~/.config/declaroid/apps.yaml
```

If exactly one match is found, it's added directly (no prompt). With more
than one match, an [fzf](https://github.com/junegunn/fzf) picker opens: the
list shows name/pkg/store per candidate, and the preview pane shows the
app's info plus the exact YAML that would be appended, colored/bold/italic.
Esc cancels without changing anything.

The append itself is a structural `yq` edit (`.apps += [...]`), not a
text-based insert -- verified against real, hand-commented, `generate-config`-produced files that it leaves every other byte of the file
untouched (header comments, `profiles:`, commented-out `# TODO` entries all
survive). If the picked package is already in the config, `add` skips it
(`SKP ... already in ...`) rather than adding a duplicate entry. The new
entry's `store:` is only written out if it differs from the config's
top-level default (same convention as `generate-config`).

Pass `--dry-run`/`-k`/`--dryrun` to print the YAML entry that would be
appended to stdout instead of actually writing it to the config file.

### `download`/`dl`/`fetch`: search, then save the APK(s)

`declaroid download QUERY [--store ...] [-o DIR]` runs the exact same
search+pick as `add` (same fzf picker, just with a "will download to DIR"
preview instead of "will append to config"), but saves the actual APK
file(s) locally instead of writing a config entry -- no device, and no
config file, needed at all:

```console
$ declaroid download whatsapp --store gplay -o ~/Downloads
INF Searching Google Play for "whatsapp"
INF Found: WhatsApp Messenger (com.whatsapp) [gplay]
INF Downloading com.whatsapp
OK base.apk -> /home/user/Downloads/
```

`gplay` downloads go through the same cache as `apply` (`-f`/
`--force-download` bypasses it the same way too) and may drop more than one
file (base + split APKs) -- every `*.apk` found in the cache dir is copied
out. `fdroid`/`izzyondroid` downloads go through `fdroidcl download`
directly (no adb/device involvement at all, confirmed: it only tries to
detect a connected device to pick the best-matching variant, and silently
skips that if none is found) -- always a single file, and `-f`/
`--force-download` has no effect there since fdroidcl does its own
download caching internally. `-o`/`--output` defaults to the current
directory, and is created if it doesn't exist yet. `github`/`local`/`url`
apps are never reachable here, same as `search`/`add` -- those stores are
never searched, only hand-configured.

Pass `--dry-run`/`-k`/`--dryrun` to print what would be downloaded and
where, without actually downloading anything.

### Table output

`declaroid devices`, `declaroid diff`, and `declaroid search` all render as
a table: using [tsvtool](https://github.com/pschmitt/tsvtool) if it's on
`$PATH`, falling back to `column -t` (with a bolded header) otherwise.
`diff` additionally colors `installed` green, `missing` yellow, `disabled`
cyan, `unwanted` red, `removed` green, and (with `--full`) `extra` red;
`search` colors the STORE column. Both are colored
*after* handing off to tsvtool/`column -t`, not before, so alignment is
never thrown off by invisible color codes. `search` is the one exception
that needs color/links embedded *before* rendering (each row's OSC 8
hyperlink points at a different URL, so it can't be added as a fixed-word
pass afterward) -- tsvtool strips escape sequences out of its input by
default, so `render_table` always passes it `--keep-escape-sequences`
(harmless for devices/diff, which have nothing pre-embedded to begin with).

### `diff --full`: what's installed but not configured

Plain `diff` only ever looks at apps *in the config* and reports
installed/missing for each. `--full` additionally lists every device app
that has no matching `pkg:` entry anywhere in the config, as a third status,
`extra` -- the same GMS/AOSP denylist `generate-config` uses keeps system
plumbing out of that list. This is a read against the device only (a single
`pm list packages -3`); it doesn't resolve app names via `aapt2`, so `extra`
rows show the package id in both the name and pkg columns.

### Install plan and confirmation

`apply` first checks, per device, which configured apps are actually
missing -- nothing is downloaded or installed yet at this point -- then
prints that plan (name/pkg/store of each pending app, plus a count of how
many are already installed) and asks for confirmation before doing anything,
per device. Already-installed apps are only ever summarized as a count here,
not logged individually; pass `-v`/`--verbose` to also see each one as it's
skipped during the actual install pass. Skip the prompt with
`-y`/`--yes`/`--noconfirm`/`--no-confirm`, or preview it without installing
anything via `--dry-run`. Declining for a device just skips installing on
that device -- `--enforce` (below) still runs afterward if requested.

### Uninstall confirmation

`uninstall` lists the apps and device(s) it's about to touch and asks for
confirmation, unless `--dry-run` or `-y`/`--yes`/`--noconfirm`/`--no-confirm`
is given.

### `apply --enforce`: removing what's not configured

`apply --enforce` runs the normal install, then -- per device -- finds the
same "extra" apps `diff --full` would report and offers to uninstall them,
prompting once for the whole batch (not once per app). Skip the prompt with
`-y`/`--yes`/`--noconfirm`/`--no-confirm`, or preview it without uninstalling
anything via `--dry-run`.

Set `enforce: true` at the top level of the config to make this the default
for that device/config, instead of having to pass `--enforce` every time:

```yaml
enforce: true
```

The CLI flag and the config key OR together -- either one is enough to turn
it on for a given run.

### `grant_permissions:` -- skip the runtime permission prompts

By default, `adb install` leaves every dangerous runtime permission
ungranted -- the app prompts for each one itself the first time it needs
it. Passing `-g` (`adb install -g`/`install-multiple -g`) grants all of
them upfront instead, at install time. `apply -g`/`--grant`/
`--grant-permissions`, or the equivalent config key, turns this on:

```yaml
grant_permissions: true
```

Same OR semantics as `enforce:` above -- the CLI flag and the config key
either one is enough. Only affects `gplay`/`github`/`url`/`local` installs
(all of them go through a real `adb install`/`install-multiple`
underneath); a no-op for `fdroid`/`izzyondroid`, since `fdroidcl install`
has no equivalent flag at all.

### Per-app `state:` -- not desired, or disabled

Each app entry can have a `state:` block:

```yaml
apps:
  - name: Facebook
    pkg: com.facebook.katana
    state:
      disabled: true

  - name: Bloatware I Don't Want Anymore
    pkg: com.example.bloat
    state:
      installed: false
```

- **`installed: false`** means this app isn't desired at all, even though its
  entry stays in the config. `apply` skips installing it (it won't show up
  in the normal install plan) and, if it's already present on the device,
  uninstalls it -- unconditionally, with its own plan+confirm step, no
  `--enforce` needed. This is different from `--enforce`'s "anything
  undeclared": here the app is still explicitly listed, just marked unwanted.
- **`disabled: true`** means the app should be installed (if missing) and
  then disabled via `pm disable-user` -- present but dormant, not "don't
  install". `apply` re-enables it (`pm enable`) if you flip this back to
  `false` or remove it. `pm disable-user` was chosen over `pm archive`:
  archiving frees the APK's storage, but un-archiving depends on the
  installer supporting an unarchive request, which isn't a safe assumption
  for anything other than `gplay` -- `disable-user` works uniformly
  regardless of store and is always reversible.

`diff` reflects both: an `installed: false` app shows as `unwanted` (present
but shouldn't be) or `removed` (correctly absent), and any app actually
disabled on the device (regardless of what `state.disabled` says) shows as
`disabled` instead of `installed`.

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
