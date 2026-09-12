# muOS Image Burner

A handheld-friendly image writer and card formatter for **MustardOS (muOS)** on
Anbernic H700 devices (developed and tested on the **RG34XXSP**).

It is a [LÖVE 11.5](https://love2d.org/) application that opens full-screen and is
driven entirely with the D-pad and A/B buttons — no terminal required. It bundles
its own runtime and the filesystem tools it needs, so it works out of the box on a
stock muOS install.

```
Image Burner
├── Image Tool   Write an ISO/IMG to a removable SD card
└── Formatter    Create a fresh filesystem on an SD card
```

## Features

### Image Tool
- Write raw `.iso` / `.img` images to a removable SD card.
- Transparently decompresses `.img.gz`, `.iso.gz` (gzip) and `.img.xz`, `.iso.xz` (xz).
- Live progress bar with percentage, bytes written, write speed and ETA.
- Cancel at any time; the result screen reports success or a partial/cancelled write.
- Refuses to write to the card muOS is running from, and blocks images larger than the target.

### Formatter
- Filesystems: **FAT12, FAT16, FAT32, exFAT, EXT2, EXT3, NTFS**.
- Cluster / block size selection (per-filesystem list, or `Auto`).
- Partition table: **MBR** (default), **GPT**, or **None (superfloppy)**.
- Mode: **Quick** (mkfs only) or **Full** (zero-fills the whole card first).
- Live progress for the zero-fill phase, cancellable.
- Unmounts the target's partitions before touching them.

### Safety
- The live system card is detected and **locked** — it cannot be selected.
- A confirmation screen is always shown before any destructive action.
- Target partitions are unmounted before writing/formatting.
- Image-larger-than-card is rejected up front.

## Requirements
- An Anbernic H700 device running **muOS 2601.0 (Jacaranda)** or newer.
- An SD card inserted in the second slot for use as the target (SD2 → `/dev/mmcblk1`).

## Install

The app lives in the muOS applications folder on SD1:

```sh
/mnt/mmc/MUOS/application/Image Burner/
```

Typical layout on device:

```
Image Burner/
├── love                 # LÖVE 11.5 binary (aarch64)
├── libs/                # liblove-11.5.so, libluajit-5.1.so.2
├── imageburner/         # the Lua app
│   ├── main.lua
│   ├── burner.lua
│   ├── formatter.lua
│   ├── conf.lua
│   └── tools/           # static mke2fs, mkntfs, tune2fs (aarch64)
├── glyph/burner.png     # menu icon
├── mux_launch.sh
└── mux_lang.ini
```

Copy the contents of this repository into that folder (the `imageburner/`
directory is the LÖVE source), add the LÖVE runtime and the built tools, then
launch **Image Burner** from the muOS *Applications* menu. See
[BUILD.md](BUILD.md) for how to produce the runtime and the static tools, and
[DEVELOPMENT.md](DEVELOPMENT.md) for the deploy workflow used during development.

## Usage

From the muOS main menu open **Applications → Image Burner**.

**Controls**

| Action | Button |
| --- | --- |
| Move selection | D-pad / arrow keys |
| Select / open | A / Enter |
| Change value | Left / Right |
| Back | B / Esc |

**Burn an image:** Image Tool → *Image* (browse and pick a file) → *Destination*
(pick the card) → *Start Burn* → confirm.

**Format a card:** Formatter → *Card* (pick the card) → choose *Filesystem*,
*Cluster/block*, *Partition table* and *Mode* → *Start Format* → confirm.

## License

Project code is released under the MIT License — see [LICENSE.md](LICENSE.md).
Bundled third-party components keep their own licenses; details are listed there.
