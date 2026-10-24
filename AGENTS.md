# Repository Guidelines

`doha-roms` is a build and porting kit for the Motorola Moto G8 Plus (`doha`, XT2019-1/2, Snapdragon 665/trinket, `amogus_doha` build target). The working tree contains no application source: the "code" is Bash orchestration, a pinned `repo` manifest, git patches, SELinux drop-ins, and Android product makefile fragments. The deliverable is a flashable LineageOS 23.2 (Android 16) ROM; Android 17 (crDroid 17.0) exists only as an unbuilt bring-up kit.

## Project Overview

- One proven target: LineageOS 23.2 / Android 16, built from `default.xml` (1,184 pinned projects) plus 17 patches and two overlay layers (latent fixes, variants).
- One user entry point: `bash doha.sh`, a menu plus non-interactive subcommands. It delegates all real work to `lineage-16/build.sh`.
- Scope status: base hardware (Wi-Fi, BT, NFC, GPS, camera, audio, fingerprint) is user-tested; touch and the governor fix are root-cause-proven but flash-pending; SIM 1 calls are `PARTIAL`; Dolby is experimental; Android 17 is explicitly NOT built or tested.
- Golden rules: never apply patches or fixes manually; never reorder the build layers; never state a feature works without device evidence (`docs/BUG-REGISTER.md`, `docs/ANALYSIS.md`).

## Architecture & Data Flow

Two-tier orchestration, with `lineage-16/build.sh` as the only pipeline:

```
doha.sh (menu / CLI)
  -> repo init -u <this repo> -b <branch> -m default.xml
  -> scripts/restore-mirrors.sh        # 27 device projects -> file://mirrors/git
  -> repo sync                         # 1,184 projects, 27 from local mirrors
  -> patches                           # lineage-16/patches/<repo path>.patch
  -> scripts/apply-latent-fixes.sh     # post_boot shim, 10 sepolicy rules, prop labels
  -> variant layer                     # cpugov rc + doha-variants.mk + Dolby blobs
  -> breakfast amogus_doha userdebug
  -> mka -j$JOBS target-files-package bacon
  -> copy zip + boot/dtbo/vbmeta to $ZIP_DIR, write .sha256sum
```

The layer order is contractual: patches, then latent fixes, then variants, then the build. The variant layer is deliberately last so `PRODUCT_PACKAGES` filter-outs run after LineageOS and AOSP product config.

Key mechanics:

- Patch identity is the filename: `lineage-16/patches/device/motorola/amogus_doha.patch` applies inside the synced project at `device/motorola/amogus_doha/`. Patch diff paths are project-relative, not AOSP-root-relative.
- `@SKIN_THROTTLE_MC@` is the only patch placeholder; `render_patch()` substitutes `SKIN_THROTTLE_C * 1000` before hashing/applying.
- Patch application is content-addressed and idempotent via `$SRC/.repo/doha-patches` (`project <patch-blob> <worktree-tree>`). A changed patch or dirty tree triggers `git reset --hard` plus `git clean -fd` in that project, then a single `git apply`.
- Zero discovered patches is a hard failure ("refusing to build an unpatched ROM").
- Sync ordering is contractual: `repo init` -> mirror restore -> `repo sync`. A mirror restore failure only warns and falls back to upstream GitHub.
- Variants render `device/motorola/amogus_doha/doha-variants.mk` and append a `-include` at the end of `lineage_amogus_doha.mk`; the append is marker-guarded (`doha-roms variant hook`).
- `crdroid-17/` is a frozen overlay kit: manifest, snippets, local manifest, and a 17-row patch re-target table. `doha.sh build17` runs its own `repo init/sync`, then stops or optionally builds.

Data produced locally (never hand-edited): `mirrors/git/`, `.repo/local_manifests/doha-mirror.xml`, `doha-variants.mk`, `init.doha.cpugov.rc` (installed copy), `$SRC/.repo/doha-patches`, `logs/doha-*.log`.

## Key Directories

| Path | Purpose | Notes |
|---|---|---|
| `doha.sh` | Single entry point and dispatcher | `set -u` only; most actions log to `logs/`; `status`/`cloud` are print-only and `flash` misses `log_init` |
| `lineage-16/build.sh` | The real build pipeline | `set -euo pipefail`; source of truth for env vars |
| `lineage-16/patches/` | One patch per repo path | 17 files, including `device/lineage/sepolicy.patch` |
| `latent-fixes/` | SELinux `allow` drop-ins and property labels | B1-B10, installed into the synced tree |
| `variants/` | Debloat tiers, CPU governor rc, Dolby wiring | Rendered, not copied wholesale |
| `scripts/` | Mirror, latent-fix, test, flash, debug tooling | Mostly `set -uo pipefail` |
| `mirrors/repos/` | Vendored device git tarballs + `.fact` rows | Committed; `mirrors/git/` is generated |
| `crdroid-17/` | Android 17 manifests and patch map | Not built; do not describe as working |
| `docs/` | Evidence, bug register, infra and feature docs | Cite these instead of guessing |
| `cloud/colab_doha.sh` | Colab CPU runtime wrapper | Requires mounted Google Drive |
| `platform-tools/` | Windows `adb`/`fastboot` binaries | Untracked in this checkout |
| `device dumps/` | Timestamped device diagnostics | Gitignored; may contain personal data |

`README.md` is the human overview; `WORKLOG.md` is the append-only project history and decision log; `docs/BUG-REGISTER.md` is the authoritative bug status list.

## Development Commands

Run scripts with `bash`, from any cwd (they resolve their own paths), but build only on Linux. `doha.sh` and `build.sh` assume GNU `nproc`, `free`, `df -BG`, `mapfile`, and a `repo` checkout.

```bash
# Interactive menu (setup, sync, build, flash, dump, vendor)
bash doha.sh

# Non-interactive
bash doha.sh env
bash doha.sh sync
bash doha.sh build16 --variant gapps --debloat safe --dolby --jobs 16
bash doha.sh build16 --src /path/to/src
bash doha.sh selftest
bash doha.sh flash          # interactive terminal only; refuses batch mode
bash doha.sh dump
bash doha.sh vendor         # one-time, resumable mirror vendoring
bash doha.sh help
```

Direct build:

```bash
# Docker (README's recommended flow)
docker run --rm -it --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/manifest:ro" -v ~/doha/src:/src \
  -v ~/doha/ccache:/ccache -e CCACHE_DIR=/ccache \
  -v ~/doha/zips:/zips -e ZIP_DIR=/zips \
  --entrypoint /manifest/lineage-16/build.sh \
  lineageos4microg/docker-lineage-cicd:latest /src

# Native Linux
bash lineage-16/build.sh ~/doha/src

# Variants / rebuilds
VARIANT=gapps bash lineage-16/build.sh ~/doha/src
VARIANT=gapps DEBLOAT=aggressive DOLBY=1 bash lineage-16/build.sh ~/doha/src
SKIP_SYNC=1 bash lineage-16/build.sh ~/doha/src
```

Environment variables read by `lineage-16/build.sh`:

| Variable | Default | Effect |
|---|---|---|
| `JOBS` | `nproc` | `mka -j` |
| `SYNC_JOBS` | `4` | `repo sync -j`; kept low to avoid googlesource HTTP 429 |
| `MANIFEST_URL` | this repo root | `repo init -u` |
| `MANIFEST_BRANCH` | checked-out branch, else `main` | `repo init -b`; must be a branch, not detached HEAD |
| `SKIP_SYNC` | `0` | `1` skips init, mirror restore, and sync |
| `STOP_AFTER_SYNC` | `0` | `1` stops before patches/build (used by `doha.sh sync`) |
| `CCACHE_SIZE` | `50G` | `ccache -M` when ccache is on PATH |
| `SKIN_THROTTLE_C` | `40` | Thermal trip substituted into the thermal patch |
| `ZIP_DIR` | `<src>/../zips` | Artifact destination |
| `VARIANT` | `nogapps` | `nogapps` or `gapps` |
| `DEBLOAT` | `none`, or `safe` when gapps | `none`, `safe`, `aggressive` |
| `DOLBY` | `0` | `1` requires populated `variants/dolby/blobs/` |
| `LATENT_FIXES` | `1` | `0` skips `apply-latent-fixes.sh` |

Artifacts: `lineage-<version><suffix>.zip`, `-boot.img`, `-dtbo.img`, `-vbmeta.img`, and `.sha256sum` in `ZIP_DIR`. Suffix order is `-gapps`, `-<debloat>`, `-dolby`.

## Code Conventions & Common Patterns

- Strictness tiers: `lineage-16/build.sh` and `selftest-paths.sh` use `set -euo pipefail`; most helper scripts use `set -uo pipefail` and warn instead of aborting; `doha.sh`, `flash-checks.sh`, and `debug_device.sh` use only `set -u` (diagnostics must not abort on one failed probe).
- AOSP env functions are not errexit-clean: `build.sh` wraps `source build/envsetup.sh`, `breakfast`, and `mka` in `set +eu ... set -eu` with `|| exit 1` per step.
- Naming: dispatcher actions are `action_<subcommand>`; helpers are `verb_noun` (`log_init`, `run_logged`, `render_patch`, `reset_project`, `worktree_id`). Failure helpers differ by file: `die` in `doha.sh`, `fail` in `colab_doha.sh`, inline `echo ... >&2; exit 1` elsewhere.
- Path resolution always uses `HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`, never `$PWD` or a relative guess. `build.sh` validates its layout and refuses to run if `patches/`, `variants/`, `latent-fixes/`, or `apply-latent-fixes.sh` are missing.
- Quoting: all expansions are quoted; command substitution uses `$(...)`; arrays use `mapfile -t`; filename loops over grep output use `--null` plus `read -r -d ''`.
- Logging: `== phase ==` banners, `WARNING:` / `BROKEN` / `SKIP` status words, three-space indented details. `run_logged` returns `${PIPESTATUS[0]}` so `tee` cannot mask failure.
- Batch safety: any `doha.sh` subcommand sets `DOHA_BATCH=1`; `confirm` then auto-answers yes so piped runs cannot skip work and exit 0. `action_flash` refuses batch mode outright.
- Idempotency is explicit everywhere: content+tree stamp for patches; marker strings before appends (`doha-roms variant hook`, `# doha-roms latent-fixes property_contexts (B20)`); `grep -q` guards; `rm -rf` + re-extract for mirrors; atomic `write .new && mv` for stamps and generated tables.
- Generated files announce themselves ("Generated ... Do not edit", "AUTO-GENERATED") and are regenerated every run.
- Patches: one file per project, filename equals the synced `path`, exact hunk headers, preserve tabs, no binary diffs. Test applicability against a real project before committing.
- Variants: add an env knob + a template fragment under `variants/` + a render hook in `build.sh` + a doc in `docs/`. Debloat uses `PRODUCT_PACKAGES := $(filter-out <modules>,$(PRODUCT_PACKAGES))`, never a removal manifest.
- SELinux: `latent-fixes/*.te` contain only independent `allow` blocks. No `type`, `genfscon`, `set_prop`, or macros. Put rules beside the tree that declares their source domain; put property relabels in `property_contexts.add`.
- Manifests: pins are full 40-hex `revision` values; almost every entry also carries `upstream` and `dest-branch`. `name` is the git repo, `path` is the checkout. Community pins use `groups="local::doha"`; local manifests auto-derive the `local::<filename>` group, which is why the overlay must be copied as `doha.xml`.
- Never edit files in a synced project tree (`lineage/`, `device/`, `vendor/`, `kernel/`): `reset_project` destroys local changes and untracked files before patching. Express changes as a patch.

## Important Files

| File | Why it matters |
|---|---|
| `default.xml` | Pinned Android 16 manifest; build.sh refuses an uncommitted copy |
| `lineage-16/build.sh` | Canonical pipeline and env-var contract |
| `lineage-16/patches/**` | All source-level fixes, including touch and WPA3 |
| `doha.sh` | User-facing dispatch, logging, batch and flash safety |
| `scripts/apply-latent-fixes.sh` | Installs sepolicy, property labels, post_boot interpreter fix, typo fix |
| `scripts/vendor-mirrors.sh` / `scripts/restore-mirrors.sh` | Vendored device repos and generated `doha-mirror.xml` |
| `variants/debloat*.mk`, `variants/dolby/`, `variants/init.doha.cpugov.rc` | Editions, Dolby, governor guard |
| `latent-fixes/doha_amogus_fixes.te`, `doha_qcom_fixes.te`, `property_contexts.add` | Runtime bug fix layer |
| `scripts/selftest-paths.sh`, `scripts/selftest-dryrun.sh` | Regression and dry-run batteries |
| `scripts/flash-checks.sh`, `scripts/debug_device.sh` | On-device verification and diagnostics |
| `docs/BUG-REGISTER.md`, `docs/ANALYSIS.md`, `docs/BUILD-INFRA.md` | Evidence, status vocabulary, build infrastructure |
| `WORKLOG.md` | Append-only history and decisions |
| `crdroid-17/README.md`, `crdroid-17/patches/README.md` | Android 17 status and patch re-target map |

## Runtime/Tooling Preferences

- Build host: x86-64 Linux, preferably Docker; ~350 GB free disk, 32 GB RAM plus swap, ~100 GB download. Measured clean build is about 2 h 51 min on 16 threads; warm ccache rebuild is about 7 min.
- No package manager, lockfile, or pinned tool versions. Required: `bash` 4+, `git` with LFS, `repo`, `ccache`, GNU coreutils; `python3` for the self-tests; `adb`/`fastboot` for device work.
- `SYNC_JOBS=4` is intentional. Raising it causes HTTP 429 storms from android.googlesource.com; rerun resumes.
- The repo must be a git repository with `default.xml` committed on a named branch. A zip-extracted copy needs `git init && git add -A && git commit`.
- On this Windows workstation, treat Bash as Git Bash/Cygwin for tests and phone tooling only. Never claim a ROM build was verified locally: `repo`, `mka`, and the AOSP env are Linux-only.
- `scripts/debug_device.sh` prefers the bundled `platform-tools/adb.exe`; `scripts/flash-checks.sh` and `doha.sh flash` use `adb` from PATH. Add `platform-tools` to PATH for those on Windows.
- Colab wrapper: `TARGET`, `REPO_URL`, `REPO_BRANCH`, `VARIANT`, `DEBLOAT`, `DOLBY`, `JOBS`, `GDRIVE`, `FORCE`, `SNAPSHOT_ONLY`, `INCLUDE_OUT`. It requires `/content/drive` mounted and at least ~190 GB free unless `FORCE=1`. No GPU helps.

## Testing & QA

Two hand-rolled harnesses, no framework. `doha.sh selftest` (menu 7) runs both:

```bash
bash scripts/selftest-paths.sh    # 15 assertions: build.sh path resolution on a mock tree
bash scripts/selftest-dryrun.sh   # 97 assertions across 10 sections
bash doha.sh selftest             # both, logged to logs/doha-*.log
```

- `selftest-paths.sh` builds `.selftest-mock/`, runs the real `build.sh` with `SKIP_SYNC=1`, and stops before `build/envsetup.sh`. It verifies patch discovery, the latent-fix call, variant rendering, the stamp, the governor rc install, and the `kernel-headers` sentinel.
- `selftest-dryrun.sh` covers: syntax of 9 scripts, manifest XML validity, mirror tarball gzip integrity and pin consistency, a sandboxed `restore-mirrors` run (`remove-project`, `file://` remote, pinned SHA fetch, idempotency, failure mode), `build.sh` init/restore/sync ordering with a `repo` stub plus fallback branch, every `doha.sh` subcommand and the menu, batch-mode behavior, latent-fix idempotency, adb-less phone script failures, and the Colab guard.
- Current state on this checkout (2026-10-24): the path test passes 15/15 and discovers 17 patches. The dry-run battery reports 84 passed, 14 failed. Remaining failures are host/asset issues: 6 XML checks cannot run because `python3` is the Windows Store stub; 5 mirror checks need the 4 intentionally omitted tarballs; 1 sandbox `file://` string check trips on Cygwin path normalization; 2 adb-less assertions are defeated by the untracked `platform-tools/adb.exe`. Run on Linux with the full mirror set for 97/97.
- The battery performs no network I/O: its `doha.sh vendor` resume assertion is skipped unless all 27 tarballs are present. Without that guard, an incomplete checkout would really clone the missing repos.
- Not covered by any test: a real Android build, patch applicability/`git apply`, a full 27-repo mirror restore, unpatched-vs-patched output, and the Android 17 path. Only the adb-absent branches of phone scripts are exercised.
- On-device checks: `bash scripts/flash-checks.sh` runs 7 sections (touch, governor, SIM/MCFG, Dolby, USB OTG, sensors, sepolicy) and exits non-zero on failure. `bash scripts/debug_device.sh [outdir]` writes a timestamped dump (direct default: `device dumps/device_dump_*`; menu default: `$HOME/doha-dumps/dump-*`). Its env knobs include `LIGHT`, `ALL_SERVICES`, `REPRO_SIM1`, `GUIDED`, `GUIDED_ONLY`, `REDACT`, `BUGREPORT`, `HASH_VENDOR`, `TMO`, `ANALYZE`.
- No CI, no shellcheck, no linter. The only gate is the manual self-test run.
- Evidence discipline: cite a dump, a measurement, or a doc section. Status words are `FIXED`, `PARTIAL`, `DOCUMENTED`, `NO-OP`; phone confirmation is tagged `phone-verified <date>`. A log line alone does not prove a feature works.

## Known Issues & Traps

- Incomplete mirror set in this checkout: delivery copies intentionally omit the 4 largest `.tgz` files (all 27 `.fact` rows are present). Missing: `android_kernel_motorola_msm-4.14`, `android_vendor_motorola_amogus`, `platform_prebuilts_clang_host_linux-x86_clang-r383902`, `proprietary_vendor_qcom_common`. Run `bash doha.sh vendor` to fetch them (~3.3 GB, 10-15 min, resumable). The dry-run battery skips its vendor assertion until they exist, so tests stay offline.
- `doha.sh action_flash` calls `run_logged` without `log_init`, so `LOG` is empty and flash commands are not logged reliably.
- Android 17 manifest includes `snippets/crdroid.xml` and `snippets/lineage.xml`, but the repo ships `snippets_crdroid.xml` / `snippets_lineage.xml` and no `snippets/` directory. They must be installed under `.repo/manifests/snippets/` before `repo init -m crdroid-17/default.xml` can resolve them. The `github` remote's relative `fetch=".."` is also wrong when initializing from the local kit path. [INFERENCE from repo semantics]
- Doc drift: `build.sh` references `docs/TOUCH.md` (absent); `docs/ANALYSIS.md` predates the shipped SIM 1 fixes; `README.md` omits `MANIFEST_URL`, `MANIFEST_BRANCH`, `LATENT_FIXES`, and `STOP_AFTER_SYNC`. Trust the script and `docs/BUG-REGISTER.md` over stale prose.
- Local state not gitignored: `.doha.conf` (remembered paths/settings). `logs/` is covered by `*.log`.

## Change Checklist

- Editing `lineage-16/build.sh`? Run `bash scripts/selftest-paths.sh`; it exists specifically to catch silent path/patch-discovery breakage.
- Adding or editing a patch? Keep the filename equal to the project path, keep diff paths project-relative, and run the self-tests.
- Bumping a pin? Update `default.xml`, `mirrors/MIRRORS.tsv`, and `mirrors/repos/*` together, then commit `default.xml` before building.
- Editing `.gitignore`? Keep the build-dir ignore anchored (`/lineage/`); a bare `lineage/` also matches `device/lineage/` and hides `lineage-16/patches/device/lineage/sepolicy.patch`.
- Touching sepolicy or property labels? Preserve block independence and marker-based idempotency; update `docs/BUG-REGISTER.md` status.
- Shipping a build? Verify with `scripts/flash-checks.sh`, then record the result in `WORKLOG.md`. Never commit `variants/dolby/blobs/`, `device dumps/`, or generated mirror pools.
