#!/bin/bash
# Build the prebuilt machine-learning runtime. Devices on the default python share DEST (installed at
# FINAL): a uv-managed python and a venv with everything they have in common, plus their remaining
# packages staged as a filesystem root under BACKENDS/<device>. A device on another python gets its
# own complete python and venv in FINAL/<device> staged there instead. Each device stages FINAL/bin/start
# from START, with @VENV@ replaced by the venv it runs on.
#
# Usage: build-ml-venvs.sh SRC DEST FINAL BACKENDS START DEFAULT_PYTHON DEVICE[:PYTHON]...
#   SRC: upstream machine-learning dir (pyproject.toml, uv.lock, immich_ml)
# Env:   UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR (build-only locations), JOBS (compileall workers)
set -eu
SRC=$(realpath "$1"); DEST=$(realpath -m "$2"); FINAL=$3; BACKENDS=$(realpath -m "$4"); START=$(realpath "$5"); DEFAULT=$6; shift 6

export UV_FROZEN=1 UV_NO_DEV=1 UV_NO_EDITABLE=1 UV_NO_PROGRESS=1 UV_REQUIRE_HASHES=1 UV_LINK_MODE=copy
export UV_PYTHON_DOWNLOADS=manual
shopt -s dotglob nullglob

declare -A PYVER
shared=(); own=()
for arg in "$@"; do
  d=${arg%%:*}; v=${arg#*:}; [ "$v" = "$arg" ] && v=$DEFAULT
  PYVER[$d]=$v
  if [ "$v" = "$DEFAULT" ]; then shared+=("$d"); else own+=("$d"); fi
done
WORK=$BACKENDS/.work
rm -rf "$DEST" "$BACKENDS"; mkdir -p "$DEST" "$WORK"

# install_python VERSION TARGET: a trimmed copy of the uv-managed python
install_python() {
  local v=$1 t=$2
  uv python install --no-bin "$v"
  cp -a "$(dirname "$(dirname "$(readlink -f "$(uv python find --managed-python "$v")")")")" "$t"
  # parts of the distribution nothing at runtime uses
  rm -rf "$t/include" "$t/share" "$t/lib/pkgconfig" "$t/lib/"{tcl,tk,itcl,thread}* "$t/lib/"lib{tcl,tk}* \
         "$t/lib/python$v/"{idlelib,tkinter,turtledemo,turtle.py,ensurepip,lib2to3,site-packages,config-*} \
         "$t/lib/python$v/lib-dynload/"_tkinter.*
  find "$t/bin" -mindepth 1 ! -name "python$v" ! -name python3 ! -name python -delete
}

# build_venv DEVICE PYTHON ROOT: the device's venv into WORK/DEVICE, relocated to run with ROOT/python
build_venv() {
  local d=$1 py=$2 root=$3 venv=$WORK/$1 v=${PYVER[$1]}
  (cd "$SRC" && UV_PROJECT_ENVIRONMENT=$venv uv sync --python "$py" --extra "$d" --no-install-project --no-compile-bytecode)
  sed -i "s#^home = .*#home = $root/python/bin#" "$venv/pyvenv.cfg"
  # console scripts carry the build path in their shebang and are not used
  find "$venv/bin" -mindepth 1 ! -name 'python*' -delete
  rm -rf "$venv/.gitignore" "$venv/.lock" "$venv/CACHEDIR.TAG" "$venv/share"
  ln -sfn "$root/python/bin/python$v" "$venv/bin/python"
  sed -i '\#^\.\./\.\./\.\./bin/#d' "$venv/lib/python$v/site-packages"/*.dist-info/RECORD
}

# start_script DEVICE VENV: the device's start script, running VENV
start_script() {
  install -d "$BACKENDS/$1$FINAL/bin"
  sed "s#@VENV@#$2#" "$START" > "$BACKENDS/$1$FINAL/bin/start"
  chmod 0755 "$BACKENDS/$1$FINAL/bin/start"
}

# unchecked-hash: the package clamps mtimes, which would invalidate timestamp-based bytecode, and the
# files are read-only at runtime
compile() { "$1" -m compileall -q -j "${JOBS:-1}" --invalidation-mode unchecked-hash -s "$2" -p "$3" "${4:-$2}"; }

if [ ${#shared[@]} -gt 0 ]; then
  install_python "$DEFAULT" "$DEST/python"
  for d in "${shared[@]}"; do build_venv "$d" "$DEST/python/bin/python$DEFAULT" "$FINAL"; done
  # what every device has identically stays in the shared venv, the rest moves to the device's backend
  SP=lib/python$DEFAULT/site-packages
  first=${shared[0]}
  common=()
  for path in "$WORK/$first/$SP"/*; do
    entry=${path##*/}
    for d in "${shared[@]:1}"; do
      diff -rq --no-dereference "$WORK/$first/$SP/$entry" "$WORK/$d/$SP/$entry" >/dev/null 2>&1 || continue 2
    done
    common+=("$entry")
  done
  is_common() { local e; for e in "${common[@]}"; do [ "$e" = "$1" ] && return 0; done; return 1; }
  for d in "${shared[@]}"; do
    backend=$BACKENDS/$d$FINAL/venv/$SP
    mkdir -p "$backend"
    for path in "$WORK/$d/$SP"/*; do
      is_common "${path##*/}" || mv "$path" "$backend/"
    done
    start_script "$d" "$FINAL/venv"
  done
  mv "$WORK/$first" "$DEST/venv"
fi

for d in "${own[@]}"; do
  root=$BACKENDS/$d$FINAL/$d
  mkdir -p "$root"
  install_python "${PYVER[$d]}" "$root/python"
  build_venv "$d" "$root/python/bin/python${PYVER[$d]}" "$FINAL/$d"
  mv "$WORK/$d" "$root/venv"
  start_script "$d" "$FINAL/$d/venv"
done
rm -rf "$WORK"

cp -a "$SRC/immich_ml" "$DEST/"

find "$DEST" "$BACKENDS" -name __pycache__ -prune -exec rm -rf {} +
if [ ${#shared[@]} -gt 0 ]; then
  compile "$DEST/python/bin/python$DEFAULT" "$DEST" "$FINAL"
  for d in "${shared[@]}"; do compile "$DEST/python/bin/python$DEFAULT" "$BACKENDS/$d" /; done
fi
for d in "${own[@]}"; do
  py=$BACKENDS/$d$FINAL/$d/python/bin/python${PYVER[$d]}
  compile "$py" "$BACKENDS/$d" /
  # immich_ml runs on every python in use
  compile "$py" "$DEST" "$FINAL" "$DEST/immich_ml"
done
