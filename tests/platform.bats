#!/usr/bin/env bats

load 'test_helper.bash'

setup() {
    load 'test_helper.bash'
    common_setup
    export MOSY_REMOTE_NAME="test-remote"
    export MOSY_MOUNT_POINT="$HOME/Cloud"
    export MOSY_CLOUD_DIR="$MOSY_MOUNT_POINT/mosy_vault"
    mkdir -p "$MOSY_CLOUD_DIR"
    mkdir -p "$HOME/.config/mosy"
    mkdir -p "$MOCK_BIN"
}

@test "Platform Detect: Accurately detects Linux environment" {
    export MOSY_OS_OVERRIDE="linux"
    source "$PROJECT_ROOT/src/platform/detect.sh"
    [ "$MOSY_OS" = "linux" ]
    [ "$MOSY_OS_NAME" = "Linux" ]
    [ "$MOSY_OS_FAMILY" = "unix" ]
    [ "$MOSY_DEFAULT_TAG" = "linux" ]
}

@test "Platform Detect: Accurately detects macOS (Darwin) environment" {
    export MOSY_OS_OVERRIDE="darwin"
    source "$PROJECT_ROOT/src/platform/detect.sh"
    [ "$MOSY_OS" = "darwin" ]
    [ "$MOSY_OS_NAME" = "macOS" ]
    [ "$MOSY_OS_FAMILY" = "unix" ]
    [ "$MOSY_DEFAULT_TAG" = "macos" ]
}

@test "Platform Detect: Accurately detects Windows (MSYS/Git Bash) environment" {
    export MOSY_OS_OVERRIDE="windows"
    source "$PROJECT_ROOT/src/platform/detect.sh"
    [ "$MOSY_OS" = "windows" ]
    [ "$MOSY_OS_NAME" = "Windows" ]
    [ "$MOSY_OS_FAMILY" = "windows" ]
    [ "$MOSY_DEFAULT_TAG" = "windows" ]
}

@test "Platform Detect: Accurately detects WSL environment" {
    export MOSY_OS_OVERRIDE="wsl"
    source "$PROJECT_ROOT/src/platform/detect.sh"
    [ "$MOSY_OS" = "wsl" ]
    [ "$MOSY_OS_NAME" = "WSL (Windows Subsystem for Linux)" ]
    [ "$MOSY_OS_FAMILY" = "unix" ]
    [ "$MOSY_DEFAULT_TAG" = "wsl" ]
}

@test "Darwin Adapter: Generates valid launchd plist file and manages lifecycle" {
    export MOSY_OS_OVERRIDE="darwin"
    source "$PROJECT_ROOT/src/platform/init.sh"

    # Mock launchctl
    cat <<'EOF' > "$MOCK_BIN/launchctl"
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo "12345 0 com.mountsync.rclone"
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/launchctl"

    run platform_service_type
    assert_output "launchd"

    run platform_create_service "MyRemote" "$HOME/MyCloud"
    assert_success

    local plist_file="$HOME/Library/LaunchAgents/com.mountsync.rclone.plist"
    assert_file_exists "$plist_file"
    run cat "$plist_file"
    assert_output --partial "<string>com.mountsync.rclone</string>"
    assert_output --partial "<string>MyRemote:</string>"
    assert_output --partial "<string>$HOME/MyCloud</string>"
    assert_output --partial "<string>--vfs-cache-mode</string>"

    run platform_service_status
    assert_output "active"

    run platform_uninstall_service
    assert_success
    [ ! -f "$plist_file" ]
}

@test "Windows Adapter: Generates CLI shims and background runner" {
    export MOSY_OS_OVERRIDE="windows"
    source "$PROJECT_ROOT/src/platform/init.sh"

    # Verify winsymlinks export
    [ "$MSYS" = "winsymlinks:nativestrict" ]

    run platform_service_type
    assert_output "windows-background"

    run platform_create_service "WinRemote" "$HOME/WinCloud"
    assert_success

    local cmd_runner="$HOME/.config/mosy/mount-runner.cmd"
    local vbs_runner="$HOME/.config/mosy/mount-runner.vbs"
    assert_file_exists "$cmd_runner"
    assert_file_exists "$vbs_runner"
    run cat "$cmd_runner"
    assert_output --partial 'mount "WinRemote:"'

    # Test CLI shims generation
    local bin_dir="$HOME/.local/bin"
    run platform_create_shims "$bin_dir" "$PROJECT_ROOT/mosy"
    assert_success

    assert_file_exists "$bin_dir/mosy.cmd"
    assert_file_exists "$bin_dir/mosy.ps1"

    run cat "$bin_dir/mosy.cmd"
    assert_output --partial "bash \"%~dp0mosy\" %*"

    run cat "$bin_dir/mosy.ps1"
    assert_output --partial '& bash "$PSScriptRoot/mosy" @args'

    run platform_uninstall_service
    assert_success
    [ ! -f "$cmd_runner" ]
    [ ! -f "$vbs_runner" ]
}

@test "Install: Automatically adapts to macOS with launchd service creation" {
    export MOSY_OS_OVERRIDE="darwin"
    echo -e '#!/bin/bash\nif [[ "$1" == "listremotes" ]]; then echo "GoogleDrive:"; fi' > "$MOCK_BIN/rclone"
    chmod +x "$MOCK_BIN/rclone"

    # Mock launchctl
    cat <<'EOF' > "$MOCK_BIN/launchctl"
#!/bin/bash
echo "Mocked launchctl $@"
exit 0
EOF
    chmod +x "$MOCK_BIN/launchctl"

    run bash -c "printf 'MacRemote\ny\n$HOME/MacCloud\ny\n' | bash install.sh"
    assert_success
    assert_file_exists "$HOME/.config/mosy/config"
    assert_file_exists "$HOME/Library/LaunchAgents/com.mountsync.rclone.plist"
    assert_output --partial "Setting up background mount service (macOS)..."
}

@test "Install: Automatically adapts to Windows with CLI shims and background runner" {
    export MOSY_OS_OVERRIDE="windows"
    echo -e '#!/bin/bash\nif [[ "$1" == "listremotes" ]]; then echo "GoogleDrive:"; fi' > "$MOCK_BIN/rclone"
    chmod +x "$MOCK_BIN/rclone"

    run bash -c "printf 'WinRemote\ny\n$HOME/WinCloud\ny\n' | bash install.sh"
    assert_success
    assert_file_exists "$HOME/.config/mosy/config"
    assert_file_exists "$HOME/.config/mosy/mount-runner.cmd"
    assert_file_exists "$HOME/.config/mosy/mount-runner.vbs"
    assert_file_exists "$HOME/.local/bin/mosy.cmd"
    assert_file_exists "$HOME/.local/bin/mosy.ps1"
    assert_output --partial "Setting up background mount service (Windows)..."
}
