#!/usr/bin/env bash
#
# zmk-build.sh — build this repo's keyboards locally.
#
#   ./zmk-build.sh --list             show available keyboards
#   ./zmk-build.sh corne              build every Corne target
#   ./zmk-build.sh chary --clean      wipe build dirs first
#   ./zmk-build.sh all                build everything in build.yaml
#   ./zmk-build.sh --setup            toolchain + modules only, no build
#
# Targets are read from build.yaml, so this script never needs updating
# when the matrix changes.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$REPO/config"
OUT="${ZMK_OUT:-$REPO/firmware}"
BUILD="${ZMK_BUILD:-$REPO/build}"

# Python virtualenv for west + Zephyr's python deps. Using a venv avoids
# three separate footguns: distros that ship python3 without pip, PEP-668
# "externally-managed-environment" refusals, and --user installs landing
# outside PATH when running as root.
VENV="${ZMK_VENV:-$REPO/.venv}"

# Zephyr SDK: ZMK v0.3 / cormoran DYA fork is Zephyr 3.5 based -> SDK 0.16.x
SDK_VER="${ZEPHYR_SDK_VERSION:-0.16.8}"
SDK_HOME="${ZEPHYR_SDK_INSTALL_DIR:-$HOME/zephyr-sdk-$SDK_VER}"

# Friendly name -> shield prefix used in build.yaml
declare -A KB=(
  [corne]=eyeslash_corne
  [sofle]=eyelash_sofle
  [flake]=anywhy_flake
  [chary]=charybdis
  [reset]=settings_reset
)

c_r=$'\e[31m'; c_g=$'\e[32m'; c_y=$'\e[33m'; c_b=$'\e[36m'; c_0=$'\e[0m'
info() { echo "${c_b}==>${c_0} $*"; }
ok()   { echo "${c_g} ok${c_0} $*"; }
warn() { echo "${c_y}warn${c_0} $*" >&2; }
die()  { echo "${c_r}err${c_0} $*" >&2; exit 1; }

usage() {
  cat <<EOF
usage: ${0##*/} <keyboard|all> [options]
       ${0##*/} --list | --setup

keyboards:
$(for k in "${!KB[@]}"; do printf '  %-8s %s\n' "$k" "${KB[$k]}"; done | sort)
  all       every target in build.yaml

options:
  -c, --clean     remove build dirs for the selected targets first
  -u, --update    force 'west update' before building
  -p, --pristine  pass --pristine to west build
  -j N            parallel jobs (default: nproc)
  -o, --output D  firmware output dir (default: ./firmware)
  -l, --list      list targets and exit
  -s, --setup     set up toolchain + fetch modules, then exit
  -h, --help      this text

env overrides:
  ZEPHYR_SDK_VERSION   default $SDK_VER
  ZEPHYR_SDK_INSTALL_DIR
  ZMK_OUT, ZMK_BUILD
  ZMK_VENV             default \$REPO/.venv
EOF
}

# ---------------------------------------------------------------- targets
# Emits: <artifact>\t<board>\t<shields>\t<snippet>\t<cmake-args>
parse_targets() {
  python3 - "$REPO/build.yaml" <<'PY'
import re, sys
rows, cur = [], None
for raw in open(sys.argv[1]):
    line = raw.rstrip('\n')
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    # strip trailing inline comments ("shield: foo   # note")
    stripped = re.sub(r'\s+#.*$', '', line.strip())
    if not stripped:
        continue
    if stripped.startswith('- board:'):
        if cur: rows.append(cur)
        cur = {'board': stripped.split(':', 1)[1].strip()}
    elif cur is not None and ':' in stripped and stripped.startswith(
            ('shield:', 'snippet:', 'cmake-args:', 'artifact-name:')):
        k, v = stripped.split(':', 1)
        cur[k.strip()] = v.strip()
if cur: rows.append(cur)

for r in rows:
    sh = r.get('shield', '')
    if not sh:
        continue
    art = r.get('artifact-name') or f"{r['board']}-{sh.replace(' ', '_')}"
    print('\t'.join([art, r['board'], sh,
                     r.get('snippet', ''), r.get('cmake-args', '')]))
PY
}

# ---------------------------------------------------------------- toolchain
need_host_deps() {
  local miss=()
  for c in git cmake ninja python3 dtc gperf; do
    command -v "$c" >/dev/null 2>&1 || miss+=("$c")
  done
  # python venv module is needed to bootstrap west
  if ! python3 -c 'import venv' >/dev/null 2>&1; then
    miss+=("python3-venv")
  fi

  if ((${#miss[@]})); then
    warn "missing host tools: ${miss[*]}"
    cat >&2 <<EOF

  Debian/Ubuntu:
    sudo apt install -y git cmake ninja-build gperf ccache dfu-util \\
      device-tree-compiler wget python3-dev python3-pip python3-venv \\
      xz-utils file make gcc libsdl2-dev libmagic1

  macOS:
    brew install cmake ninja gperf python3 ccache qemu dtc libmagic

  Arch:
    sudo pacman -S git cmake ninja gperf ccache dtc python python-pip

EOF
    die "install the above, then re-run"
  fi
  ok "host tools present"
}

need_python_env() {
  # Already have west (system package, pipx, or an activated venv)? Use it.
  if command -v west >/dev/null 2>&1; then
    ok "west $(west --version 2>/dev/null | head -1) (already on PATH)"
    return
  fi

  # Reuse our venv if it exists.
  if [[ -x "$VENV/bin/west" ]]; then
    export PATH="$VENV/bin:$PATH"
    ok "west $(west --version 2>/dev/null | head -1) (venv)"
    return
  fi

  info "creating python venv at $VENV"
  if ! python3 -m venv "$VENV" 2>/dev/null; then
    warn "python3 -m venv failed — the venv module is missing"
    cat >&2 <<'EOF'

  Install it, then re-run:

    Debian/Ubuntu:  apt install -y python3-venv python3-pip
    Fedora/RHEL:    dnf install -y python3-pip
    Arch:           pacman -S --needed python-pip
    Alpine:         apk add python3 py3-pip

  Or, if you prefer not to use a venv, install west another way and
  re-run (the script will detect it on PATH):

    pipx install west
    apt install -y python3-west      # some distros package it

EOF
    die "python venv unavailable"
  fi

  export PATH="$VENV/bin:$PATH"

  info "installing west into the venv"
  "$VENV/bin/python" -m pip install --quiet --upgrade pip wheel \
    || warn "could not upgrade pip inside venv; continuing"
  "$VENV/bin/python" -m pip install --quiet west \
    || die "failed to install west into $VENV"

  ok "west $(west --version 2>/dev/null | head -1) (venv)"
}

# The DYA Studio modules (ble-management, settings-rpc,
# runtime-input-processor) generate protobuf code with nanopb at build
# time. nanopb's protoc wrapper imports pkg_resources, which recent
# setuptools removed -- so a fresh venv fails with
# "ModuleNotFoundError: No module named 'pkg_resources'".
need_nanopb_deps() {
  local py="${VENV}/bin/python"
  [[ -x "$py" ]] || py="$(command -v python3)"

  if ! "$py" -c 'import pkg_resources' >/dev/null 2>&1; then
    info "installing setuptools (<81, still ships pkg_resources) for nanopb"
    "$py" -m pip install --quiet "setuptools<81" \
      || warn "could not install setuptools; nanopb codegen may fail"
  fi

  if ! "$py" -c 'import google.protobuf' >/dev/null 2>&1; then
    info "installing protobuf + grpcio-tools for nanopb"
    "$py" -m pip install --quiet protobuf grpcio-tools \
      || warn "could not install protobuf; nanopb codegen may fail"
  fi

  "$py" -c 'import pkg_resources, google.protobuf' >/dev/null 2>&1 \
    && ok "nanopb python deps present" \
    || warn "nanopb python deps still incomplete — DYA modules may fail"
}

need_sdk() {
  # already exported / present?
  for d in "$SDK_HOME" /opt/zephyr-sdk-* "$HOME"/zephyr-sdk-*; do
    [[ -d "$d" && -f "$d/cmake/Kconfig" || -d "$d/arm-zephyr-eabi" ]] || continue
    export ZEPHYR_SDK_INSTALL_DIR="$d"
    ok "Zephyr SDK: $d"
    return
  done

  warn "Zephyr SDK $SDK_VER not found"
  read -rp "Download it now (~1GB) to $SDK_HOME? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || die "set ZEPHYR_SDK_INSTALL_DIR to an existing SDK"

  local os arch url tar
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x86_64 ;;
    arm64|aarch64) arch=aarch64 ;;
    *) die "unsupported arch: $(uname -m)" ;;
  esac

  tar="zephyr-sdk-${SDK_VER}_${os}-${arch}_minimal.tar.xz"
  url="https://github.com/zephyrproject-rtos/zephyr-sdk-ng/releases/download/v${SDK_VER}/${tar}"

  info "fetching $tar"
  mkdir -p "$(dirname "$SDK_HOME")"
  ( cd "$(dirname "$SDK_HOME")" \
    && wget -q --show-progress "$url" \
    && tar xf "$tar" \
    && rm -f "$tar" )
  "$SDK_HOME/setup.sh" -t arm-zephyr-eabi -c 2>/dev/null \
    || warn "SDK setup.sh reported an issue; continuing"
  export ZEPHYR_SDK_INSTALL_DIR="$SDK_HOME"
  ok "SDK installed at $SDK_HOME"
}

init_workspace() {
  [[ -f "$CONFIG/west.yml" ]] || die "no config/west.yml — run from the repo root"

  if [[ ! -d "$REPO/.west" ]]; then
    info "initialising west workspace (config/west.yml)"
    ( cd "$REPO" && west init -l config )
    FORCE_UPDATE=1
  fi

  # Re-run 'west update' whenever config/west.yml has changed since the
  # last one. Without this, editing the manifest (swapping a module, or
  # changing a revision) silently keeps building against the OLD checkout,
  # which surfaces much later as baffling devicetree/link errors.
  local stamp="$REPO/.west/.manifest-hash"
  local now="" prev=""
  now="$(sha256sum "$CONFIG/west.yml" 2>/dev/null | cut -d' ' -f1)"
  [[ -f "$stamp" ]] && prev="$(cat "$stamp")"

  if [[ ! -d "$REPO/zmk" ]]; then
    info "fetching ZMK + modules (first run — this takes a while)"
    FORCE_UPDATE=1
  elif [[ "$now" != "$prev" ]]; then
    info "config/west.yml changed since last update — refetching modules"
    FORCE_UPDATE=1
  fi

  if [[ "${FORCE_UPDATE:-0}" == 1 ]]; then
    ( cd "$REPO" && west update )
    ( cd "$REPO" && west zephyr-export >/dev/null 2>&1 || true )
    mkdir -p "$(dirname "$stamp")"
    printf '%s' "$now" > "$stamp"
  else
    ok "modules up to date with config/west.yml"
  fi

  local req="$REPO/zephyr/scripts/requirements-base.txt"
  if [[ -f "$req" ]]; then
    info "installing Zephyr python requirements"
    if [[ -x "$VENV/bin/python" ]]; then
      "$VENV/bin/python" -m pip install --quiet -r "$req" \
        || warn "could not install Zephyr python deps; build may fail"
    else
      python3 -m pip install --user --quiet -r "$req" 2>/dev/null \
        || python3 -m pip install --user --break-system-packages --quiet -r "$req" 2>/dev/null \
        || warn "could not install Zephyr python deps; build may fail"
    fi
  fi

  need_nanopb_deps

  info "modules in workspace:"
  ( cd "$REPO" && west list -f '   {name:34} {revision}' 2>/dev/null | tail -n +2 ) || true
}

# ---------------------------------------------------------------- build
build_one() {
  local art="$1" board="$2" shields="$3" snippet="$4" cargs="$5"
  local dir="$BUILD/$art"

  info "building ${c_y}${art}${c_0}  (board=$board shield=\"$shields\")"

  local -a cmd=(west build -s "$REPO/zmk/app" -d "$dir" -b "$board")
  [[ -n "$snippet" ]] && cmd+=(-S "$snippet")
  [[ "${PRISTINE:-0}" == 1 ]] && cmd+=(--pristine)
  cmd+=(-- "-DSHIELD=$shields" "-DZMK_CONFIG=$CONFIG")
  # shellcheck disable=SC2206
  [[ -n "$cargs" ]] && cmd+=($cargs)

  if ! ( cd "$REPO" && "${cmd[@]}" ); then
    echo "${c_r}FAILED${c_0} $art" >&2
    return 1
  fi

  local uf2="$dir/zephyr/zmk.uf2"
  if [[ -f "$uf2" ]]; then
    mkdir -p "$OUT"
    cp "$uf2" "$OUT/$art.uf2"
    ok "$OUT/$art.uf2"
  else
    warn "$art built but no zmk.uf2 at $uf2"
    return 1
  fi
}

# ---------------------------------------------------------------- main
SELECT=""; CLEAN=0; FORCE_UPDATE=0; PRISTINE=0; JOBS=""; SETUP_ONLY=0; LIST=0
while (($#)); do
  case "$1" in
    -c|--clean)   CLEAN=1 ;;
    -u|--update)  FORCE_UPDATE=1 ;;
    -p|--pristine) PRISTINE=1 ;;
    -j)           JOBS="$2"; shift ;;
    -o|--output)  OUT="$2"; shift ;;
    -l|--list)    LIST=1 ;;
    -s|--setup)   SETUP_ONLY=1 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           die "unknown option: $1" ;;
    *)            SELECT="$1" ;;
  esac
  shift
done
export MAKEFLAGS="-j${JOBS:-$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4) )}"

if ((LIST)); then
  printf '%-42s %-14s %s\n' TARGET BOARD SHIELDS
  printf '%-42s %-14s %s\n' "------" "-----" "-------"
  while IFS=$'\t' read -r art board shields _ _; do
    printf '%-42s %-14s %s\n' "$art" "$board" "$shields"
  done < <(parse_targets)
  echo
  echo "keyboards: ${!KB[*]} all"
  exit 0
fi

# Validate the selection first — no point downloading a 1GB SDK to then
# reject a typo'd keyboard name.
if ((!SETUP_ONLY)); then
  [[ -n "$SELECT" ]] || { usage; exit 1; }
  if [[ "$SELECT" == all ]]; then
    PREFIX=""
  else
    [[ -v KB[$SELECT] ]] \
      || die "unknown keyboard '$SELECT' — try one of: ${!KB[*]} all"
    PREFIX="${KB[$SELECT]}"
  fi
fi

need_host_deps
need_python_env
need_sdk
init_workspace
((SETUP_ONLY)) && { ok "setup complete"; exit 0; }

mapfile -t TARGETS < <(parse_targets | awk -F'\t' -v p="$PREFIX" '$3 ~ "^"p')
((${#TARGETS[@]})) || die "no targets match '$SELECT'"

if ((CLEAN)); then
  for t in "${TARGETS[@]}"; do
    a="${t%%$'\t'*}"
    [[ -d "$BUILD/$a" ]] && { info "removing $BUILD/$a"; rm -rf "$BUILD/$a"; }
  done
fi

echo
info "${#TARGETS[@]} target(s) for '${SELECT}'"
fail=0
for t in "${TARGETS[@]}"; do
  IFS=$'\t' read -r art board shields snippet cargs <<<"$t"
  build_one "$art" "$board" "$shields" "$snippet" "$cargs" || fail=$((fail+1))
  echo
done

if ((fail)); then
  die "$fail of ${#TARGETS[@]} target(s) failed"
fi
ok "all ${#TARGETS[@]} target(s) built -> $OUT"
ls -1 "$OUT" | sed 's/^/     /'
