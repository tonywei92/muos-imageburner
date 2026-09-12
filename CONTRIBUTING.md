# Contributing

Thanks for your interest in improving muOS Image Burner!

## Ways to help
- Report bugs (device model, muOS version, what you did, and what happened).
- Suggest features or new filesystem support.
- Submit fixes and improvements via pull request.

## Development setup
See [DEVELOPMENT.md](DEVELOPMENT.md) for the architecture, the headless test mode,
and the over-SSH deploy workflow. See [BUILD.md](BUILD.md) for producing the LÖVE
runtime and the static filesystem tools.

## Pull requests
1. Fork the repository and create a topic branch:
   `git checkout -b feature/my-change`.
2. Keep changes focused; one logical change per pull request.
3. Make sure the headless self-test passes:
   ```sh
   LD_LIBRARY_PATH="$PWD/libs" IB_SELFTEST=1 ./love imageburner
   ```
   and, for formatter changes, the loop-device test in DEVELOPMENT.md.
4. Do **not** commit build outputs (the `build/` binaries, `.love` files, logs).
5. Update the docs when you change behaviour, options, or the on-disk layout.
6. Open the pull request with a clear description and, when possible, what device
   and muOS version you tested on.

## Commit messages
Use short, imperative subject lines, e.g.:

```
formatter: add GPT partition table option
ui: size footer key badges to their text
burner: reject images larger than the target card
```

## Code style
- Lua targets LÖVE 11.5 (LuaJIT 5.1): no `goto`, no `//`, keep it 5.1-compatible.
- On-device shell must be POSIX `sh` (BusyBox).
- Do not hardcode mount points or block device names; use the helpers in
  `burner.lua`.
- Never add destructive actions without a confirmation screen.
- Avoid new dependencies unless they are strictly necessary and ship cleanly on
  muOS.

## Reporting security / data-loss issues
If you find a path that could write to the live system card or otherwise cause
data loss, please open an issue marked as such and describe the steps to
reproduce. Do not include real user data.

## License
By contributing you agree that your contributions are licensed under the MIT
License (see [LICENSE.md](LICENSE.md)).
