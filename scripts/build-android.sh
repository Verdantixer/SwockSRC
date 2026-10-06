#!/usr/bin/env bash
set -euo pipefail

# Reuses Flutter/Gradle caches and avoids accidental concurrent Android builds.
# Default is the fast, device-ready ARM64 build. Use "universal" only when a
# single APK for multiple CPU architectures is actually required.
build_kind=${1:-arm64}
export PATH="/home/richboybrown/flutter-sdk/bin:${PATH}"

case "$build_kind" in
  arm64)
    flutter build apk --release --target-platform android-arm64
    ;;
  universal)
    flutter build apk --release
    ;;
  split)
    flutter build apk --release --split-per-abi
    ;;
  *)
    echo 'Usage: scripts/build-android.sh [arm64|universal|split]' >&2
    exit 2
    ;;
esac
