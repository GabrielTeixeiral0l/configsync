#!/usr/bin/env bash
# MountSync - src/platform/init.sh
# Main loader for platform detection and adapters

platform_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$platform_dir/detect.sh" ]; then
    . "$platform_dir/detect.sh"
fi

case "${MOSY_OS:-linux}" in
    darwin)
        if [ -f "$platform_dir/darwin.sh" ]; then
            . "$platform_dir/darwin.sh"
        fi
        ;;
    windows)
        if [ -f "$platform_dir/windows.sh" ]; then
            . "$platform_dir/windows.sh"
        fi
        ;;
    linux|wsl|*)
        if [ -f "$platform_dir/linux.sh" ]; then
            . "$platform_dir/linux.sh"
        fi
        ;;
esac
