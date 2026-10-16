#!/usr/bin/env python3
"""Emit a third-party license inventory of the python distributions installed in the given
site-packages directories."""
import sys
from importlib import metadata


def license_of(meta):
    expr = meta.get("License-Expression")
    if expr:
        return expr.strip()
    classifiers = [
        c.split("::")[-1].strip()
        for c in meta.get_all("Classifier", [])
        if c.startswith("License ::")
    ]
    if classifiers:
        return ", ".join(classifiers)
    lic = (meta.get("License") or "").strip()
    return lic.splitlines()[0] if lic else "UNKNOWN"


def main(paths):
    rows = {}
    for dist in metadata.distributions(path=paths):
        meta = dist.metadata
        name = meta["Name"]
        rows[name] = (meta["Version"], license_of(meta), meta.get("Home-page") or "")
    print("Third-party python components bundled in this package")
    print("=" * 60)
    print()
    for name in sorted(rows, key=str.lower):
        version, lic, home = rows[name]
        print(f"{name} {version}")
        print(f"    License: {lic}")
        if home:
            print(f"    Homepage: {home}")
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
