#!/usr/bin/env bash
# MountSync - src/platform/darwin.sh
# Platform adapter for macOS / launchd

platform_is_mounted() {
    local target="${1:-$MOSY_MOUNT_POINT}"
    local target_clean="${target%/}"
    [ -z "$target_clean" ] && return 1

    # Check via mount list
    if mount 2>/dev/null | grep -qE "[[:space:]]on[[:space:]]${target_clean}/?[[:space:]]"; then
        return 0
    fi

    # Check via df mount point resolution
    local df_mount
    df_mount=$(df "$target_clean" 2>/dev/null | awk 'NR==2 {print $NF}')
    if [ -n "$df_mount" ] && [ "${df_mount%/}" = "$target_clean" ]; then
        return 0
    fi

    return 1
}

platform_service_type() {
    echo "launchd"
}

platform_service_status() {
    if command -v launchctl >/dev/null 2>&1; then
        if launchctl list 2>/dev/null | grep -q "com.mountsync.rclone"; then
            echo "active"
        else
            echo "inactive"
        fi
    else
        echo "unavailable"
    fi
}

platform_service_start() {
    local service_file
    service_file=$(platform_service_file)
    if command -v launchctl >/dev/null 2>&1; then
        if [ -f "$service_file" ]; then
            launchctl load -w "$service_file" 2>/dev/null || launchctl start com.mountsync.rclone 2>/dev/null || return 1
        fi
    fi
}

platform_service_stop() {
    local service_file
    service_file=$(platform_service_file)
    if command -v launchctl >/dev/null 2>&1; then
        if [ -f "$service_file" ]; then
            launchctl unload "$service_file" 2>/dev/null || launchctl stop com.mountsync.rclone 2>/dev/null || true
        fi
    fi
}

platform_service_enable() {
    local service_file
    service_file=$(platform_service_file)
    if command -v launchctl >/dev/null 2>&1 && [ -f "$service_file" ]; then
        launchctl load -w "$service_file" 2>/dev/null || return 1
    fi
}

platform_service_disable() {
    local service_file
    service_file=$(platform_service_file)
    if command -v launchctl >/dev/null 2>&1 && [ -f "$service_file" ]; then
        launchctl unload -w "$service_file" 2>/dev/null || true
    fi
}

platform_service_reload() {
    true
}

platform_service_file() {
    echo "${HOME}/Library/LaunchAgents/com.mountsync.rclone.plist"
}

platform_service_hint() {
    echo "Try: launchctl load -w ~/Library/LaunchAgents/com.mountsync.rclone.plist"
}

platform_create_service() {
    local remote="$1"
    local mount_pt="$2"
    local service_dir="${HOME}/Library/LaunchAgents"
    local service_file="$service_dir/com.mountsync.rclone.plist"
    local rclone_bin
    rclone_bin=$(command -v rclone 2>/dev/null || echo "/usr/local/bin/rclone")

    mkdir -p "$service_dir" || return 1

    cat <<EOF > "$service_file" || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mountsync.rclone</string>
    <key>ProgramArguments</key>
    <array>
        <string>$rclone_bin</string>
        <string>mount</string>
        <string>${remote}:</string>
        <string>${mount_pt}</string>
        <string>--vfs-cache-mode</string>
        <string>writes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${HOME}/.config/mosy/rclone-mount.log</string>
    <key>StandardOutPath</key>
    <string>${HOME}/.config/mosy/rclone-mount.log</string>
</dict>
</plist>
EOF
}

platform_uninstall_service() {
    local service_file
    service_file=$(platform_service_file)
    platform_service_stop
    platform_service_disable
    rm -f "$service_file"
}
