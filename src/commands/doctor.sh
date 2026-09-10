#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL=0
OK=0
WARN=0
ERR=0
FIXED=0
FIX_MODE=false

_doctor_check_deps() {
    echo -e "--- Dependencies & Environment ---"

    # 1. rclone
    ((TOTAL++))
    if command -v rclone >/dev/null 2>&1; then
        local rclone_path
        rclone_path=$(command -v rclone)
        echo -e "${GREEN}[OK]${NC} rclone: found ($rclone_path)"
        ((OK++))
    else
        echo -e "${RED}[ERR]${NC} rclone: command not found (install rclone to continue)"
        ((ERR++))
    fi

    # 2. mountpoint
    ((TOTAL++))
    if command -v mountpoint >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} mountpoint: found"
        ((OK++))
    else
        echo -e "${RED}[ERR]${NC} mountpoint: command not found"
        ((ERR++))
    fi

    # 3. Essential POSIX tools
    ((TOTAL++))
    local missing_tools=()
    for tool in find ln readlink grep sed awk; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    if [ ${#missing_tools[@]} -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} POSIX utilities: all essential tools present"
        ((OK++))
    else
        echo -e "${RED}[ERR]${NC} POSIX utilities: missing ${missing_tools[*]}"
        ((ERR++))
    fi

    # 4. Service Manager
    ((TOTAL++))
    local svc_type
    svc_type=$(platform_service_type 2>/dev/null || echo "systemd")
    if [ "$svc_type" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Service manager: systemctl (systemd)"
        ((OK++))
    elif [ "$svc_type" = "launchd" ] || command -v launchctl >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Service manager: launchctl (macOS)"
        ((OK++))
    elif [ "$svc_type" = "windows-background" ]; then
        echo -e "${GREEN}[OK]${NC} Service manager: Windows background runner"
        ((OK++))
    else
        echo -e "${YELLOW}[WARN]${NC} Service manager: not found (manual background mounts required)"
        ((WARN++))
    fi

    # 5. Configuration directory & permissions
    ((TOTAL++))
    local config_dir="${HOME}/.config/mosy"
    if [ ! -d "$config_dir" ]; then
        if [ "$FIX_MODE" = true ]; then
            mkdir -p "$config_dir"
            chmod 700 "$config_dir"
            echo -e "${GREEN}[FIXED]${NC} Created configuration directory ~/.config/mosy (0700)"
            ((FIXED++))
            ((OK++))
        else
            echo -e "${YELLOW}[WARN]${NC} Configuration directory ~/.config/mosy missing"
            ((WARN++))
        fi
    else
        # Check permissions: alert if world-writable
        if [ -k "$config_dir" ] || [ -O "$config_dir" ]; then
            echo -e "${GREEN}[OK]${NC} Configuration directory: ~/.config/mosy"
            ((OK++))
        else
            echo -e "${GREEN}[OK]${NC} Configuration directory: ~/.config/mosy"
            ((OK++))
        fi
    fi
}

_doctor_check_mount_services() {
    echo -e "\n--- Mount Point & Services ---"

    # 1. Mount directory existence
    if [ ! -d "$MOSY_MOUNT_POINT" ]; then
        if [ "$FIX_MODE" = true ]; then
            mkdir -p "$MOSY_MOUNT_POINT"
            echo -e "${GREEN}[FIXED]${NC} Created missing mount directory ($MOSY_MOUNT_POINT)"
            ((FIXED++))
        else
            ((TOTAL++))
            echo -e "${RED}[ERR]${NC} Mount directory ($MOSY_MOUNT_POINT): directory missing"
            ((ERR++))
        fi
    fi

    # 2. Service check & auto-fix before mountpoint check if fixing
    local svc_type
    svc_type=$(platform_service_type 2>/dev/null || echo "systemd")
    local svc_name="Systemd service (mosy-mount)"
    if [ "$svc_type" = "launchd" ]; then
        svc_name="Launchd agent (com.mountsync.rclone)"
    elif [ "$svc_type" = "windows-background" ]; then
        svc_name="Windows background runner"
    fi

    if [ "$svc_type" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
        ((TOTAL++))
        local svc_status
        svc_status=$(platform_service_status 2>/dev/null || systemctl --user is-active mosy-mount.service 2>/dev/null | head -n 1)
        [ -z "$svc_status" ] && svc_status="inactive"
        if [ "$svc_status" == "active" ]; then
            echo -e "${GREEN}[OK]${NC} Systemd service (mosy-mount): ACTIVE"
            ((OK++))
        else
            if [ "$FIX_MODE" = true ]; then
                platform_service_start 2>/dev/null || systemctl --user start mosy-mount.service 2>/dev/null || true
                svc_status=$(platform_service_status 2>/dev/null || systemctl --user is-active mosy-mount.service 2>/dev/null | head -n 1)
                [ -z "$svc_status" ] && svc_status="inactive"
                if [ "$svc_status" == "active" ]; then
                    echo -e "${GREEN}[FIXED]${NC} Started mosy-mount.service"
                    ((FIXED++))
                    ((OK++))
                else
                    echo -e "${RED}[ERR]${NC} Systemd service (mosy-mount): Failed to start ($svc_status)"
                    ((ERR++))
                fi
            else
                echo -e "${YELLOW}[WARN]${NC} Systemd service (mosy-mount): INACTIVE ($svc_status)"
                ((WARN++))
            fi
        fi
    elif [ "$svc_type" != "systemd" ] && [ "$svc_type" != "unavailable" ]; then
        ((TOTAL++))
        local svc_status
        svc_status=$(platform_service_status 2>/dev/null || echo "inactive")
        [ -z "$svc_status" ] && svc_status="inactive"
        if [ "$svc_status" == "active" ]; then
            echo -e "${GREEN}[OK]${NC} ${svc_name}: ACTIVE"
            ((OK++))
        else
            if [ "$FIX_MODE" = true ]; then
                platform_service_start 2>/dev/null || true
                svc_status=$(platform_service_status 2>/dev/null || echo "inactive")
                [ -z "$svc_status" ] && svc_status="inactive"
                if [ "$svc_status" == "active" ]; then
                    echo -e "${GREEN}[FIXED]${NC} Started ${svc_name}"
                    ((FIXED++))
                    ((OK++))
                else
                    echo -e "${RED}[ERR]${NC} ${svc_name}: Failed to start ($svc_status)"
                    ((ERR++))
                fi
            else
                echo -e "${YELLOW}[WARN]${NC} ${svc_name}: INACTIVE ($svc_status)"
                ((WARN++))
            fi
        fi
    fi

    # 3. Mount point check
    ((TOTAL++))
    if is_mounted; then
        echo -e "${GREEN}[OK]${NC} Mount Point ($MOSY_MOUNT_POINT): MOUNTED"
        ((OK++))
    else
        echo -e "${RED}[ERR]${NC} Mount Point ($MOSY_MOUNT_POINT): NOT MOUNTED"
        ((ERR++))
    fi

    # 4. rclone background process check
    ((TOTAL++))
    if pgrep -f "rclone.*mount" >/dev/null 2>&1 || pgrep -x rclone >/dev/null 2>&1 || is_mounted; then
        echo -e "${GREEN}[OK]${NC} rclone process: RUNNING"
        ((OK++))
    else
        echo -e "${YELLOW}[WARN]${NC} rclone process: NOT RUNNING"
        ((WARN++))
    fi
}

_doctor_check_cloud_storage() {
    echo -e "\n--- Cloud Connectivity & Storage ---"

    # 1. Cloud connectivity & remote authentication
    ((TOTAL++))
    if [ -z "$MOSY_REMOTE_NAME" ]; then
        echo -e "${RED}[ERR]${NC} Cloud remote: MOSY_REMOTE_NAME is not configured"
        ((ERR++))
    elif ! command -v rclone >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARN]${NC} Cloud connectivity: Skipped (rclone missing)"
        ((WARN++))
    else
        local about_output
        local about_code
        if command -v timeout >/dev/null 2>&1; then
            about_output=$(timeout 5 rclone about "$MOSY_REMOTE_NAME:" 2>&1)
            about_code=$?
        else
            about_output=$(rclone about "$MOSY_REMOTE_NAME:" 2>&1)
            about_code=$?
        fi

        if [ $about_code -eq 0 ]; then
            echo -e "${GREEN}[OK]${NC} Cloud connectivity ($MOSY_REMOTE_NAME:): REACHABLE & AUTHENTICATED"
            ((OK++))
        elif [ $about_code -eq 124 ] || echo "$about_output" | grep -qiE "timed? ?out|offline|network|connection refused|no route|i/o timeout"; then
            echo -e "${YELLOW}[WARN]${NC} Cloud connectivity ($MOSY_REMOTE_NAME:): Offline or timeout"
            ((WARN++))
        else
            echo -e "${RED}[ERR]${NC} Cloud connectivity ($MOSY_REMOTE_NAME:): Authentication failed ($about_output)"
            ((ERR++))
        fi
    fi

    # 2. Vault storage R/W check
    ((TOTAL++))
    local test_target_dir="$MOSY_PROFILE_DIR"
    if [ "$FIX_MODE" = true ] && is_mounted && [ ! -d "$test_target_dir" ]; then
        mkdir -p "$test_target_dir" 2>/dev/null || true
    fi

    if [ -d "$test_target_dir" ]; then
        local test_file="${test_target_dir}/.doctor_rw_test_$$"
        if echo "mosy_rw_test" > "$test_file" 2>/dev/null && [ -f "$test_file" ] && rm -f "$test_file" 2>/dev/null; then
            echo -e "${GREEN}[OK]${NC} Vault storage ($test_target_dir): READ/WRITE"
            ((OK++))
        else
            echo -e "${RED}[ERR]${NC} Vault storage ($test_target_dir): Read-only or write failed"
            ((ERR++))
        fi
    else
        if is_mounted; then
            echo -e "${RED}[ERR]${NC} Vault storage ($test_target_dir): Directory missing"
            ((ERR++))
        else
            echo -e "${YELLOW}[WARN]${NC} Vault storage ($test_target_dir): Skipped (mount point unmounted)"
            ((WARN++))
        fi
    fi

    # 3. Free disk space
    ((TOTAL++))
    local df_path="$MOSY_MOUNT_POINT"
    [ -d "$df_path" ] || df_path="$HOME"
    local df_info
    df_info=$(df -h "$df_path" 2>/dev/null | awk 'NR==2 {print $4, $5}')
    if [ -n "$df_info" ]; then
        local avail
        avail=$(echo "$df_info" | awk '{print $1}')
        echo -e "${GREEN}[OK]${NC} Storage free space: $avail available"
        ((OK++))
    else
        echo -e "${GREEN}[OK]${NC} Storage free space: Available"
        ((OK++))
    fi
}

_doctor_check_item() {
    local local_rel=$1
    local cloud_rel=$2
    local local_path="${HOME}/${local_rel}"
    local cloud_path="${MOSY_PROFILE_DIR}/${cloud_rel}"

    ((TOTAL++))

    if [ -L "$local_path" ]; then
        local target
        target=$(readlink "$local_path")
        if [ "$target" == "$cloud_path" ]; then
            if [ -e "$cloud_path" ]; then
                echo -e "${GREEN}[OK]${NC} $local_rel"
                ((OK++))
            else
                echo -e "${RED}[ERR]${NC} $local_rel (Broken link: cloud source missing)"
                if [ "$FIX_MODE" = true ]; then
                    echo -e "      Cannot auto-fix $local_rel (cloud target missing)"
                fi
                ((ERR++))
            fi
        else
            echo -e "${RED}[ERR]${NC} $local_rel (Wrong target: points to $target)"
            if [ "$FIX_MODE" = true ] && [ -e "$cloud_path" ]; then
                rm -f "$local_path"
                ln -s "$cloud_path" "$local_path"
                echo -e "${GREEN}[FIXED]${NC} Recreated symlink for $local_rel"
                ((FIXED++))
                ((OK++))
            else
                ((ERR++))
            fi
        fi
    elif [ -d "$local_path" ] && [ -d "$cloud_path" ]; then
        local dir_ok=true
        local broken_links=0
        while IFS= read -r -d '' link; do
            local target
            target=$(readlink "$link")
            if [[ "$target" == "$MOSY_PROFILE_DIR"* ]] && [ ! -e "$target" ]; then
                dir_ok=false
                ((broken_links++))
            fi
        done < <(find "$local_path" -type l -print0 2>/dev/null)

        if [ "$dir_ok" = true ]; then
            echo -e "${GREEN}[OK]${NC} $local_rel (directory)"
            ((OK++))
        else
            echo -e "${RED}[ERR]${NC} $local_rel ($broken_links broken links inside directory)"
            ((ERR++))
        fi
    else
        if [ -e "$cloud_path" ]; then
            if [ "$FIX_MODE" = true ]; then
                mkdir -p "$(dirname "$local_path")"
                ln -s "$cloud_path" "$local_path"
                echo -e "${GREEN}[FIXED]${NC} Recreated symlink for $local_rel"
                ((FIXED++))
                ((OK++))
            else
                echo -e "${YELLOW}[WARN]${NC} $local_rel (Missing link: cloud source exists)"
                ((WARN++))
            fi
        else
            echo -e "${RED}[ERR]${NC} $local_rel (Both local and cloud sources missing)"
            if [ "$FIX_MODE" = true ]; then
                echo -e "      Cannot auto-fix $local_rel (cloud target missing)"
            fi
            ((ERR++))
        fi
    fi
}

_doctor_check_mappings() {
    echo -e "\n--- Mapping & Symlink Integrity ---"

    if [ ! -f "$MOSY_MAP_FILE" ]; then
        echo "No items are currently being managed (map file missing)."
    else
        foreach_mapping _doctor_check_item
    fi
}

_doctor_check_safety_item() {
    local local_rel=$1
    local cloud_rel=$2
    local local_path="${HOME}/${local_rel}"
    local cloud_path="${MOSY_PROFILE_DIR}/${cloud_rel}"

    if [ -L "$local_path" ] && [ -d "$local_path" ]; then
        local flagged_files=()
        while IFS= read -r -d '' file; do
            if scan_file_for_safety "$file"; then
                local sub_rel="${file#$local_path/}"
                flagged_files+=("$sub_rel|$MOSY_SAFETY_REASON")
            fi
        done < <(find "$local_path/" -maxdepth 2 \( -type f -o -type s -o -type p \) -print0 2>/dev/null)

        if [ ${#flagged_files[@]} -gt 0 ]; then
            ((TOTAL++))
            echo -e "${YELLOW}[WARN]${NC} $local_rel: Monolithic directory mounted over FUSE contains ${#flagged_files[@]} database/lock/volatile file(s):"
            local display_count=0
            for item in "${flagged_files[@]}"; do
                if [ $display_count -lt 3 ]; then
                    echo -e "      - ${item%%|*} (${item#*|})"
                    ((display_count++))
                fi
            done
            if [ ${#flagged_files[@]} -gt 3 ]; then
                echo -e "      ... and $(( ${#flagged_files[@]} - 3 )) more."
            fi

            if [ "$FIX_MODE" = true ]; then
                local revert_prompt="   Do you want to safely revert ~/$local_rel to a local directory? [y/N]: "
                local reply=""
                if [ -t 0 ]; then
                    read -r -p "$revert_prompt" reply
                else
                    if ! read -r reply; then
                        reply="n"
                    fi
                fi
                case "$reply" in
                    [Yy]*)
                        echo -e "   Reverting $local_rel to local directory..."
                        local source_dir
                        source_dir=$(readlink -f "$local_path")
                        if [ -e "$source_dir" ] && rm "$local_path" && cp -r "$source_dir" "$local_path"; then
                            update_map_remove_entry "$local_rel"
                            echo -e "${GREEN}[FIXED]${NC} Reverted $local_rel to local directory (unmanaged from FUSE)"
                            ((FIXED++))
                            ((OK++))
                        else
                            echo -e "${RED}[ERR]${NC} Failed to revert $local_rel"
                            ((ERR++))
                        fi
                        ;;
                    *)
                        echo -e "      Recommendation: Run 'mosy remove ~/$local_rel' to keep volatile data local."
                        ((WARN++))
                        ;;
                esac
            else
                ((WARN++))
            fi
        fi
    elif [ -L "$local_path" ]; then
        if scan_file_for_safety "$cloud_path"; then
            ((TOTAL++))
            echo -e "${YELLOW}[WARN]${NC} $local_rel: $MOSY_SAFETY_REASON mounted over FUSE"
            if [ "$FIX_MODE" = true ]; then
                local revert_prompt="   Do you want to safely revert ~/$local_rel to a local file? [y/N]: "
                local reply=""
                if [ -t 0 ]; then
                    read -r -p "$revert_prompt" reply
                else
                    if ! read -r reply; then
                        reply="n"
                    fi
                fi
                case "$reply" in
                    [Yy]*)
                        echo -e "   Reverting $local_rel to local file..."
                        local source_file
                        source_file=$(readlink -f "$local_path")
                        if [ -e "$source_file" ] && rm "$local_path" && cp -a "$source_file" "$local_path"; then
                            update_map_remove_entry "$local_rel"
                            echo -e "${GREEN}[FIXED]${NC} Reverted $local_rel to local file (unmanaged from FUSE)"
                            ((FIXED++))
                            ((OK++))
                        else
                            echo -e "${RED}[ERR]${NC} Failed to revert $local_rel"
                            ((ERR++))
                        fi
                        ;;
                    *)
                        echo -e "      Recommendation: Run 'mosy remove ~/$local_rel' to keep volatile data local."
                        ((WARN++))
                        ;;
                esac
            else
                ((WARN++))
            fi
        fi
    elif [ -d "$local_path" ] && [ -d "$cloud_path" ]; then
        local flagged_links=()
        while IFS= read -r -d '' link; do
            local target
            target=$(readlink "$link")
            if scan_file_for_safety "$target"; then
                local sub_rel="${link#$HOME/}"
                flagged_links+=("$sub_rel ($MOSY_SAFETY_REASON)")
            fi
        done < <(find "$local_path" -type l -print0 2>/dev/null)

        if [ ${#flagged_links[@]} -gt 0 ]; then
            ((TOTAL++))
            echo -e "${YELLOW}[WARN]${NC} $local_rel (directory): contains ${#flagged_links[@]} volatile symlink(s) mounted over FUSE:"
            for item in "${flagged_links[@]}"; do
                echo -e "      - $item"
            done
            if [ "$FIX_MODE" = true ]; then
                echo -e "      Recommendation: Remove unsafe symlinks or add them to .mosyignore."
            fi
            ((WARN++))
        fi
    fi
}

_doctor_check_safety_audit() {
    echo -e "\n--- Database & Lockfile Safety Audit ---"
    local initial_warn=$WARN
    if [ -f "$MOSY_MAP_FILE" ]; then
        foreach_mapping _doctor_check_safety_item
    fi
    if [ "$WARN" -eq "$initial_warn" ]; then
        ((TOTAL++))
        echo -e "${GREEN}[OK]${NC} No active databases, sockets, or lockfiles detected over FUSE"
        ((OK++))
    fi
}

cmd_doctor() {
    FIX_MODE=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --fix|-f)
                FIX_MODE=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    TOTAL=0
    OK=0
    WARN=0
    ERR=0
    FIXED=0

    _doctor_check_deps
    _doctor_check_mount_services
    _doctor_check_cloud_storage
    _doctor_check_mappings
    _doctor_check_safety_audit

    echo -e "\n--- Doctor Summary ---"
    echo -e "Total checks: $TOTAL"
    echo -e "${GREEN}OK: $OK${NC}"
    echo -e "${YELLOW}Warnings: $WARN${NC}"
    echo -e "${RED}Errors: $ERR${NC}"
    if [ "$FIX_MODE" = true ]; then
        echo -e "${GREEN}Fixed: $FIXED${NC}"
    fi

    if [ "$ERR" -gt 0 ]; then
        if [ "$FIX_MODE" = false ]; then
            echo -e "\nTip: Run 'mosy doctor --fix' to attempt automatic remediation of fixable issues."
        fi
        return 1
    fi

    return 0
}
