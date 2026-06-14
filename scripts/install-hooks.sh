#!/usr/bin/env bash
cd "$(dirname "$0")/.." && git config core.hooksPath .githooks && echo "✓ hooks installed (core.hooksPath=.githooks)"
