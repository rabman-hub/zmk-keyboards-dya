# Migration notes

Every change applied while merging four ZMK repos into this monorepo,
updating them for ZMK `main` (Zephyr 4.1), and adding dongle support to
Flake and Charybdis.

---

## 1. Scope changes in this revision

- **CCK-BALL removed.** No longer needed; its shield, keymap, conf, and
  build entries are gone.
- **Flake and Charybdis gained dongle support**, following the pattern
  already used by the Corne and Sofle configs. Their standalone
  (dongle-less) variants are preserved but commented out in `build.yaml`.
- **Naming.** You asked for `flake-zmk` → `zmk-flake-dongle` and
  `Chary-Mini-zmk` → `zmk-chary-dongle`. Since this is now a single
  monorepo there are no separate repos to rename, so the rename is
  reflected in two places that actually matter: the origin table in the
  README, and the dongle's advertised Bluetooth name
  (`ZMK_KEYBOARD_NAME` = `"Flake Dongle"` / `"Chary Dongle"`). The
  **shield IDs were deliberately left alone** (`anywhy_flake`,
  `charybdis`) — renaming them would break the keymap/conf lookup for no
  functional gain.

## 2. Structural merge

### One `west.yml`

Consolidates all module dependencies. Choices made:

- **`prospector-zmk-module` dropped.** Its `main` targets Zephyr 3.5 and
  sets `LV_DISP_DEF_REFR_PERIOD` against the pre-LVGL-9 Kconfig layout.
  Zephyr parses every module's Kconfig on every build, so this one broken
  module aborted **all** builds, not just prospector ones. See §8.
- **PMW3610 driver dropped as a west project** — replaced by Zephyr
  4.1's in-tree driver. See §11.
- `hammerbeam-slideshow` and `zmk-dongle-display` kept on `main`
  (englmaxi's `main` is Zephyr-4.1-ready).

### One shield tree

All shields live under `config/boards/shields/`, so a single
`zephyr/module.yml` with `board_root: config` covers them. Flake's shield
moved from a repo-root `boards/` into that tree.

### One build matrix, one workflow

`build.yaml` builds every keyboard; `.github/workflows/build.yml` tracks
`zmkfirmware/zmk@main`. Charybdis no longer needs the `petejohanson`
fork (see §3).

## 3. Charybdis: off the experimental fork

The original config built against
`petejohanson/zmk @ feat/pointers-move-scroll`. That branch was merged
upstream long ago; pointer support is now `CONFIG_ZMK_POINTING`.

- `west.yml` → `zmkfirmware/zmk @ main`.
- `charybdis.conf` → added `CONFIG_ZMK_POINTING=y` (without it the `&mkp`
  bindings in the keymap won't compile).
- `charybdis.keymap` → `dt-bindings/zmk/mouse.h` →
  `dt-bindings/zmk/pointing.h`.

The keymap only uses `&mkp`, so no behavior bindings changed.

## 4. Deprecation cleanups

| Old | New |
| --- | --- |
| `#include <dt-bindings/zmk/mouse.h>` | `#include <dt-bindings/zmk/pointing.h>` |
| `CONFIG_ZMK_MOUSE=y` | `CONFIG_ZMK_POINTING=y` |
| `ZMK_MOUSE_DEFAULT_MOVE_VAL` | `ZMK_POINTING_DEFAULT_MOVE_VAL` |
| `ZMK_MOUSE_DEFAULT_SCRL_VAL` | `ZMK_POINTING_DEFAULT_SCRL_VAL` |

Applied across user keymaps, shield-default keymaps, and `.conf` files.

## 5. Bugs inherited from the originals

- **Sofle `siblings:` was wrong.** `eyelash_sofle.zmk.yml` listed
  `eyelash_sofle_left` / `_right`, which don't exist. Corrected to the
  real variants and added `studio` to `features`.
- **Duplicate Sofle shield dropped.** The original repo had both
  `eyelash_sofle/` and `eyeslash_solfe/` (typo) with parallel contents.
  Only the former was referenced by the build; the latter was dead code.
- **Empty files dropped:** `charybdis.conf` and `charybdis_left.conf`
  in the shield dir were both zero bytes.

## 6. Pinned to ZMK v0.3.0 (Zephyr 3.5)

This repo is pinned to the **`v0.3.0`** release (2025-08-01), not `main`.

> **The git tag is `v0.3.0`, not `v0.3`.** ZMK's tags are `v0.1.0`,
> `v0.2.0`, `v0.2.1`, `v0.3.0`. Writing `v0.3` will fail at `west update`.

The pin lives in two places that must stay in sync:

- `config/west.yml` → `revision: v0.3.0`
- `.github/workflows/build.yml` → `@v0.3.0`

### Why pinned rather than `main`

`main` currently sits in the Zephyr 4.1 era, ahead of any tagged release
(`v0.4` will be the first release on that Zephyr). Tracking it means
taking breaking changes as they land — which is exactly what happened
during this migration: four consecutive build failures traced to
Zephyr-4.1-era churn in ZMK and its ecosystem modules. Pinning trades
newness for a base that does not move under you.

### What pinning implies

Four other settings hang off the ZMK version and are set for Zephyr 3.5:

| Setting | Zephyr 3.5 (here) | Zephyr 4.1 (`main`) |
| --- | --- | --- |
| Board ID | `nice_nano_v2` | `nice_nano` (HWMv2 revision collapse) |
| PMW3610 | out-of-tree `inorichi` driver | in-tree `CONFIG_INPUT_PMW3610` |
| `zmk-dongle-display` | `v0.3` branch | `main` |
| `CONFIG_WS2812_STRIP` | set explicitly | auto-selected, must be removed |

If you ever move back to `main`, all four flip together. See §11 for the
PMW3610 details, which are the most involved of the four.

### Side benefit: prospector works again

The `prospector-zmk-module` targets ZMK v0.3 / Zephyr 3.5, so the Kconfig
crash described in §8 does not occur on this pin. It is still not enabled
(no build entry uses `prospector_adapter`), but `config/west.yml` carries
a ready-to-uncomment snippet if you want it.


## 7. Battery reporting on the dongles

The `dongle_display` widget calls `zmk_battery_state_of_charge`,
`as_zmk_battery_state_changed`, `as_zmk_peripheral_battery_state_changed`
and `zmk_event_zmk_peripheral_battery_state_changed` unconditionally. The
first two require `CONFIG_ZMK_BATTERY_REPORTING=y`, which is *normally*
implied by `ZMK_BLE` — but not on a dongle, which has no battery node and
sets `CONFIG_BT_BAS=n`. Without it the link fails with
`undefined reference to ...`.

All four central-dongle confs therefore set:

```
CONFIG_ZMK_BATTERY_REPORTING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

## 8. Prospector module removed

Symptom: every build failed at Kconfig with

```
warning: LV_DISP_DEF_REFR_PERIOD ... defined without a type
error: Aborting due to Kconfig warnings
```

Cause: Zephyr parses all module Kconfigs regardless of which shield is
selected, and the prospector module's `main` branch is written for
Zephyr 3.5's LVGL Kconfig hierarchy. carrefinho's README states plainly
that `main` targets ZMK v0.3 and older, and that ZMK `main` users need
the `feat/new-status-screens` branch.

Since no build entry used `prospector_adapter`, the module was simply
removed from `west.yml`. To re-add it, use carrefinho's Zephyr-4.1
branch (snippet in `config/west.yml`).

## 9. Phantom shield + space-in-path

Symptom on the peripheral builds:

```
arm-zephyr-eabi-gcc: fatal error: cannot specify '-o' with '-c' ... with multiple files
```

with a build directory named `nice_nano_..._peripheral_right nice_view_custom/`
— note the literal space.

Two stacked problems:

1. **`nice_view_custom` is not a real shield.** It appeared in the
   original Corne and Sofle `build.yaml` files but is defined nowhere —
   not in ZMK, not in any declared module, not in the source repos. The
   standard chain is `nice_view_adapter nice_view`, which is what all
   four peripheral entries now use.
2. **Multi-shield strings break the build directory name.** When
   `shield:` contains a space, the orchestrator builds a directory path
   with that space in it and gcc treats the tail as a second input file.
   The `artifact-name:` field fixes this by giving the build an explicit
   space-free name.

**Rule of thumb: any `shield:` entry containing a space gets an
`artifact-name:`.** Every such entry in `build.yaml` now has one.

## 10. Dongle support for Flake and Charybdis (new)

Both keyboards were conventional splits (one half acting as central).
They now follow the same three-shield dongle pattern as Corne and Sofle.

### The pattern

| Shield | Role | kscan | Notes |
| --- | --- | --- | --- |
| `<name>_central_dongle` | central | `zmk,kscan-mock` (0×0) | no physical keys; owns the display |
| `<name>_peripheral_left` | peripheral | real matrix | |
| `<name>_peripheral_right` | peripheral | real matrix + `col-offset` | |

The central sets `ZMK_SPLIT_ROLE_CENTRAL default y` in
`Kconfig.defconfig` and `CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS=2` in
its conf. Both halves are plain peripherals.

### Flake specifics

The Flake ships **three** physical layouts (large / medium / small) with
a `position_map`. The right peripheral therefore applies `col-offset` to
**all three** transforms (`&large_transform`, `&medium_transform`,
`&small_transform`), matching what the standalone right half did. The
layouts live in `anywhy_flake.dtsi`, which the dongle also includes, so
ZMK Studio sees the complete keyboard from the dongle.

`ZMK_STUDIO` moved from the left half to the central dongle.

### Charybdis specifics — the trickiest part of this change

The PMW3610 trackball is physically on the **right** half. In the old
standalone config that half was the *central*, so the sensor was local
and a plain listener sufficed.

In a dongle setup the right half becomes a *peripheral*, so its input
must reach the dongle over BLE. ZMK does this with `zmk,input-split`,
and the wiring follows the pattern in ZMK's Pointing Devices docs:

**Shared** (`charybdis.dtsi`) — declared on every part. The split node
carries no `device` here, and the listener is **disabled**:

```dts
split_inputs {
    #address-cells = <1>;
    #size-cells = <0>;
    trackball_split: trackball_split@0 {
        compatible = "zmk,input-split";
        reg = <0>;
    };
};

trackball_listener: trackball_listener {
    compatible = "zmk,input-listener";
    device = <&trackball_split>;
    status = "disabled";
};
```

Putting the listener in the shared file — rather than only on the
central — is deliberate. The keymap is compiled for *both* central and
peripheral builds, so if a keymap references `&trackball_listener` to
attach input processors, a central-only definition would fail the
peripheral build with an undefined reference. Declaring it everywhere and
gating with `status` avoids that.

**Peripheral right** — fills in the local sensor, listener stays off:

```dts
&trackball_split { device = <&trackball>; };
```

**Central dongle** — enables the listener, nothing else:

```dts
&trackball_listener { status = "okay"; };
```

Enabling the listener on both sides would double-report movement, which
is why only the central switches it on.

**Standalone right** (non-dongle) re-points the listener straight at the
local sensor, bypassing the split:

```dts
&trackball_listener { device = <&trackball>; status = "okay"; };
```

The sensor hardware (SPI0 pinctrl + the `trackball` node, including
`scroll-layers` and `automouse-layer`) lives in a shared
`charybdis-trackball.dtsi`, included by both the standalone right half
and the dongle peripheral right.

> ⚠️ **This remains the part most likely to need adjustment.** Split
> pointing is a relatively recent ZMK feature. If the trackball doesn't
> move the cursor after flashing, re-check the `zmk,input-split` syntax
> against the docs for v0.3.0 specifically.


### Dongle OLED

Both new dongles define an SSD1306 on `&pro_micro_i2c` (128×32). That
alias maps to the standard Pro Micro SDA/SCL pins, so it works on a plain
nice!nano dongle. If your dongle wires the display differently, or you
use a 128×64 panel, adjust the node in `<name>_central_dongle.overlay`
and the `height`/`multiplex-ratio` values.

If you don't want a display at all, drop `dongle_display` from the
`shield:` string in `build.yaml` and remove `CONFIG_ZMK_DISPLAY=y` from
the central conf.

## 11. PMW3610 trackball (Charybdis)

Uses the **out-of-tree `inorichi/zmk-pmw3610-driver`**, matching the
original Chary-Mini config.

On Zephyr 3.5 this is unambiguously the right choice: Zephyr had no
in-tree PMW3610 driver until 3.6+, so there is nothing for the
`pixart,pmw3610` binding to collide with. (On Zephyr 4.1 the two *do*
collide — that was one of the build failures during the `main`
experiment. It is not a concern on this pin.)

Sensor tuning stays in Kconfig, as the driver expects:

```
CONFIG_PMW3610=y
CONFIG_PMW3610_CPI=2400
CONFIG_PMW3610_CPI_DIVIDOR=4
CONFIG_PMW3610_ORIENTATION_90=y
CONFIG_PMW3610_SNIPE_CPI=800
CONFIG_PMW3610_SNIPE_CPI_DIVIDOR=4
CONFIG_PMW3610_SCROLL_TICK=32
CONFIG_PMW3610_INVERT_X=y
CONFIG_PMW3610_POLLING_RATE_125_SW=y
CONFIG_PMW3610_SMART_ALGORITHM=y
```

These are byte-for-byte the values from your original
`charybdis_right.conf`, so trackball feel should be unchanged.

The driver's layer features (`scroll-layers = <1>`,
`automouse-layer = <5>`) also survive — they live on the `trackball` node
in `charybdis-trackball.dtsi`. Nothing needs reimplementing in the
keymap, unlike the in-tree-driver route.

The hardware definition is shared between the standalone right half and
the dongle peripheral right via `charybdis-trackball.dtsi`, so there is
one place to edit pins or tuning.


## 12. Summary of what to verify on first flash

1. **The `v0.3.0` tag resolves.** If `west update` errors on the
   revision, confirm the exact tag name on ZMK's releases page — it is
   `v0.3.0`, not `v0.3`.
2. **Charybdis trackball over BLE** (§10) — highest risk. The cursor
   should move when the dongle is connected and the right half paired.
   Orientation/CPI are unchanged from your original config, so if the
   cursor moves *correctly* the split plumbing is working.
3. **Dongle OLED pins** (§10) — assumes standard Pro Micro I²C and a
   128×32 panel. Adjust the node if yours differs.
4. **Flake layout switching** — all three transforms (L/M/S) should work
   from the dongle via ZMK Studio.
5. **Pairing order** — flash `settings_reset` to the dongle *and* both
   halves before flashing real firmware.

Note that the trackball's feel (CPI, orientation, snipe, scroll tick) and
its `scroll-layers` / `automouse-layer` behavior are carried over
verbatim from your original Chary-Mini config, so nothing there should
need re-tuning.

## 13. Unified keymap: Corne as the base for all four boards

The eyeslash Corne keymap is now the base layout on every keyboard. All
four share the same layer set with identical bindings on every key that
exists on both boards. (The `colemak` layer was removed afterwards —
see §14 — leaving seven: `qwerty`, `symbol`, `Num`, `Nav`, `Fun`,
`system`, `lower`.)

### Geometry

The eyeslash Corne is **48 keys**, not the usual 42. It adds a 6-key
centre cluster that plain Corne-style boards don't have:

```
row0:  L0..L5   [ centre ]   R0..R5          (6 + 1 + 6)
row1:  L0..L5   [ centre ]   R0..R5          (6 + 3 + 6)
row2:  L0..L5   [ centre ]   R0..R5          (6 + 2 + 6)
thumb:      3 left | 3 right                 (6)
```

That splits into **36 alphas + 6 centre + 6 thumbs**. The centre cluster
holds `&mmv MOVE_UP/DOWN/LEFT/RIGHT`, `&mkp LCLK`, and a `&kp SPACE`.

### How each board was mapped

| Board | Keys | Δ | Treatment |
| --- | --- | --- | --- |
| eyeslash Corne | 48 | base | unchanged |
| Charybdis | 42 | −6 | 36 alphas + 6 thumbs; centre cluster dropped |
| Anywhy Flake | 46 | −2 | 36 alphas + 6 thumbs; centre dropped, **4 extra thumbs kept** |
| eyelash Sofle | 64 | +16 | 36 alphas + 6 thumbs; **22 extra keys kept** |

**Charybdis (42)** is an exact fit: 48 − 6 centre keys = 42, matching its
`3×6 + 3` geometry key-for-key. Nothing else had to move. Losing the
`&mmv`/`&mkp` keys costs nothing here — the board has a physical
trackball, so mouse emulation was redundant anyway.

**Flake (46)** takes the 36 alphas, then has a 10-key thumb row against
the Corne's 6. The Corne's six land on the inner three per side; the
outer two per side keep their original bindings
(`&kp LEFT_GUI`, `&kp LEFT_ALT` … `&kp RIGHT_ALT`, `&kp RIGHT_GUI`).

**Sofle (64)** keeps 22 keys untouched: the whole number row (13), the
outermost key on each of the three alpha rows (3), and the outer three
thumbs per side (6). Everything else comes from the Corne.

### Two things that needed care

**Home-row-mod trigger positions.** The `hrm_left` / `hrm_right`
hold-taps use `hold-trigger-key-positions`, which are raw key indices.
Copying the Corne's numbers verbatim would have silently broken the
mods on every other board — the positions would point at the wrong keys.
They are recomputed per geometry:

| Board | `hrm_left` positions |
| --- | --- |
| Corne | `6 7 20 21 22 35 36 45 46 47 8 9 …` (48-key indices) |
| Charybdis | `6 7 8 9 10 11 18 19 20 21 22 23 …` |
| Flake | `6 7 8 9 10 11 18 19 20 21 22 23 … 38 39 40 41 42 43` |
| Sofle | `19 20 21 22 23 24 32 33 34 35 36 37 …` |

**Encoder bindings.** The Corne and Sofle have encoders; Flake and
Charybdis don't. The `sensor-bindings` lines and the `rgb_encoder` /
`scroll_encoder` behaviours are emitted only for the two boards that
have the hardware — leaving them in would fail the build on the other
two.

### Re-propagating after edits

`tools/propagate_keymap.py` regenerates the three derived keymaps from
`config/eyeslash_corne.keymap`:

```sh
python3 tools/propagate_keymap.py
```

Edit the Corne keymap, re-run, and the other three follow. It re-reads
the current derived keymaps first, so anything you've customised in a
"kept as-is" position survives; only Corne-derived positions are
overwritten.

> Layers are matched **by index**, not by name. The script emits exactly
> the Corne's layers on every board. Flake previously had nine
> layers (`lower_layer`, `raise_layer`, `adjust_layer`); those names are
> gone, replaced by the Corne's set.

## 14. Colemak layer removed

The `colemak` layer is gone from all four keymaps, leaving seven:

| # | Layer |
| --- | --- |
| 0 | `qwerty` |
| 1 | `symbol` |
| 2 | `Num` |
| 3 | `Nav` |
| 4 | `Fun` |
| 5 | `system` |
| 6 | `lower` |

### Layer references were renumbered

Deleting a layer shifts every layer above it down by one, so every
layer-referencing binding had to be rewritten. `colemak` sat at index 1,
so the shift was `2→1, 3→2, 4→3, 5→4, 6→5, 7→6`.

Behaviours renumbered: `&mo`, `&to`, `&tog`, `&sl`, `&lt`, and the custom
`&layer_tap` hold-tap.

**Not** renumbered: `&bt BT_SEL 0..4`. Those take a *profile* index, not
a layer index — blanket find-and-replace on bare numbers would have
silently rebound your Bluetooth profiles. The same applies to
`&rgb_ug` and `&mkp MB<n>` arguments.

### One dangling reference

The `lower` layer had a base-switcher row reading
`&to 0  &to 1  &to 0` — QWERTY / Colemak / QWERTY. With Colemak gone,
the middle key pointed at a layer that no longer existed, so it is now
`&trans` on all four boards.

### ⚠️ `lower` is now unreachable

Worth knowing: `lower` was only ever reachable *from* the Colemak layer,
via `&layer_tap 7 DELETE` and `&layer_tap 7 TAB` on its thumb row. Both
bindings were deleted along with Colemak, so **no key on any board now
activates `lower`**.

This is harmless — an unreferenced layer costs a little flash and
nothing else, and it is still reachable through ZMK Studio — but it is
almost certainly not what you want long-term. Three options:

1. **Delete `lower` too**, leaving six layers. It mostly contains
   `&trans` plus the base-switcher row that is now half-dead anyway.
2. **Bind a key to it** — e.g. change a thumb on `qwerty` to
   `&layer_tap 6 <KEY>`, mirroring how Colemak reached it.
3. **Leave it** and reach it via Studio when needed.

No option was applied automatically, since which key you would sacrifice
is a layout decision.

## 15. DYA Studio support

All four keyboards now build against **DYA Studio**, ported from the
creator's updated `zmk-corne-dongle` config.

DYA Studio (<https://studio.dya.cormoran.works/>) is cormoran's extended
alternative to ZMK Studio. On top of the stock keymap editor it adds BLE
profile management, per-OS default layers, power-management tuning,
battery/firmware inspection, key-chatter diagnostics, and — on boards
with a trackball — live pointer tuning.

### What it required

**1. A different ZMK core.** DYA Studio talks to a custom RPC subsystem
that only exists in cormoran's fork. `config/west.yml` now pulls:

```yaml
- name: zmk
  remote: cormoran            # https://github.com/cormoran
  revision: v0.3-branch+dya
```

That branch is based on ZMK v0.3 (Zephyr 3.5), so it is a drop-in for the
previous `zmkfirmware/zmk @ v0.3.0` pin — no Zephyr version change, and
none of the §6 dependent settings had to move.

**2. Five cormoran modules**, at the revisions used by the reference
config:

| Module | Revision |
| --- | --- |
| `zmk-module-ble-management` | `zmk-v0.3.0.0` |
| `zmk-module-runtime-input-processor` | `zmk-v0.3.0.0` |
| `zmk-module-settings-rpc` | `main` |
| `zmk-module-battery-history` | `main` |
| `zmk-behavior-runtime-sensor-rotate` | `main` |

**3. The GitHub workflow had to move too.** This is easy to miss —
pointing only `west.yml` at the fork leaves CI building against stock
ZMK, and the mismatch surfaces as confusing link errors:

```yaml
uses: cormoran/zmk/.github/workflows/build-user-config.yml@v0.3-branch+dya
```

**4. Three devicetree includes** on each central dongle overlay:

```c
#include <behaviors/battery_history_request.dtsi>
#include <input/processors.dtsi>
#include <input/processors/runtime-input-processor.dtsi>
```

**5. Kconfig** — a block on each central dongle (Studio, BLE management,
runtime input processor, settings RPC, settings persistence, split relay)
and a smaller one on each of the eight peripheral confs (battery history,
settings RPC, split relay, save debounce).

### Per-board differences

`CONFIG_ZMK_RUNTIME_SENSOR_ROTATE` is enabled **only on Corne and Sofle**.
Flake and Charybdis have no `zmk,keymap-sensors` node — no encoder — so
there is no sensor for the runtime-rotate behaviour to act on. It is left
commented out on those two with a note explaining why.

Everything else is identical across all four.

### `&studio_unlock` is required

DYA Studio cannot connect unless `&studio_unlock` is bound in the keymap.
All four keymaps already have it (on the `Nav` and `system` layers),
inherited from the Corne base in §13 — so nothing needed adding. Worth
knowing if you ever rework those layers: remove that binding and the app
stops connecting, with no obvious clue why.

### Live trackball tuning on Charybdis (enabled)

The Charybdis is the one board here with a physical trackball, so it is
the one that gains most from the runtime input processor: DYA Studio can
adjust sensitivity/scaling, axis inversion and the auto-mouse layer from
the browser, with no re-flash.

This is wired up in `charybdis_central_dongle.overlay`:

```dts
&trackball_listener {
    status = "okay";
    input-processors = <&mouse_runtime_input_processor>;
};
```

Three details that matter:

**The node label.** `<input/processors/runtime-input-processor.dtsi>`
exports two default instances — `mouse_runtime_input_processor` and
`scroll_runtime_input_processor` — not a single `runtime_input_processor`.
Guessing the label wrong fails the devicetree build, so it is worth
copying exactly.

**An extra include.** The module's README also requires
`#include <dt-bindings/zmk/input.h>`, which is now present alongside the
other DYA includes in the Charybdis central overlay.

**Where it goes.** Input processors run on the *listener*, and in a
dongle setup the listener lives on the **central**. So this belongs on
the dongle overlay, even though the sensor is physically attached to the
right-hand peripheral. Putting it on the peripheral would do nothing.

`CONFIG_ZMK_POINTING=y` and `CONFIG_ZMK_RUNTIME_INPUT_PROCESSOR=y` are
both already set on the Charybdis central conf, which is what the module
needs.

### Division of labour: driver vs DYA Studio

The driver's own layer features have been **removed** so DYA Studio is
the single source of truth for pointer behaviour. Configuring both would
make them fight: the driver switches modes off the active layer while the
processor applies its own, giving inconsistent scrolling and an
auto-mouse layer that sticks.

Removed from the `trackball` node in `charybdis-trackball.dtsi`:

```dts
scroll-layers = <1>;
automouse-layer = <5>;
```

Removed from both `charybdis_right.conf` and
`charybdis_peripheral_right.conf` (these only ever took effect
*alongside* the layer features above, so they were left inert):

```
CONFIG_PMW3610_SNIPE_CPI=800
CONFIG_PMW3610_SNIPE_CPI_DIVIDOR=4
CONFIG_PMW3610_SCROLL_TICK=32
```

All are preserved as comments in place, so restoring them is a matter of
uncommenting.

**What the driver still owns** — deliberately, because it is physical
setup rather than user preference:

| Setting | Why it stays |
| --- | --- |
| `CONFIG_PMW3610_CPI` / `_CPI_DIVIDOR` | Sensor hardware resolution. The runtime processor *scales* on top of this; it does not reprogram the sensor. |
| `CONFIG_PMW3610_ORIENTATION_90` | How the sensor is physically mounted. |
| `CONFIG_PMW3610_INVERT_X` | Ditto — corrects the raw stream before anything else sees it. |
| `CONFIG_PMW3610_POLLING_RATE_125_SW` | Sampling rate. |
| `CONFIG_PMW3610_SMART_ALGORITHM` | Sensor power management. |

The idea is that the driver delivers an already-correct raw event stream,
and DYA Studio applies preference on top. If you *also* invert an axis in
Studio it will compound with `INVERT_X` and cancel out — set orientation
in one place only.

**Both Charybdis variants** got the processor, not just the dongle. The
standalone right half (`charybdis_right.overlay`) uses the same
`&mouse_runtime_input_processor`, because it shares
`charybdis-trackball.dtsi` — without it that build would have lost the
driver features and gained nothing in return.

### Connecting

1. Flash the firmware, then plug the **dongle** into the PC by USB.
2. Open <https://studio.dya.cormoran.works/> in Chrome or Edge (WebUSB).
3. Press the key bound to `&studio_unlock`.

Changes made in DYA Studio are saved to the **central** (the dongle).
Flash `settings_reset` to that device to undo them.

### Reverting to stock ZMK

Restore `remote: zmkfirmware` / `revision: v0.3.0` in `config/west.yml`,
point the workflow back at
`zmkfirmware/zmk/.github/workflows/build-user-config.yml@v0.3.0`, drop
the five cormoran modules, and delete the `DYA Studio` blocks from the
shield `.conf` files plus the three includes from the central overlays.

> ⚠️ cormoran describes the fork as **experimental and optimised for DYA
> keyboards**. It is not stock ZMK. If you hit odd behaviour unrelated to
> Studio, reverting is the first diagnostic step.

## 16. Local build script

`zmk-build.sh` builds any of the four keyboards locally, sets up the
toolchain on first run, and fetches the west modules.

```sh
./zmk-build.sh --list          # show every target
./zmk-build.sh --setup         # toolchain + modules only
./zmk-build.sh corne           # build all 3 Corne targets
./zmk-build.sh chary --clean   # wipe build dirs first
./zmk-build.sh all             # all 13 targets
```

Keyboard names: `corne`, `sofle`, `flake`, `chary`, `reset`, `all`.
Output lands in `firmware/<artifact-name>.uf2`.

### Targets come from build.yaml

The script parses `build.yaml` rather than keeping its own list, so
editing the matrix (adding a target, uncommenting the standalone Flake
and Charybdis entries) is picked up automatically with no script change.
It carries across `board`, `shield`, `snippet` and `cmake-args`, so a
local build matches CI.

### What `--setup` does

1. Checks host tools (`git cmake ninja python3 dtc gperf`) and prints
   the right install command for Debian/Ubuntu, macOS or Arch if any are
   missing.
2. Bootstraps `west` in a **Python virtualenv** at `.venv/` (override
   with `ZMK_VENV`). If `west` is already on PATH — system package, pipx,
   an activated venv — that is used instead and no venv is created.

   The venv exists to dodge three separate problems at once: distros that
   ship `python3` with no `pip` at all, PEP-668
   `externally-managed-environment` refusals on newer Debian/Ubuntu/Arch,
   and `pip install --user` landing outside `PATH` when running as root.
   A venv ships its own `pip`, so the first of those stops mattering.

   `python3 -m venv` itself is checked in step 1, since on Debian/Ubuntu
   it lives in a separate `python3-venv` package.
3. Finds a Zephyr SDK, or offers to download one. Default is
   **0.16.8** — the 0.16.x series pairs with Zephyr 3.5, which is what
   ZMK v0.3 and cormoran's DYA fork are built on. Do **not** use 0.17.x
   here; that targets Zephyr 4.x.
4. Runs `west init -l config` + `west update`, which pulls cormoran's
   ZMK fork and all the DYA modules straight from `config/west.yml` —
   the same manifest CI uses.
5. Installs Zephyr's Python requirements.

Zephyr's Python requirements are installed into the same venv, so
nothing touches system Python.

Overridable via `ZEPHYR_SDK_VERSION`, `ZEPHYR_SDK_INSTALL_DIR`,
`ZMK_VENV`, `ZMK_OUT`, `ZMK_BUILD`.

### Workspace layout

`west init -l config` makes the repo root the workspace, so `zmk/`,
`zephyr/`, `modules/` and `.west/` appear alongside `config/`. That is
the standard ZMK user-config layout. A `.gitignore` covering all of them
plus `build/` and `firmware/` is included, so none of it gets committed.

### Note on inline comments in build.yaml

The parser strips trailing `# ...` comments from values. Without that,
the `charybdis_peripheral_right   # owns the PMW3610 trackball` entry
would have passed the comment text through to `-DSHIELD=` and failed.
Worth remembering if you extend the parser.

## 17. First local build: three failures fixed

Building `chary` locally surfaced three problems. All were real; the
third was architectural.

### a) `dt-bindings/zmk/input.h: No such file or directory`

I had added this include to the Charybdis overlays based on the
runtime-input-processor module's README. The header does not exist in
this ZMK/module combination. Removed from both
`charybdis_central_dongle.overlay` and `charybdis_right.overlay`. The
runtime input processor works without it.

### b) "Peripheral input splits need an `input` property set"

Failed on **`charybdis_peripheral_left`** — the half with no trackball.

`charybdis.dtsi` is shared by every part, and it declared
`trackball_split` unconditionally. ZMK's `input_split.c` asserts at build
time that any *enabled* peripheral input-split has a device attached, so
the left half — which has no sensor to attach — failed the assert.

The node is now `status = "disabled"` in the shared dtsi and switched on
explicitly by exactly the two parts that need it:

| Part | `trackball_split` |
| --- | --- |
| `charybdis.dtsi` (shared) | `disabled` |
| `charybdis_central_dongle` | `okay` (receives over BLE) |
| `charybdis_peripheral_right` | `okay` + `device = <&trackball>` |
| `charybdis_peripheral_left` | stays disabled |

This mirrors how the *listener* is already handled — declared shared and
disabled, enabled only on the central.

### c) `undefined reference to zmk_keymap_highest_layer_active`

Failed at link on `charybdis_peripheral_right`, and this one is not a
config mistake — **inorichi's PMW3610 driver cannot run on a split
peripheral.**

It implements scroll-mode, snipe-mode and auto-mouse-layer inside the
driver, which means calling `zmk_keymap_highest_layer_active()`. The
keymap is not linked into peripheral builds — the central owns it — so
the symbol is missing. It worked before only because the pre-dongle
Charybdis had the sensor on the *right half acting as central*.

Switched to **`badjeff/zmk-pmw3610-driver`**, which is explicitly
"compatible to be used on split peripheral shield" and moved those
features out of the driver into keymap-side input listeners. This is the
same switch made by Bastard Keyboards' official wireless Charybdis
firmware and by the eigatech Charybdis-dongle config, which notes:
*"Charybdis uses Inorichi's PMW3610 driver, while Charybdis Dongle
leverages multiple modules written by badjeff."*

It also happens to fit what we already wanted: with DYA Studio owning
scroll/snipe/auto-mouse via `&mouse_runtime_input_processor` (§15), a
driver that does not also implement them removes the conflict entirely.

**badjeff moved tuning from Kconfig into devicetree**, so
`charybdis-trackball.dtsi` now carries:

| Old Kconfig | New devicetree |
| --- | --- |
| `CONFIG_PMW3610_CPI=2400` | `cpi = <2400>;` |
| `CONFIG_PMW3610_ORIENTATION_90` | `swap-xy;` + `invert-x;` |
| `CONFIG_PMW3610_INVERT_X` | `invert-x;` |
| `CONFIG_PMW3610_CPI_DIVIDOR` | dropped |
| `CONFIG_PMW3610_SNIPE_CPI*` | dropped (keymap-side now) |
| `CONFIG_PMW3610_SCROLL_TICK` | dropped (keymap-side now) |

Only `CONFIG_PMW3610=y` remains in the `.conf` files.

> If the build reports **"no matching binding found"** for the trackball,
> switch `compatible` to `"pixart,pmw3610-alt"` — badjeff renamed the
> binding to avoid clashing with Zephyr's in-tree driver. That clash only
> exists on Zephyr 3.6+, and we are on 3.5, so the original name should
> apply; both are present in the dtsi, one commented.

> A 90° rotation is a swap *plus* one inversion. If the cursor moves
> along the wrong axis after flashing, move the inversion from
> `invert-x` to `invert-y`.

## 18. Second local build: two more fixes

### a) Dongle failed devicetree validation on `col-gpios`

```
devicetree error: 'col-gpios' is marked as required in
zmk,kscan-gpio-matrix.yaml, but does not appear in <Node /kscan>
```

`charybdis.dtsi` declared `kscan0` with `compatible =
"zmk,kscan-gpio-matrix"` and `row-gpios`, but left `col-gpios` to each
side's overlay. The central dongle has no matrix overlay — it uses
`mock_kscan` — so the node was incomplete and failed validation.

All four Charybdis variants wire the columns identically, so `col-gpios`
now lives in `charybdis.dtsi` alongside `row-gpios`. The node is valid
for every build including the dongle, and the per-side overlays may
still restate it harmlessly.

(For contrast, `eyeslash_corne.dtsi` avoids this a different way: its
kscan node declares no `compatible` at all, so no binding validation
runs against it.)

### b) `'cpi' ... not declared in properties` — stale module checkout

```
devicetree error: 'cpi' appears in /soc/spi@40003000/trackball@0 ...
but is not declared in 'properties:' in
zmk-pmw3610-driver/dts/bindings/pixart,pmw3610.yml
```

badjeff's driver **does** declare `cpi` — that is the whole point of §17.
The driver on disk was still **inorichi's**, because `zmk-build.sh` only
ran `west update` when the workspace was missing entirely. Switching the
manifest from `inorichi` to `badjeff` therefore changed nothing on disk,
and the build kept using the old checkout.

`zmk-build.sh` now hashes `config/west.yml` and stores it at
`.west/.manifest-hash`. If the manifest has changed since the last
update, it re-runs `west update` automatically:

```
==> config/west.yml changed since last update — refetching modules
```

`-u` / `--update` still forces it manually.

> This class of bug is worth remembering: a stale west checkout produces
> errors that point at devicetree or linking, never at the manifest, so
> it is easy to chase the wrong thing. If an error mentions a property or
> symbol that the module's docs clearly say exists, suspect the checkout
> before the config.

## 19. Third local build: nanopb deps + badjeff's required properties

### a) `ModuleNotFoundError: No module named 'pkg_resources'`

Failed on the central dongle, in all three DYA RPC modules
(`ble-management`, `settings-rpc`, `runtime-input-processor`).

Those modules generate protobuf code with **nanopb** at build time.
nanopb's `protoc` wrapper does `import pkg_resources`, which ships with
setuptools — and setuptools **removed it in v81**. Its own deprecation
notice says:

> *The pkg_resources package is slated for removal as early as
> 2025-11-30. Refrain from using this package or pin to Setuptools<81.*

A fresh venv on a current pip therefore gets a setuptools too new for
nanopb. `zmk-build.sh` now checks for `pkg_resources` and installs
`setuptools<81` if it is missing, plus `protobuf` and `grpcio-tools`
which nanopb also needs:

```
==> installing setuptools (<81, still ships pkg_resources) for nanopb
==> installing protobuf + grpcio-tools for nanopb
 ok nanopb python deps present
```

This runs after `west update`, since the modules must exist first.

Note this is **specific to the DYA build**. Stock ZMK has no protobuf
codegen, so this never came up before §15.

### b) `'evt-type' is marked as required`

Failed on `charybdis_peripheral_right`. badjeff's binding requires three
properties inorichi's never had:

```dts
evt-type     = <INPUT_EV_REL>;
x-input-code = <INPUT_REL_X>;
y-input-code = <INPUT_REL_Y>;
```

They exist because badjeff supports wiring a *second* sensor as a
dedicated scroll device on one shield, so each sensor declares what it
emits rather than the driver assuming. Added to
`charybdis-trackball.dtsi`, along with
`#include <zephyr/dt-bindings/input/input-event-codes.h>`.

### c) `compatible` confirmed

The error above was a *missing property* on a matched binding, not "no
matching binding found" — which proves `compatible = "pixart,pmw3610"` is
correct even though badjeff's binding file is named
`pixart,pmw3610-alt.yml`. Zephyr matches on the `compatible:` string
inside the YAML, not the filename. The `-alt` hedge comment has been
removed.

### d) Macro redefinition warnings silenced

All four keymaps redefined `ZMK_POINTING_DEFAULT_MOVE_VAL` /
`_SCRL_VAL`, which `dt-bindings/zmk/pointing.h` already defines —
harmless, but it produced warning noise on every build. Each keymap now
`#undef`s them first.

## 20. Fourth local build: physical layout + Kconfig cleanup

Setup phase was clean this round — nanopb deps installed, all nine
modules at the right revisions. Three remaining problems.

### a) ZMK Studio requires a physical layout

```
error: static assertion failed: "ISSUE FOUND: Keyboards require
additional configuration to allow for firmware with ZMK Studio enabled."
```

Charybdis was the **only** shield in this repo without a
`zmk,physical-layout` node — Corne, Sofle and Flake all had one
(`*-layouts.dtsi`). Studio needs it to draw the keyboard in the editor,
and the build asserts rather than silently producing unusable firmware.

Created `charybdis-layouts.dtsi`: 42 keys as `3x6 + 3 thumbs` per side.
The coordinates reuse the column stagger from this repo's Flake medium
layout — the same 3x6 shape, already known-good — with a 3-key rotated
thumb fan per side taken from the same source.

Key order **must** match `&default_transform`:

```
row0 RC(0,0..11)   row1 RC(1,0..11)   row2 RC(2,0..11)   row3 RC(3,3..8)
```

Wired in via `zmk,physical-layout = &charybdis_layout;` in the `chosen`
node.

> The layout is geometrically reasonable but not measured against real
> Charybdis hardware. It affects only how the board is *drawn* in
> Studio — key positions, sizes and rotations — never which key does
> what. If it looks off in the editor, adjust the x/y values; nothing
> functional depends on them.

### b) `attempt to assign the value 'y' to the undefined symbol PMW3610`

badjeff's driver defines no `CONFIG_PMW3610` symbol. inorichi's did;
badjeff's is selected from devicetree by the `pixart,pmw3610` compatible
instead, in the normal Zephyr style. The line is removed from both
`charybdis_right.conf` and `charybdis_peripheral_right.conf`.

This is the last remnant of the inorichi → badjeff switch in §17 — the
Kconfig surface differs as much as the devicetree one.

### c) `ZMK_BATTERY_HISTORY_INTERVAL_MINUTES` assigned with no parent

```
CONFIG_ZMK_BATTERY_HISTORY_INTERVAL_MINUTES was assigned the value '30'
but got the value ''. Check these unsatisfied dependencies:
ZMK_BATTERY_HISTORY (=n)
```

The DYA peripheral block (§15) sets `BATTERY_HISTORY=n` — matching the
reference config — but also set the interval, which only exists when
history is enabled. Zephyr treats an assignment to an unsatisfiable
symbol as an error, not a warning.

Commented out across **all eight** peripheral confs, not just Charybdis:
the same block was copied to every board, so the other three would have
hit it as soon as they were built. If you ever set
`CONFIG_ZMK_BATTERY_HISTORY=y`, uncomment the interval alongside it.

## 21. Fifth local build: missing layouts include

```
devicetree error: /charybdis_layout: undefined node label 'key_physical_attrs'
```

All three targets failed, because the layouts file added in §20 lives in
the shared `charybdis.dtsi` and so is compiled for every part.

`&key_physical_attrs` is defined by ZMK's `<physical_layouts.dtsi>`, and
my new `charybdis-layouts.dtsi` had no includes at all. Every other
layouts file in the repo opens with that line:

```c
#include <physical_layouts.dtsi>
```

Added. Verified present in all three layouts files
(`charybdis`, `eyelash_sofle`, `eyeslash_corne`); Flake includes it
directly in `anywhy_flake.dtsi`.

### Also aligned: the `chosen` node

Charybdis declared **both** `zmk,matrix_transform` and
`zmk,physical-layout`. Corne and Flake declare only the layout — with a
physical layout present the transform comes from the layout's own
`transform` property, so the older key is redundant and can shadow it.
Removed for consistency with the two shields that build.

### Checks run afterwards

To avoid another single-error round trip:

- **Label resolution** — every `&label` used anywhere in the Charybdis
  shield resolves either to a definition in the shield or to a known
  external (`gpio0`, `pro_micro`, `spi0`, `pro_micro_i2c`,
  `key_physical_attrs`, `mouse_runtime_input_processor`).
- **Brace balance** — all eight Charybdis `.dtsi`/`.overlay` files pair
  correctly.
- **Key count** — the layout defines exactly 42 keys, matching
  `&default_transform` (12+12+12+6).

## 22. Charybdis physical layout replaced with the upstream one

§20 said the Charybdis had no physical layout, and §20–21 built one from
scratch. That was wrong in an important way, and worth recording.

### What actually happened

The `charybdis.dtsi` **inside the originally-uploaded zip** genuinely had
no layout — zero `key_physical_attrs`, `zmk,matrix_transform` in `chosen`,
no `<physical_layouts.dtsi>` include. That zip was a Feb 2025 snapshot.

The upstream repo has since gained a proper layout. So nothing was lost
in the merge; the source material was simply out of date. The
hand-written layout in §20 was solving a problem that upstream had
already solved better.

### What replaced it

`charybdis.dtsi` is now the upstream version, which brings:

- `#include <physical_layouts.dtsi>`
- `zmk,physical-layout = &charybdis;` in `chosen` (and no
  `zmk,matrix_transform` — matching the conclusion reached independently
  in §21)
- a `charybdis: charybdis` layout node, display-name "matrix layout",
  with all 42 keys
- `kscan = <&kscan0>;` on the layout node — which the hand-written
  version lacked entirely

The coordinates are the board author's own: a flat grid with the halves
separated at x=1250, and a ±30° rotated 3-key thumb fan per side. The
§20 version borrowed Flake's column stagger, which was a guess at
Charybdis geometry. This is the real thing.

`charybdis-layouts.dtsi` (created in §20) has been deleted — upstream
keeps the layout inline.

### What was carried forward

Two additions this monorepo needs that upstream has no reason to include,
both re-applied on top:

1. **`col-gpios` on `kscan0`** (§18a) — upstream leaves these to the
   per-side overlays, which is fine for a two-part split but fails for a
   dongle, since the dongle has no matrix overlay.
2. **The split-pointing plumbing** (§17b, §21) — `split_inputs` with a
   disabled `trackball_split`, plus the disabled `trackball_listener`.
   Upstream is not a dongle config, so it has none of this.

### Lesson

When a merge source is a zip rather than a live clone, it is a snapshot
with a date. If something looks conspicuously missing from a
well-maintained upstream — like a physical layout on a board that
obviously supports Studio — check the current upstream before building a
replacement.

## 23. Sixth local build: 2 of 3 pass; the last is the driver Kconfig

The dongle and the left peripheral now build. Only
`charybdis_peripheral_right` failed:

```
ld.bfd: app/libapp.a(input_split.c.obj): undefined reference to
`__device_dts_ord_29'
```

### What that error actually means

`__device_dts_ord_NN` is the device struct Zephyr generates for a
devicetree node. Its absence means **no driver claimed the `trackball`
node**, so nothing was instantiated for `input_split.c` to point at.

The devicetree was fine — validation had already passed. The driver
simply was not compiled in.

### Cause: badjeff renamed everything

§20b removed `CONFIG_PMW3610=y` because Kconfig rejected it as undefined,
and I assumed the driver auto-enabled from devicetree. It does not.
badjeff's module carries a documented breaking change:

> *Compatible string changed to `pixart,pmw3610-alt`.
> All config prefix changed to `CONFIG_PMW3610_ALT_*`.*

So two things were wrong at once:

| | Was | Now |
| --- | --- | --- |
| Kconfig | *(nothing)* | `CONFIG_PMW3610_ALT=y` |
| `compatible` | `pixart,pmw3610` | `pixart,pmw3610-alt` |

### Why the old compatible looked correct

§19c concluded `pixart,pmw3610` was right, because the build produced a
*missing property* error (`evt-type`) rather than "no matching binding".
That reasoning was sound but the conclusion was wrong: the node did bind
to the YAML, so validation ran — but the **driver's `DT_DRV_COMPAT` is
the `-alt` name**, so `DT_INST_FOREACH_STATUS_OKAY` matched zero
instances and built no device.

Binding successfully and being claimed by a driver are two different
things. A node can pass devicetree validation and still have no driver,
and the failure only appears at link time.

### Also noted from badjeff's README

If the log later shows `Incorrect product id 0xFF (expecting 0x3E)!` on a
nice_nano_v2, the sensor needs more settling time after power-up:

```
CONFIG_PMW3610_ALT_INIT_POWER_UP_EXTRA_DELAY_MS=1000
```

Left commented in both right-side confs, since the board here *is* a
nice_nano_v2 and this is a known issue on it.

The `swap-xy` / `invert-x` / `invert-y` devicetree properties already in
`charybdis-trackball.dtsi` are the current form; the
`CONFIG_PMW3610_ALT_SWAP_XY` style equivalents are deprecated.
