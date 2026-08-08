# mbii-gpu — Movie Battles II in a podman container on the host NVIDIA GPU

Runs the 32-bit **Movie Battles II** client (`mbii.i386`, a mod of the
OpenJK-based Jedi Academy engine) in a rootless podman container, rendering via
the host's NVIDIA driver over X11 — **without installing any NVIDIA software in
the image**, so the image is freely redistributable.


**Warning**: This is absolutely not going to receive any regular amount of support. If you
hit an issue, consider pointing a highly capable model like Deepseek v4 at it.

```
                HOST (user-space)                         CONTAINER (linux/386)
  ┌─────────────────────────────────────┐    ┌───────────────────────────────────┐
  │ NVIDIA kernel module (host driver)  │    │  mbii.i386  (32-bit game)          │
  │   └─ /dev/nvidia* (passed --device) │───▶│    │                              │
  │                                      │    │    ▼                              │
  │ driver/usr/lib  (user-space 32-bit  │    │  libGL.so.1 (glvnd dispatch, in   │
  │  NVIDIA GL libs, staged by          │──▶ │  image) → dlopen libGLX_nvidia.so  │
  │  ./fetch-driver.sh)                 │ mount│    ▲                            │
  └─────────────────────────────────────┘    │  /usr/lib/nvidia  (bind-mounted)   │
                                             └───────────────────────────────────┘
```

---

## Why this exists

- **MBII ships a 32-bit (i386) Linux client** and only provides `*.so` modules for
  it. The container must therefore be a `linux/386` image.
- **The renderer is OpenJK's `rd-vanilla`** (GLX/X11). For it to see the GPU, the
  container needs NVIDIA's 32-bit *user-space* GL stack: `libGLX_nvidia`,
  `libnvidia-glcore`, `libEGL_nvidia`, the shader-compiler libs, etc.
- **No i386 distro packages NVIDIA user-space libs.** (AlmaLinux has no i386
  NVIDIA packages at all; Debian's `nvidia-driver-libs:i386` only exists for
  Debian-packaged driver versions.)
- **The kernel module stays on the host** — the container just passes the
  `/dev/nvidia*` and `/dev/dri/renderD*` devices through. But NVIDIA's
  user-space libs *must match the host driver version* (they talk to the kernel
  module via version-gated ABI), so we can't just install "any" libs.

As a result, the image ships only free components
(glvnd GL/GLX dispatch + a patched SDL2/SDL3, both MIT/zlib licensed), and the
NVIDIA libs are provided at **runtime** from a host directory that
`./fetch-driver.sh` populates from NVIDIA's **own download servers**.

---

## Directory layout

```
mbii-gpu/
├── Dockerfile            # linux/386 image; free components only (no NVIDIA files)
├── build.sh              # podman build --platform linux/386  (-t mbii-glx -t mbii-gpu)
├── run.sh                # run the game windowed (--rm); auto-detects X auth cookie
├── run-logs.sh           # like run.sh but keeps the container + tees logs├── fetch-driver.sh       # stage the 32-bit NVIDIA user-space libs into driver/
├── driver/usr/lib/       # ← NVIDIA libs live HERE (host), mounted at /usr/lib/nvidia
├── rootfs-overlay/usr/lib/      # free libs baked into the image: glvnd + patched SDL
├── rootfs-overlay/usr/share/glvnd/egl_vendor.d/10_nvidia.json
├── sound-null.wav        # source for the sound/null.wav fix
└── logs/                 # console copies from run-logs.sh (mbii-<timestamp>.log)
```

---

## Quick start

```sh
./fetch-driver.sh            # stage the host driver's 32-bit libs into driver/   (once)
./build.sh                   # build the image                                      (once)
./run.sh                     # play
# or, to keep logs for debugging:
./run-logs.sh +map mp/duel1
```

The image is `localhost/mbii-glx:latest` (also tagged `mbii-gpu`). The game
runs with `fs_game MBII`, `s_initsound 0`, and a 1920x1080 window by default.
Resolution/fullscreen/sound are one-line edits at the top of `run.sh`.

### Specifying the gamedata folder

Both `run.sh` and `run-logs.sh` take the **path to the gamedata folder** (the
directory containing `mbii.i386`, `base/` and `MBII/`) as their first argument:

```sh
./run.sh /path/to/gamedata
./run-logs.sh /path/to/gamedata +devmap mb2_cloudcity
```

The lookup order is: first CLI argument → `GAMEDATA` env var → the default
placeholder in the script (`/PATH_TO_YOUR/gamedata` in `run.sh`,
`/PATH_TO_DOWNLOADED_MBII/gamedata` in `run-logs.sh`). The path is checked to
exist before launching; set `GAMEDATA` and edit the placeholder to your own
install if you don't want to pass it every time.

`run-logs.sh` treats everything after the first argument (or the `MAP` env var)
as the game command line, e.g. `+devmap <map>`.

---

## Grabbing / selecting the host driver under `driver/`

The only NVIDIA thing this setup needs is the **32-bit user-space GL library
set** for the host's driver, staged into `driver/usr/lib/`. Everything else is
provided by the host (kernel module, `/dev/nvidia*` devices) or by the image
(glvnd dispatch, SDL).

### The rule: user-space version must equal host driver version

The user-space libs `dlopen` the kernel module and are **version-gated** — a
mismatch fails at runtime with a GLX/EGL version error. So:

1. **Find the host driver version:**
   ```sh
   nvidia-smi --query-gpu=driver_version --format=csv,noheader   # e.g. 610.57.04
   ```
2. **Stage matching 32-bit libs:** `./fetch-driver.sh` does this automatically —
   it reads `nvidia-smi`, downloads that exact version, and extracts only the
   user-space libs into `driver/usr/lib/`.

### What `fetch-driver.sh` does

1. Picks a version — `$1` > `$DRIVER_VERSION` > `nvidia-smi` detection.
2. Skips if that version is already staged (idempotent: it checks for
   `driver/usr/lib/libnvidia-glcore.so.<ver>`).
3. Finds the installer, in order:
   - `DRIVER_RUN=/path/to/NVIDIA-Linux-x86-<ver>.run` (explicit),
   - `./NVIDIA-Linux-x86-<ver>.run` (dropped next to the script),
   - otherwise tries NVIDIA's official mirrors:
     `https://{download,us.download,international.download}.nvidia.com/XFree86/Linux-x86/<ver>/NVIDIA-Linux-x86-<ver>.run`
4. Extracts with the installer's own `--extract-only`, copies the `lib*.so.*`
   files into `driver/usr/lib/`, and creates the soname symlinks glvnd needs
   (`libGLX_nvidia.so.0 → libGLX_nvidia.so.<ver>`, etc.).

The download comes straight from NVIDIA's download servers; the script never
redistributes the driver; it only stages what your host already runs.

### Manual path (when the exact version isn't published)

The mirror layout is official but not every version stays published (e.g. this
host's `610.57.04` 404s on all mirrors). In that case:

```sh
# 1. Grab the 32-bit installer for your driver version, e.g. from the
#    NVIDIA driver download page ("Linux 32-bit" flavor):
#    https://www.nvidia.com/Download/index.aspx
curl -fLO https://download.nvidia.com/XFree86/Linux-x86/<ver>/NVIDIA-Linux-x86-<ver>.run
# 2. Point the script at it:
DRIVER_RUN=$PWD/NVIDIA-Linux-x86-<ver>.run ./fetch-driver.sh <ver>
```

If you already have a working extracted set (e.g. this project's seeded
`driver/usr/lib`, originally extracted from a matching `.run`), that is a valid
stage directory — it is exactly what `run.sh` mounts.

### Changing / reselecting a driver

- The mounted dir is just `driver/usr/lib`. To force a restage:
  ```sh
  rm -rf driver          # then re-run ./fetch-driver.sh
  ```
- **No image rebuild is needed for driver changes** — only the host-side
  `driver/` directory changes; the image is untouched.

### Which files actually get used

Only the 32-bit user-space set. The important ones for this game's GLX/DRI3
path: `libGLX_nvidia.so.<ver>`, `libnvidia-glcore.so.<ver>`,
`libnvidia-glsi.so.<ver>`, `libnvidia-tls.so.<ver>`,
`libnvidia-ptxjitcompiler.so.<ver>`, `libnvidia-gpucomp.so.<ver>`, plus the EGL
companions (`libEGL_nvidia.so.0`, `libnvidia-eglcore`, `libnvidia-egl-xcb/xlib`)
and `libvdpau_nvidia` for good measure. `fetch-driver.sh` stages the whole
user-space set, so nothing is left out.

---

## Verification

```sh
./run-logs.sh +map mp/duel1
# then, in the latest logs/mbii-*.log:
grep -E "GL_RENDERER|GL_VERSION" logs/mbii-*.log
#   GL_RENDERER: NVIDIA GeForce RTX .../PCIe/SSE2
#   GL_VERSION:  4.6.0 NVIDIA <ver>
grep -ic "couldn't find image" logs/mbii-*.log   # expect 0
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `SDL_Init(SDL_INIT_VIDEO) FAILED (No available video device)` | X auth cookie missing. `run.sh` auto-detects it from the running X server's `-auth` flag; if that fails, pass `XAUTH=/path/to/cookie`. |
| GLX/EGL version mismatch at startup | `driver/` libs don't match the host driver. Re-run `./fetch-driver.sh` (or reselect), see above. |
| Missing textures/models | Check `gamedata/base/` exists with `assets0-3.pk3` (a symlink into another host dir does **not** work inside the container — it must be real files). |
| `ERROR: sound/null has length 0` | `sound/null.wav` must exist in `gamedata/MBII/sound/`. |
| `error: cannot determine driver version` | `nvidia-smi` missing; pass the version explicitly: `./fetch-driver.sh 610.57.04` |

Known cosmetic-only gaps (referenced by menus, present in no pk3):
`gfx/menus/blackMask`, `gfx/menus/classes/*`, `gfx/menus/alpha/Main_Background2_2`
(actual file is `gfx/menus/mb_background2_2.tga`).

---

## Distribution

```sh
podman save localhost/mbii-glx | gzip > mbii-glx.tar.gz   # ~100-200 MB
podman load < mbii-glx.tar.gz
```

The recipient then runs `./fetch-driver.sh` on their machine (which pulls the
version-matched 32-bit libs from NVIDIA for *their* host) before `./run.sh`.
No NVIDIA files are shipped in the tarball, so no NVIDIA redistribution terms
apply to it.
