# License

## Project code

Copyright (c) 2026 Tony Wei (tonywei92)

The source code in this repository — the Lua application
(`imageburner/*.lua`), the launcher (`mux_launch.sh`), and the documentation — is
released under the **MIT License**:

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Third-party components

A normal installation of this app bundles third-party software on the device.
Those components are **not** covered by the MIT License above and remain under
their own licenses. They are not committed to this repository (see
[BUILD.md](BUILD.md)); build/obtain them from their upstream projects.

| Component | Used for | License |
| --- | --- | --- |
| [LÖVE](https://love2d.org/) 11.5 (`love`, `liblove`, `libluajit`) | Application runtime | zlib |
| [e2fsprogs](https://e2fsprogs.sourceforge.net/) 1.47.1 (`mke2fs`, `tune2fs`) | EXT2/EXT3 | GPL-2.0-or-later / LGPL-2.0 |
| [ntfs-3g / ntfsprogs](https://github.com/tuxera/ntfs-3g) 2022.10.3 (`mkntfs`) | NTFS | GPL-2.0-or-later |
| [dosfstools](https://github.com/dosfstools/dosfstools) (`mkfs.fat`) | FAT12/16/32 | GPL-3.0-or-later |
| [exfatprogs](https://github.com/exfatprogs/exfatprogs) (`mkfs.exfat`) | exFAT | GPL-2.0-or-later |
| [util-linux](https://github.com/util-linux/util-linux) (`sfdisk`, `partprobe`, `blockdev`) | Partition tables | GPL-2.0-or-later |

The device firmware itself, [MustardOS / muOS](https://muos.dev/), is a separate
project distributed under the GPL-3.0 and is not part of this repository.

When redistributing a built app folder, keep the upstream license texts for the
bundled tools and comply with their terms (in particular the GPL's requirement to
offer corresponding source for the GPL binaries you ship).
