# Development

## Architecture

```
imageburner/
├── main.lua       UI: state machine, input handling, all screens, drawing helpers
├── burner.lua     Device/image discovery + the chunked copy engine (burn)
├── formatter.lua  Filesystem options + the background format runner
└── conf.lua       LÖVE window/module config (also enables the headless test mode)
```

### `burner.lua`
- Reads `/proc/partitions` and `/proc/mounts` to enumerate whole-disk block
  devices, detect the live/system disk, and detect mount state.
- `newBurn(src, dst)` opens the source (directly, or through `gzip -dc` /
  `xz -dc`) and the destination block device. `Burn:step()` copies one chunk at a
  time so the UI stays responsive and cancellable; the caller drives it from
  `love.update`.

### `formatter.lua`
- Declares the supported filesystems (`formatter.kinds`) with their MBR type byte
  and GPT type GUID, and per-filesystem cluster/block size choices
  (`formatter.clusterOptions`).
- `formatter.start(opts)` generates a small `/bin/sh` script that optionally
  zero-fills the card, optionally writes a partition table with `sfdisk`, then
  runs the right `mkfs` command. The script writes progress to a status file.
- `formatter.status()` parses that status file; `formatter.cancel()` kills the
  job via its pid file.

### `main.lua`
- A single `state` string drives the screens: `home`, `imgmenu`, `browser`,
  `disks`, `confirm`, `burning`, `formatopts`, `formatconfirm`, `formatting`,
  `result`.
- Input is polled every frame with edge detection (`A`/`B`, D-pad, left/right),
  which is more reliable than key events across muOS's virtual gamepad.

## Local checks (headless)

The app has a built-in, headless self-test that runs the discovery and copy
engines against regular files (never real devices) and smoke-tests every drawing
state with a mocked graphics API:

```sh
cd "/mnt/mmc/MUOS/application/Image Burner"
LD_LIBRARY_PATH="$PWD/libs" IB_SELFTEST=1 ./love imageburner
```

There is also an end-to-end formatter test that runs the *generated* script
against a loop device (safe, never a real card):

```sh
dd if=/dev/zero of=/tmp/fmtloop.img bs=1M count=300
losetup /dev/loop0 /tmp/fmtloop.img
cd "/mnt/mmc/MUOS/application/Image Burner"
LD_LIBRARY_PATH="$PWD/libs" IB_FMTTEST=1 IB_FMTDEV=/dev/loop0 \
  IB_FMTLAYOUT=mbr IB_FMTMODE=quick ./love imageburner
losetup -d /dev/loop0
```

`IB_FMTLAYOUT` accepts `mbr`, `gpt` or `none`; `IB_FMTMODE` accepts `quick` or
`full`.

## Deploying while developing

Over SSH (muOS enables SSH with user `root` / password `root`):

```sh
scp imageburner/*.lua root@<device>:"/mnt/mmc/MUOS/application/Image Burner/imageburner/"
```

The files are read at launch, so just reopen the app from the Applications menu.

## Conventions

- POSIX `sh` for anything that runs on-device; never hardcode `/mnt/mmc` or
  `/mnt/sdcard` inside the app — muOS bind-mounts storage under
  `/run/muos/storage`.
- Never hardcode block device names. Use `burner.listDisks()` and refuse the live
  system disk.
- Keep destructive operations behind an explicit confirmation screen.
- Match the existing visual style; use the helpers in `main.lua`
  (`header`, `footer`, `drawList`, `infoCard`, `warnBand`, `drawProgressScreen`).

## Safety notes

This app writes raw data to block devices. When testing:

- Always use a **spare** SD card for the target, or a loop device for automated
  tests.
- The live system card is locked in the UI, but double-check `listDisks()` output
  if you change the device-detection code.
- Prefer the headless and loop-device tests above for anything destructive.
