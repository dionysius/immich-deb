#!/bin/sh
# Starts immich-machine-learning on the venv of this prebuilt backend; immich_ml spawns gunicorn with the
# python found in PATH.
PATH=@VENV@/bin:$PATH
export PATH
exec python -m immich_ml
