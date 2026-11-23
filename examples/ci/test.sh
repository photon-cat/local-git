#!/usr/bin/env bash
# CI: run by the hub's post-receive hook on every push, from a fresh export of the commit.
set -euo pipefail
python3 -m unittest -v
