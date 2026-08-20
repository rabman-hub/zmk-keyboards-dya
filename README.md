# ZMK Keyboards (monorepo)

A single ZMK config repository covering four keyboards, all built in
**dongle** configuration: a keyless nice!nano acts as the split central
and both halves connect to it as BLE peripherals.

| Keyboard | Origin repo | Central dongle | Peripherals | Notes |
| --- | --- | --- | --- | --- |
| Anywhy Flake | `zmk-flake-dongle` (was `flake-zmk`) | `anywhy_flake_central_dongle` | `anywhy_flake_peripheral_left` / `_right` | 3 physical layouts (L/M/S), ZMK Studio |
| Charybdis (Chary Mini) | `zmk-chary-dongle` (was `Chary-Mini-zmk`) | `charybdis_central_dongle` | `charybdis_peripheral_left` / `_right` | PMW3610 trackball on the right half |
| Corne | `zmk-corne-dongle` | `eyeslash_corne_central_dongle` | `eyeslash_corne_peripheral_left` / `_right` | nice!view on both halves |
| Sofle | `zmk-sofle-dongle` | `eyelash_sofle_central_dongle` | `eyelash_sofle_peripheral_left` / `_right` | nice!view on both halves, encoder |

Flake and Charybdis **gained dongle support in this merge** — they were
previously conventional splits. Their standalone (dongle-less) variants
are preserved and can be re-enabled by uncommenting the entries at the
bottom of `build.yaml`.

CCK-BALL was part of an earlier revision of this repo and has been
removed.

## Repository layout

```
.
├── build.yaml                       # GitHub Actions build matrix
├── .github/workflows/
│   ├── build.yml                    # tracks ZMK main
│   └── draw.yml                     # optional keymap-drawer renderer
├── zephyr/module.yml                # board_root: config
├── config/
│   ├── west.yml                     # unified manifest
│   ├── <keyboard>.conf              # user-level overrides
│   ├── <keyboard>.keymap            # user keymap
│   └── boards/shields/
│       ├── anywhy_flake/
│       ├── charybdis/
│       ├── eyelash_sofle/
│       └── eyeslash_corne/
├── keymap-drawer/
└── MIGRATION_NOTES.md               # every change, with rationale
```

### How user config maps to shields

ZMK resolves a shield's keymap and conf by its **shield directory name**,
not the full shield name. So `config/charybdis.keymap` and
`config/charybdis.conf` apply to *every* `charybdis_*` variant —
standalone, dongle, and both peripherals. The per-variant `.conf` files
inside `config/boards/shields/<name>/` are shield-level defaults; the
files directly under `config/` are your overrides on top of those.

## ZMK version

Built against **cormoran's DYA fork**: `cormoran/zmk @ v0.3-branch+dya`,
which is based on ZMK v0.3 (Zephyr 3.5). This is required for **DYA
Studio** support — see `MIGRATION_NOTES.md` §15.

Two places must stay in sync:

- `config/west.yml` → `remote: cormoran`, `revision: v0.3-branch+dya`
- `.github/workflows/build.yml` → `cormoran/zmk/...@v0.3-branch+dya`

To return to stock ZMK, set both back to `zmkfirmware` / `v0.3.0` and
remove the five cormoran modules and the DYA Kconfig blocks.

## DYA Studio

Plug the dongle in by USB, open <https://studio.dya.cormoran.works/> in
Chrome or Edge, and press the key bound to `&studio_unlock` (on the `Nav`
and `system` layers). Changes are saved to the dongle; flash
`settings_reset` to that device to undo them.


## Building

### Locally

```sh
./zmk-build.sh --list          # show every target
./zmk-build.sh --setup         # toolchain + modules, no build
./zmk-build.sh corne           # build one keyboard
./zmk-build.sh all             # everything
```

Keyboards: `corne`, `sofle`, `flake`, `chary`, `reset`, `all`.
Firmware lands in `firmware/`. The first run installs `west`, offers to
fetch the Zephyr SDK, and runs `west update` to pull cormoran's ZMK fork
and the DYA modules. Targets are read from `build.yaml`, so the script
and CI never drift apart.

### On GitHub Actions

Every push builds the whole matrix; UF2 artifacts appear on the run page.


## Flashing a dongle setup

1. Flash `settings_reset.uf2` to the dongle **and** both halves first.
2. Flash `<keyboard>_central_dongle_oled.uf2` to the dongle.
3. Flash `<keyboard>_peripheral_left.uf2` and `_peripheral_right.uf2` to
   the corresponding halves.
4. Power everything on. The dongle advertises to the host; the halves
   pair to the dongle.

If the halves don't connect, reset settings on all three again and
re-flash in that order.

## Credits

Original repos: [zmk-corne-dongle](https://github.com/TheSkyHeart/zmk-corne-dongle),
[zmk-sofle-dongle](https://github.com/TheSkyHeart/zmk-sofle-dongle),
[flake-zmk](https://github.com/TheSkyHeart/flake-zmk),
[Chary-Mini-zmk](https://github.com/TheSkyHeart/Chary-Mini-zmk).
