#!/bin/sh
# Starts immich-machine-learning with uv, which syncs the python runtime and libraries for DEVICE on the
# first start and after upgrades. Each default can be overridden in /etc/default/immich-machine-learning,
# see https://docs.astral.sh/uv/reference/environment/
# Hardware acceleration mode (one of [armnn, cuda, cpu, rocm, openvino, rknn])
: "${DEVICE=cpu}"
# point uv paths to folders the service may write
: "${UV_CACHE_DIR=/var/cache/immich/uv/cache}"
: "${UV_PROJECT_ENVIRONMENT=/var/cache/immich/uv/venv}"
: "${UV_PYTHON_INSTALL_DIR=/var/cache/immich/uv/python}"
: "${UV_COMPILE_BYTECODE=true}"
: "${UV_FROZEN=true}"
: "${UV_NO_DEV=true}"
: "${UV_NO_EDITABLE=true}"
: "${UV_NO_PROGRESS=true}"
: "${UV_REQUIRE_HASHES=true}"
: "${UV_PYTHON=3.12}"
: "${UV_PYTHON_PREFERENCE=only-managed}"
# cache for rustup (watchfiles uses puccinialin/rustup)
: "${RUSTUP_HOME=/var/cache/immich/.cache/rustup}"
export UV_CACHE_DIR UV_PROJECT_ENVIRONMENT UV_PYTHON_INSTALL_DIR UV_COMPILE_BYTECODE UV_FROZEN UV_NO_DEV \
       UV_NO_EDITABLE UV_NO_PROGRESS UV_REQUIRE_HASHES UV_PYTHON UV_PYTHON_PREFERENCE RUSTUP_HOME
exec /usr/lib/immich/machine-learning/bin/uv run --extra "$DEVICE" -m immich_ml
