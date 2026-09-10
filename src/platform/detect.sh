#!/usr/bin/env bash
# MountSync - src/platform/detect.sh
# Cross-platform environment and OS detector

detect_platform() {
    if [ -n "${MOSY_OS_OVERRIDE:-}" ]; then
        export MOSY_OS="$MOSY_OS_OVERRIDE"
    elif [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] || ( [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null ); then
        export MOSY_OS="wsl"
    elif [[ "${OSTYPE:-}" == "darwin"* ]] || [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
        export MOSY_OS="darwin"
    elif [[ "${OSTYPE:-}" == "msys"* ]] || [[ "${OSTYPE:-}" == "cygwin"* ]] || [[ "${OSTYPE:-}" == "win32"* ]] || [[ "$(uname -s 2>/dev/null)" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
        export MOSY_OS="windows"
    else
        export MOSY_OS="linux"
    fi

    case "$MOSY_OS" in
        darwin)
            export MOSY_OS_NAME="macOS"
            export MOSY_OS_FAMILY="unix"
            export MOSY_DEFAULT_TAG="macos"
            ;;
        windows)
            export MOSY_OS_NAME="Windows"
            export MOSY_OS_FAMILY="windows"
            export MOSY_DEFAULT_TAG="windows"
            ;;
        wsl)
            export MOSY_OS_NAME="WSL (Windows Subsystem for Linux)"
            export MOSY_OS_FAMILY="unix"
            export MOSY_DEFAULT_TAG="wsl"
            ;;
        linux|*)
            export MOSY_OS="linux"
            export MOSY_OS_NAME="Linux"
            export MOSY_OS_FAMILY="unix"
            export MOSY_DEFAULT_TAG="linux"
            ;;
    esac
}

# Auto-detect on source
detect_platform
