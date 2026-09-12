# AGENTS.md

muOS Image Burner: a LÖVE 11.5 (LuaJIT, Lua 5.1) full-screen app that writes disk
images to an SD card and formats cards, for **muOS on Anbernic H700** devices
(tested on RG34XXSP, aarch64). There is no compiler, package manager, linter, or
test runner — the app is plain Lua plus static helper binaries.

## Layout
- `imageburner/main.lua` — all UI: one `state` string drives every screen; drawing helpers live at the bottom.
- `imageburner/burner.lua` — device/image discovery and the chunked, cancellable copy engine.
- `imageburner/formatter.lua` — filesystem options; generates a `/bin/sh` script that does the real work and reports progress via a status file.
- `mux_launch.sh` / `mux_lang.ini` — muOS launcher + menu metadata.
- `build/` — cross-compile scripts for the static tools. Their outputs (`mke2fs`, `mkntfs`, `tune2fs`) and the LÖVE runtime (`love`, `libs/`) are **gitignored**; see `BUILD.md`.

## Hard rules (data-loss territory)
- Never hardcode `/mnt/mmc`, `/mnt/sdcard`, or `/dev/mmcblk*`. Enumerate with `burner.listDisks()` and always refuse the live system disk.
- Any destructive action needs an explicit confirmation screen and must unmount the target first (`burner.unmountDisk`).
- Partition device naming: if the disk path ends in a digit, append `p1` (`mmcblk0p1`, `loop0p1`); otherwise append `1` (`sda1`).
- On-device shell must stay POSIX `sh` (BusyBox); `mux_launch.sh` and the generated formatter script are `#!/bin/sh`.

## Testing (no local test runner; runs on the device)
Both self-tests need a LÖVE runtime, so they normally run on the device where the app is installed:
```sh
cd "/mnt/mmc/MUOS/application/Image Burner"
LD_LIBRARY_PATH="$PWD/libs" IB_SELFTEST=1 ./love imageburner         # discovery + copy engine + draw smoke test
LD_LIBRARY_PATH="$PWD/libs" IB_FMTTEST=1 IB_FMTDEV=/dev/loop0 IB_FMTLAYOUT=mbr IB_FMTMODE=quick ./love imageburner
```
- `IB_FMTTEST` runs the *generated* formatter script against a loop device — safe, never a real card. Test MBR/GPT/quick/full this way.
- The draw smoke test runs against a mocked `love.graphics`. **If you use a new `love.graphics.*` call, add it to the mock in `main.lua`** or the headless test fails.
- `main.lua` defines test entrypoints at the top of `love.load` (`IB_FMTTEST` then `IB_SELFTEST`); keep them working.

## Deploying / SSH quirks (Windows host)
- Deploy with `scp -O imageburner/*.lua root@<device>:"/mnt/mmc/MUOS/application/Image Burner/imageburner/"`, then reopen the app (files are read at launch). Device SSH: muOS default `root`/`root`.
- Windows OpenSSH **strips quotes** from complex one-liners. Don't pass rich commands to `ssh`; pipe a script on stdin (`... | ssh host "sh -s"`) or `scp` a script and run it.
- Git is **not installed on Windows**; run git from WSL Ubuntu. Repo path in WSL: `/mnt/c/Users/Tony Song/muos-imageburner`. A passphrase-free key is configured at `~/.ssh/id_ed25519_muos` for `git@github.com`.

## Toolchain facts
- Formatter tools resolve at runtime via `formatter.toolsDir()` = `love.filesystem.getSource() .. "/tools"` (i.e. on device: `imageburner/tools/`).
- Built-in tools: `/sbin/mkfs.fat` (FAT), `/usr/sbin/mkfs.exfat` (exFAT). Bundled static tools: `tools/mke2fs` (EXT2/EXT3), `tools/mkntfs` (NTFS). BusyBox `mke2fs` can only make ext2 — do not rely on it for EXT3.
- Tools are built with the musl cross-toolchain; see `BUILD.md`. The ntfs-3g build links dynamically and must be relinked static (`build/ntfs-relink.sh`).

## Style
- Match the existing look: use `header`, `footer`, `drawList`, `infoCard`, `warnBand`, `drawProgressScreen`; colors come from `COL`.
- Input is polled each frame with edge detection (D-pad + A/B + left/right), not key events — muOS's virtual gamepad makes events unreliable.
- Use short, imperative commit subjects (e.g. `formatter: add GPT partition table option`). See `CONTRIBUTING.md`.
