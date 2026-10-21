#!/usr/bin/env bash
set -euo pipefail

# Reuses Flutter/Gradle caches and avoids accidental concurrent Android builds.
# Default to one APK containing every configured Android architecture.
build_kind=${1:-universal}
export PATH="/home/richboybrown/flutter-sdk/bin:${PATH}"

case "$build_kind" in
  universal)
    flutter build apk --release
    ;;
  split)
    flutter build apk --release --split-per-abi
    ;;
  *)
    echo 'Usage: scripts/build-android.sh [universal|split]' >&2
    exit 2
    ;;
esac
