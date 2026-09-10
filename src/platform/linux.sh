#!/usr/bin/env bash
# MountSync - src/platform/linux.sh
# Platform adapter for Linux / systemd

platform_is_mounted() {
    local target="${1:-$MOSY_MOUNT_POINT}"
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$target"
    else
        mount 2>/dev/null | grep -qE "[[:space:]]on[[:space:]]${target%/}/?[[:space:]]"
    fi
}

platform_service_type() {
    echo "systemd"
}

platform_service_status() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user is-active mosy-mount.service 2>/dev/null | head -n 1 || echo "inactive"
    else
        echo "unavailable"
    fi
}

platform_service_start() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user start mosy-mount.service 2>/dev/null || return 1
    fi
}

platform_service_stop() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user stop mosy-mount.service 2>/dev/null || true
    fi
}

platform_service_enable() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable mosy-mount.service 2>/dev/null || return 1
    fi
}

platform_service_disable() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable mosy-mount.service 2>/dev/null || true
    fi
}

platform_service_reload() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
}

platform_service_file() {
    echo "${HOME}/.config/systemd/user/mosy-mount.service"
}

platform_service_hint() {
    echo "Try: systemctl --user start mosy-mount.service (if installed)"
}

platform_create_service() {
    local remote="$1"
    local mount_pt="$2"
    local service_dir="${HOME}/.config/systemd/user"
    local service_file="$service_dir/mosy-mount.service"
    local rclone_bin
    rclone_bin=$(command -v rclone 2>/dev/null || echo "rclone")

    mkdir -p "$service_dir" || return 1

    cat <<EOF > "$service_file" || return 1
[Unit]
Description=Rclone Mount for MountSync
After=network-online.target

[Service]
Type=simple
ExecStart=$rclone_bin mount ${remote}: ${mount_pt} --vfs-cache-mode writes
ExecStop=/bin/fusermount -u ${mount_pt}
Restart=on-failure

[Install]
WantedBy=default.target
EOF
}

platform_uninstall_service() {
    local service_file
    service_file=$(platform_service_file)
    platform_service_stop
    platform_service_disable
    rm -f "$service_file"
    platform_service_reload
}
