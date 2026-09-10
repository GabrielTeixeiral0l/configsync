#!/usr/bin/env bash
# MountSync - tests/docker/test-3-os-containers.sh
# Multi-container 3-OS simulation: Linux, macOS, and Windows containers syncing real apps

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "============================================================"
echo " Running 3-Container Multi-OS Live Sync Test"
echo "============================================================"

# Ensure test image exists
echo " Building test image..."
docker build -t mountsync-test -f tests/docker/Dockerfile . >/dev/null

# Create shared temporary cloud volume
SHARED_VAULT=$(mktemp -d /tmp/mosy_cloud_XXXXXX)
chmod 777 "$SHARED_VAULT"
mkdir -p "$SHARED_VAULT/mosy_vault"

# Create isolated home directories for each simulated machine
LINUX_HOME=$(mktemp -d /tmp/mosy_node_linux_XXXXXX)
MACOS_HOME=$(mktemp -d /tmp/mosy_node_macos_XXXXXX)
WIN_HOME=$(mktemp -d /tmp/mosy_node_win_XXXXXX)

chmod 777 "$LINUX_HOME" "$MACOS_HOME" "$WIN_HOME"

cleanup() {
    echo " Cleaning up test containers and volumes..."
    docker rm -f mosy-linux mosy-macos mosy-windows 2>/dev/null || true
    rm -rf "$SHARED_VAULT" "$LINUX_HOME" "$MACOS_HOME" "$WIN_HOME" 2>/dev/null || true
}
trap cleanup EXIT

echo "  [Node 1 - Linux]: Setting up initial real application configs (VS Code, Neovim, Git)..."
docker run --rm \
    -e MOSY_OS_OVERRIDE=linux \
    -e MOSY_NO_TTY=1 \
    -e HOME=/home/tester \
    -v "$PROJECT_ROOT:/home/tester/mountsync:ro" \
    -v "$SHARED_VAULT:/home/tester/Cloud" \
    -v "$LINUX_HOME:/home/tester" \
    mountsync-test bash -c '
        set -e
        export PATH="/home/tester/mountsync:$PATH"
        mkdir -p /home/tester/.config/mosy
        cat <<EOF > /home/tester/.config/mosy/config
MOSY_REMOTE_NAME=shared-cloud
MOSY_MOUNT_POINT=/home/tester/Cloud
MOSY_CLOUD_DIR=/home/tester/Cloud/mosy_vault
EOF
        # Real VS Code Settings on Linux
        mkdir -p /home/tester/.config/Code/User
        cat <<EOF > /home/tester/.config/Code/User/settings.json
{
  "editor.fontSize": 14,
  "workbench.colorTheme": "Dracula",
  "editor.tabSize": 2
}
EOF
        # Real Neovim Config on Linux
        mkdir -p /home/tester/.config/nvim
        echo "vim.opt.number = true" > /home/tester/.config/nvim/init.lua

        # Real Git Config on Linux
        cat <<EOF > /home/tester/.gitconfig
[user]
    name = Linux User
    email = linux@example.com
EOF

        # Add to MountSync vault from Linux
        mosy add /home/tester/.config/Code/User/settings.json -t linux -g editors
        mosy add /home/tester/.config/nvim/init.lua -t linux,macos -g editors
        mosy add /home/tester/.gitconfig -t all -g vcs

        echo " [Linux Node]: Configs vaulted successfully!"
    '

echo " [Node 2 - macOS]: Initializing dotfiles from Cloud Vault via flagless mosy init & mosy link..."
docker run --rm \
    -e MOSY_OS_OVERRIDE=darwin \
    -e MOSY_NO_TTY=1 \
    -e HOME=/home/tester \
    -v "$PROJECT_ROOT:/home/tester/mountsync:ro" \
    -v "$SHARED_VAULT:/home/tester/Cloud" \
    -v "$MACOS_HOME:/home/tester" \
    mountsync-test bash -c '
        set -e
        export PATH="/home/tester/mountsync:$PATH"
        mkdir -p /home/tester/.config/mosy
        cat <<EOF > /home/tester/.config/mosy/config
MOSY_REMOTE_NAME=shared-cloud
MOSY_MOUNT_POINT=/home/tester/Cloud
MOSY_CLOUD_DIR=/home/tester/Cloud/mosy_vault
EOF
        # Flagless init automatically links universal items (git, nvim)
        mosy init

        # Link macOS-specific VS Code path to cloud vault
        mosy link "/home/tester/Library/Application Support/Code/User/settings.json" ".config/Code/User/settings.json"

        # Validate macOS paths
        MAC_VSCODE="/home/tester/Library/Application Support/Code/User/settings.json"
        MAC_NVIM="/home/tester/.config/nvim/init.lua"
        MAC_GIT="/home/tester/.gitconfig"

        [ -f "$MAC_VSCODE" ] || { echo " macOS VS Code config missing"; exit 1; }
        [ -f "$MAC_NVIM" ] || { echo " macOS Neovim config missing"; exit 1; }
        [ -f "$MAC_GIT" ] || { echo " macOS Git config missing"; exit 1; }

        grep -q "Dracula" "$MAC_VSCODE" || { echo " Theme mismatch on macOS"; exit 1; }
        grep -q "vim.opt.number = true" "$MAC_NVIM" || { echo " Neovim mismatch on macOS"; exit 1; }

        echo " [macOS Node]: Replicated configs into ~/Library and ~/.config perfectly via mosy link!"
    '

echo " [Node 3 - Windows]: Initializing dotfiles into Windows AppData via mosy link..."
docker run --rm \
    -e MOSY_OS_OVERRIDE=windows \
    -e MOSY_NO_TTY=1 \
    -e HOME=/home/tester \
    -v "$PROJECT_ROOT:/home/tester/mountsync:ro" \
    -v "$SHARED_VAULT:/home/tester/Cloud" \
    -v "$WIN_HOME:/home/tester" \
    mountsync-test bash -c '
        set -e
        export PATH="/home/tester/mountsync:$PATH"
        mkdir -p /home/tester/.config/mosy
        cat <<EOF > /home/tester/.config/mosy/config
MOSY_REMOTE_NAME=shared-cloud
MOSY_MOUNT_POINT=/home/tester/Cloud
MOSY_CLOUD_DIR=/home/tester/Cloud/mosy_vault
EOF
        # Flagless init automatically links universal items (git)
        mosy init

        # Link Windows AppData paths to existing cloud vault items
        mosy link "/home/tester/AppData/Roaming/Code/User/settings.json" ".config/Code/User/settings.json"
        mosy link "/home/tester/AppData/Local/nvim/init.lua" ".config/nvim/init.lua"

        # Validate Windows paths
        WIN_VSCODE="/home/tester/AppData/Roaming/Code/User/settings.json"
        WIN_NVIM="/home/tester/AppData/Local/nvim/init.lua"
        WIN_GIT="/home/tester/.gitconfig"

        [ -f "$WIN_VSCODE" ] || { echo " Windows VS Code config missing"; exit 1; }
        [ -f "$WIN_NVIM" ] || { echo " Windows Neovim config missing"; exit 1; }
        [ -f "$WIN_GIT" ] || { echo " Windows Git config missing"; exit 1; }

        grep -q "Dracula" "$WIN_VSCODE" || { echo " Theme mismatch on Windows"; exit 1; }
        grep -q "vim.opt.number = true" "$WIN_NVIM" || { echo " Neovim mismatch on Windows"; exit 1; }

        # Now Windows modifies VS Code Theme to Tokyo Night
        cat <<EOF > "$WIN_VSCODE"
{
  "editor.fontSize": 16,
  "workbench.colorTheme": "Tokyo Night",
  "editor.tabSize": 2
}
EOF
        echo " [Windows Node]: Replicated configs to AppData via mosy link and updated theme to Tokyo Night!"
    '

echo " [Cross-Platform Verification]: Verifying live sync across all 3 OS nodes..."
docker run --rm \
    -e MOSY_OS_OVERRIDE=linux \
    -e HOME=/home/tester \
    -v "$SHARED_VAULT:/home/tester/Cloud" \
    -v "$LINUX_HOME:/home/tester" \
    mountsync-test bash -c '
        set -e
        grep -q "Tokyo Night" "/home/tester/.config/Code/User/settings.json" || { echo " Linux did not receive Windows edit"; exit 1; }
        grep -q "16" "/home/tester/.config/Code/User/settings.json" || { echo " Linux did not receive font size update"; exit 1; }
        echo " [Linux Node]: Successfully received Windows VS Code modification live!"
    '

docker run --rm \
    -e MOSY_OS_OVERRIDE=darwin \
    -e HOME=/home/tester \
    -v "$SHARED_VAULT:/home/tester/Cloud" \
    -v "$MACOS_HOME:/home/tester" \
    mountsync-test bash -c '
        set -e
        grep -q "Tokyo Night" "/home/tester/Library/Application Support/Code/User/settings.json" || { echo " macOS did not receive Windows edit"; exit 1; }
        echo " [macOS Node]: Successfully received Windows VS Code modification live in ~/Library!"
    '

echo "============================================================"
echo " SUCCESS: All 3 OS containers communicated and synced live!"
echo "============================================================"
