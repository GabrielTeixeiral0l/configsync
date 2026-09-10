#!/usr/bin/env bats
# MountSync - tests/link.bats
# Tests for 'mosy link' cross-platform linking command

load 'test_helper.bash'

setup() {
    common_setup
    export MOSY_REMOTE_NAME="test-remote"
    export MOSY_MOUNT_POINT="$HOME/Cloud"
    export MOSY_CLOUD_DIR="$MOSY_MOUNT_POINT/mosy_vault"
    export MOSY_MAP_FILE="$MOSY_CLOUD_DIR/sync-map.conf"
    mkdir -p "$MOSY_CLOUD_DIR"
    mkdir -p "$HOME/.config/mosy"
    cat <<EOF > "$HOME/.config/mosy/config"
MOSY_REMOTE_NAME=test-remote
MOSY_MOUNT_POINT=$MOSY_MOUNT_POINT
MOSY_CLOUD_DIR=$MOSY_CLOUD_DIR
EOF
}

@test "Link: Links local path to existing cloud vault file and records in sync-map.conf" {
    # 1. Setup cloud vault item
    mkdir -p "$MOSY_CLOUD_DIR/.config/Code/User"
    echo '{"editor.fontSize": 14}' > "$MOSY_CLOUD_DIR/.config/Code/User/settings.json"
    echo ".config/Code/User/settings.json|.config/Code/User/settings.json|linux|editors" > "$MOSY_MAP_FILE"

    # 2. Link from Windows/Mac style local path
    run mosy link "$HOME/AppData/Roaming/Code/User/settings.json" ".config/Code/User/settings.json" -t windows
    assert_success
    assert_output --partial "Success! Linked ~/AppData/Roaming/Code/User/settings.json -> vault/.config/Code/User/settings.json (tags: windows)."

    # 3. Verify symlink exists and points to cloud vault
    [ -L "$HOME/AppData/Roaming/Code/User/settings.json" ]
    run cat "$HOME/AppData/Roaming/Code/User/settings.json"
    assert_output '{"editor.fontSize": 14}'

    # 4. Verify sync-map.conf contains both entries and inherited the 'editors' group
    run grep "AppData/Roaming/Code/User/settings.json|.config/Code/User/settings.json|windows|editors" "$MOSY_MAP_FILE"
    assert_success
}

@test "Link: Auto-discovers matching target in vault when 2nd argument is omitted" {
    mkdir -p "$MOSY_CLOUD_DIR/nvim"
    echo "vim.opt.number = true" > "$MOSY_CLOUD_DIR/nvim/init.lua"

    run mosy link "$HOME/.config/nvim/init.lua"
    assert_success
    assert_output --partial "Success! Linked ~/.config/nvim/init.lua -> vault/nvim/init.lua"

    [ -L "$HOME/.config/nvim/init.lua" ]
    run cat "$HOME/.config/nvim/init.lua"
    assert_output "vim.opt.number = true"
}

@test "Link: Fails with clear error if cloud vault target does not exist" {
    run mosy link "$HOME/missing.conf" "non_existent_vault_target.conf"
    assert_failure
    assert_output --partial "Error: Cloud vault target 'non_existent_vault_target.conf' does not exist"
}

@test "Link: Fails if target is outside HOME directory" {
    mkdir -p "$MOSY_CLOUD_DIR"
    touch "$MOSY_CLOUD_DIR/test.conf"

    run mosy link "/var/log/test.conf" "test.conf"
    assert_failure
    assert_output --partial "Error: Local path must be inside your HOME directory"
}

@test "Link: Safely backs up existing local file before linking" {
    mkdir -p "$MOSY_CLOUD_DIR"
    echo "cloud content" > "$MOSY_CLOUD_DIR/config.ini"

    mkdir -p "$HOME/.config"
    echo "local preexisting content" > "$HOME/.config/config.ini"

    run mosy link "$HOME/.config/config.ini" "config.ini"
    assert_success
    assert_output --partial "Backing up existing local file"

    # Verify backup exists with local preexisting content
    local backup_file
    backup_file=$(find "$HOME/.config" -name "config.ini.bak_*" | head -n 1)
    [ -n "$backup_file" ]
    run cat "$backup_file"
    assert_output "local preexisting content"

    # Verify active symlink has cloud content
    [ -L "$HOME/.config/config.ini" ]
    run cat "$HOME/.config/config.ini"
    assert_output "cloud content"
}

@test "Link: Auto-assigns active platform default tag (e.g. macos) when none passed" {
    export MOSY_OS_OVERRIDE="darwin"
    mkdir -p "$MOSY_CLOUD_DIR"
    echo "mac data" > "$MOSY_CLOUD_DIR/mac.conf"

    run mosy link "$HOME/Library/Preferences/mac.conf" "mac.conf"
    assert_success
    assert_output --partial "(tags: macos)"

    run grep "Library/Preferences/mac.conf|mac.conf|macos|" "$MOSY_MAP_FILE"
    assert_success
}

@test "Link: mosy add --link and --target delegate cleanly to link command" {
    mkdir -p "$MOSY_CLOUD_DIR"
    echo "target data" > "$MOSY_CLOUD_DIR/app.json"

    run mosy add "$HOME/.config/app.json" --link "app.json" -t all -g apps
    assert_success
    assert_output --partial "Success! Linked ~/.config/app.json -> vault/app.json (tags: all)."

    [ -L "$HOME/.config/app.json" ]
    run grep ".config/app.json|app.json|all|apps" "$MOSY_MAP_FILE"
    assert_success
}

@test "Core Tag Filter: Skips foreign OS tags on mosy init but processes matching and universal tags" {
    mkdir -p "$MOSY_CLOUD_DIR/.config/Code/User"
    echo '{"theme": "LinuxTheme"}' > "$MOSY_CLOUD_DIR/.config/Code/User/settings.json"

    mkdir -p "$MOSY_CLOUD_DIR/git"
    echo "[user] name = Dev" > "$MOSY_CLOUD_DIR/git/.gitconfig"

    # Map with Linux, macOS, and Windows entries for the same and different files
    cat <<EOF > "$MOSY_MAP_FILE"
.config/Code/User/settings.json|.config/Code/User/settings.json|linux|editors
Library/Application Support/Code/User/settings.json|.config/Code/User/settings.json|macos|editors
AppData/Roaming/Code/User/settings.json|.config/Code/User/settings.json|windows|editors
.gitconfig|git/.gitconfig|all|vcs
EOF

    # 1. Test on Linux environment (MOSY_OS_OVERRIDE=linux)
    export MOSY_OS_OVERRIDE="linux"
    run mosy init
    assert_success

    # Linux should have .config/Code and .gitconfig, but NOT Library or AppData
    assert_file_exists "$HOME/.config/Code/User/settings.json"
    assert_file_exists "$HOME/.gitconfig"
    [ ! -e "$HOME/Library" ]
    [ ! -e "$HOME/AppData" ]

    # 2. Test on Windows environment in fresh virtual home
    export HOME="$TEST_HOME/win_home"
    mkdir -p "$HOME/.config/mosy"
    cat <<EOF > "$HOME/.config/mosy/config"
MOSY_REMOTE_NAME=test-remote
MOSY_MOUNT_POINT=$MOSY_MOUNT_POINT
MOSY_CLOUD_DIR=$MOSY_CLOUD_DIR
EOF
    export MOSY_OS_OVERRIDE="windows"
    run mosy init
    assert_success

    # Windows should have AppData/Roaming and .gitconfig, but NOT .config/Code or Library
    assert_file_exists "$HOME/AppData/Roaming/Code/User/settings.json"
    assert_file_exists "$HOME/.gitconfig"
    [ ! -e "$HOME/.config/Code" ]
    [ ! -e "$HOME/Library" ]
}
