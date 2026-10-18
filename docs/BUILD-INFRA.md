# BUILD-INFRA — where and how to build the doha ROMs

*Answer to the "can I use GPU / Google Colab / Kaggle for building?" question,
recorded so every future build session has the same facts. Written 2026-10-17
after the 5 TB Google Drive + Colab question. Cloud specs DRIFT - re-check
quotas before committing to a plan; the conclusions below have been stable
for years.*

## TL;DR

1. **No GPU on earth compiles an Android ROM.** The AOSP build chain
   (Soong → ninja → clang, javac, kotlinc, lld, aapt2, img tools) has no GPU
   back-end anywhere. A Colab A100/T4 or Kaggle P100 sits 100% idle during
   `mka bacon`. Choosing a GPU runtime on Kaggle actually gives you FEWER
   CPU cores than a CPU-only session, so it makes the build *slower*.
2. What a build actually consumes: **CPU cores, RAM, fast local disk** —
   roughly 16+ cores, 32-64 GB RAM, 350+ GB NVMe, and ccache for re-builds.
3. Your **5 TB Google Drive is excellent as the archive** (ROM zips, source
   snapshots, ccache archives) and **useless as the live build disk**
   (network FUSE bridge: git/repo over it is glacial, `.repo` hardlinks and
   symlink semantics break, ~750 GB/day transfer caps).
4. Ranked plan for doha-roms: **Crave (proven for this device) → own PC →
   rented VPS → Colab Pro as last resort**. GDrive as the archive in every
   plan. Details in §5.

---

## 1. Why the GPU cannot help

Every stage of `mka bacon` is a branchy, serial-per-file CPU process
parallelized *by running many of them at once* (ninja `-jN`):

| Build stage | Tool | GPU back-end? |
|---|---|---|
| Build graph | Soong / kati → ninja | none exists |
| C/C++ compile | clang (hundreds of parallel jobs) | none exists |
| Link | lld | none |
| Java / Kotlin | javac / kotlinc | none |
| Resources / APEX / images | aapt2, soong_zip, avbtool, img | none |
| Packaging + signing | zip, apksigner | none |

Compilers are control-flow-heavy; GPUs are data-parallel machines. There is
no production GPU compiler for this toolchain and no flag to enable one.
There never has been in 15+ years of AOSP. Anything that promises
"GPU-accelerated compiling" for AOSP in 2026 is a research demo, not a
usable path.

Consequences:

* A **Colab GPU runtime** contributes exactly nothing. On Colab, GPU
  runtimes also burn **compute units (≈ 8-11 CU/h for A100) whether the GPU
  is idle or not** — you pay quota for a chip that does zero work.
* A **Kaggle GPU session** comes with ~2 vCPU vs ~4 vCPU on a CPU session
  and a 30 h/week GPU quota — selecting GPU makes your build *slower and
  quota-limited*.
* The only "more compute" paths that are real: more CPU cores, more RAM,
  faster disk, **ccache**, and (industrially) RBE remote execution — see §6.

## 2. What the build actually needs (Lineage 23 / Android 16, doha)

| Resource | Minimum | Comfortable | Why |
|---|---|---|---|
| CPU | 8 cores | 16-32 | ninja job slots; build time scales ~1/cores |
| RAM | 16 GB | 32-64 GB | lld + javac + Soong peaks; OOM risk below 16 |
| Disk | 250 GB | 350-500 GB NVMe | source 150-200 GB (shallow) + `out/` 100-150 GB |
| First full build | — | 3-6 h @ 16c/32 GB | 8-15 h @ 12 vCPU; 60 h+ @ 2 vCPU |
| Re-build after patch change | — | 30-90 min | **with 50 GB ccache** — the single biggest win |

`lineage-16/build.sh` already sets `CCACHE_SIZE` (default 50G) and
`USE_CCACHE=1`. Our workflow (patch → build → flash → dump) is dominated by
RE-builds, so whatever machine you pick, keep its ccache warm.

## 3. What each cloud option actually gives you

| Option | vCPU / RAM | Disk | Session cap | Verdict for full A16 build |
|---|---|---|---|---|
| Colab Free | ~2 / 12.7 GB | ~100 GB | ~12 h, idle kill ~90 min | ✗ impossible (disk, RAM, time) |
| Colab Pro CPU high-RAM | ≈6-12 / 25-51 GB | ~100-200 GB | 24 h | △ last resort, needs §4 workflow |
| Colab Pro A100 runtime | 12 / 83 GB | ~200 GB | 24 h | △ works, burns ~8-11 CU/h for an idle GPU |
| Kaggle CPU | 4 / 30 GB | ~73 GB | 9 h, 30 h/week | ✗ disk + cores too small |
| Kaggle GPU | 2 / 13-16 GB | ~73 GB | 9 h, 30 GPU-h/week | ✗ worst option (fewer cores than CPU!) |
| GitHub Actions runner | 4 / 16 GB | 14 GB | 6 h/job | ✗ disk far too small; kernel-only OK |
| **Crave** (crave_aosp_builder) | free VM, quota-based | quota-based | quota-based | ✓ **proven for doha** (your crDroid 13 came from here) |
| Rented VPS/dedicated (Hetzner/Contabo class) | 16-32 / 64 GB | 2×1 TB NVMe | none | ✓ $10-30 per full A16+A17 cycle, then cancel |
| Own PC | — | — | — | ✓ best for the iterate-flash-dump loop |

## 4. Colab Pro workflow (if you must)

Only worth it for kernel-only work or a one-off single-target build, but
since you have Colab + 5 TB GDrive, here is the correct pattern
(`cloud/colab_doha.sh` automates it):

1. Runtime: **CPU → High-RAM** (NOT GPU). Locals in `/content` (ephemeral
   NVMe, 100-200 GB). Never build inside `drive.mount()` — see §5.
2. First session: shallow sync (`repo init --depth=1` + `repo sync -c
   --no-tags --no-clone-bundle -j8`), ≈ 150-200 GB, 1-2 h.
3. Build once (8-15 h on 12 vCPU — within the 24 h cap).
4. Snapshot to GDrive at every session end:
   `tar --use-compress-program=zstd -cf
   /content/drive/MyDrive/doha/snap/src-android16.tar.zstd -C /content src`
   (~60-90 GB compressed; restore next session in 15-40 min). Archive
   `ccache/` the same way (50 GB) — this is what makes session #2 build in
   1-2 h instead of 10.
5. Push ROM zips + images + sha256 + logs to
   `/content/drive/MyDrive/doha/releases/`.
6. Mind the meter: one full A16 build on an A100 runtime ≈ 100-200 CU ≈ a
   whole Pro month (100 CU @ $10). CPU high-RAM runtimes are far cheaper
   per hour — prefer them.

## 5. Your 5 TB Google Drive: right and wrong uses

**Wrong (breaks or crawls):** mounting GDrive and syncing/building inside
it. `drive.mount()` is a network FUSE bridge: `repo`/`git` do millions of
small-file ops (a `git status` takes minutes), `.repo` hardlink/symlink
semantics are not preserved, and personal accounts cap transfers at
~750 GB/day with rate limiting. A build would take days and corrupt.

**Right (this is what 5 TB is for):** the archive of record.

```
MyDrive/doha/
├── repo/            doha-roms snapshots (zip or git bundle)
├── snapshots/       src-android16.tar.zstd, src-android17.tar.zstd,
│                    ccache-android16.tar.zstd (rotating, keep 2 each)
├── releases/        every ROM zip + boot/dtbo/vbmeta + .sha256sum + logs
└── dumps/           the 3-ROM evidence dumps (already collected)
```

That is ≈ 250-300 GB even with both source trees + ccaches + years of
releases — a tenth of your space. rclone (outside Colab) moves big files
faster than the in-notebook mount.

## 6. The only real ways to add compute

* **More cores + RAM** (own machine or rented box): the honest answer.
* **ccache**: warm 50 GB cache turns our patch-iteration rebuilds into
  30-90 min jobs. Already wired into `build.sh`.
* **distcc / icecream**: distribute C/C++ compiles across your own
  machines — viable for kernel-only builds, awkward for full AOSP (Soong
  does not drive distcc).
* **RBE** (remote build execution): the industrial solution; self-hosting
  for a one-device project is not worth the setup.
* **GPU**: nothing. For ML training, not compiling.

## 7. Recommended plan for doha-roms

1. **Full builds (Android 16 first, then crDroid 17): use Crave** — the
   same route your most-stable ROM (crDroid 13) took via
   `Aldair69/crave_aosp_builder`. Push this repo to GitHub, adapt the
   craving recipe to call `lineage-16/build.sh` (it is already
   idempotent/incremental, which is exactly what cloud quota wants), check
   the instance disk covers the shallow A16 tree. If quota is tight, split
   into sync-session and build-session (ccache or out/ persistence via
   their artifacts) — same checkpoint pattern as §4.
2. **Iteration machine**: whatever local PC you have (8+ cores, 32 GB,
   500 GB free) + warm ccache. If none: a ~$0.3-0.8/h VPS for the weeks we
   iterate, then cancel.
3. **Colab**: keep for kernel-only experiments and small jobs
   (`cloud/colab_doha.sh` supports TARGET=kernel). CPU runtime, GPU off.
4. **GDrive 5 TB**: the archive of record in every plan (§5 layout).
5. Kaggle: skip for ROMs; fine for dataset/ML side-quests.

When the first build is done: flash `lineage-amogus_doha-*` + the new
fixes, run `scripts/flash-checks.sh` (7 sections) and
`scripts/debug_device.sh`, and check the SIM 1 test matrix in
`docs/SIM1-CALLS.md` — those results decide the next patch round.
