#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

cmd_info() {
    local json_output=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --json|-j)
                json_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # System metrics
    local host_name os_name os_arch kernel_ver os_desc
    host_name=$(hostname 2>/dev/null || uname -n)
    os_name=$(uname -s 2>/dev/null || echo "Unknown")
    os_arch=$(uname -m 2>/dev/null || echo "Unknown")
    kernel_ver=$(uname -r 2>/dev/null || echo "Unknown")

    if [ -f /etc/os-release ]; then
        os_desc=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    fi
    [ -z "$os_desc" ] && os_desc="$os_name $kernel_ver ($os_arch)"

    # Service status
    local service_status="not found"
    if declare -F platform_service_status >/dev/null 2>&1; then
        service_status=$(platform_service_status | head -n 1)
        [ -z "$service_status" ] && service_status="inactive"
    elif command -v systemctl >/dev/null 2>&1; then
        service_status=$(systemctl --user is-active mosy-mount.service 2>/dev/null | head -n 1)
        [ -z "$service_status" ] && service_status="inactive"
    elif command -v launchctl >/dev/null 2>&1; then
        if launchctl list 2>/dev/null | grep -q "com.mountsync.rclone"; then
            service_status="active"
        else
            service_status="inactive"
        fi
    fi

    # Mount status
    local is_mount_active="false"
    local mount_label="NOT MOUNTED"
    if is_mounted; then
        is_mount_active="true"
        mount_label="MOUNTED"
    fi

    # Item metrics
    local total_managed=0
    local valid_links=0
    local broken_links=0
    local missing_links=0
    local lost_items=0
    local all_tags=()
    local all_groups=()

    if [ -f "$MOSY_MAP_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            IFS="|" read -r local_rel cloud_rel tags groups <<< "$line"
            [ -z "$local_rel" ] && continue

            ((total_managed++))

            local local_path="${HOME}/${local_rel}"
            local cloud_path="${MOSY_PROFILE_DIR}/${cloud_rel}"

            if [ -L "$local_path" ]; then
                local target
                target=$(readlink "$local_path")
                if [ "$target" == "$cloud_path" ]; then
                    if [ -e "$cloud_path" ]; then
                        ((valid_links++))
                    else
                        ((broken_links++))
                    fi
                else
                    ((broken_links++))
                fi
            elif [ -d "$local_path" ] && [ -d "$cloud_path" ]; then
                local dir_ok=true
                while IFS= read -r -d '' link; do
                    local target
                    target=$(readlink "$link")
                    if [[ "$target" == "$MOSY_PROFILE_DIR"* ]] && [ ! -e "$target" ]; then
                        dir_ok=false
                        break
                    fi
                done < <(find "$local_path" -type l -print0 2>/dev/null)

                if [ "$dir_ok" = true ]; then
                    ((valid_links++))
                else
                    ((broken_links++))
                fi
            else
                if [ -e "$cloud_path" ]; then
                    ((missing_links++))
                else
                    ((lost_items++))
                fi
            fi

            if [ -n "$tags" ]; then
                IFS=',' read -ra t_arr <<< "$tags"
                for t in "${t_arr[@]}"; do
                    [ -n "$t" ] && all_tags+=("$t")
                done
            fi

            if [ -n "$groups" ]; then
                IFS=',' read -ra g_arr <<< "$groups"
                for g in "${g_arr[@]}"; do
                    [ -n "$g" ] && all_groups+=("$g")
                done
            fi
        done < "$MOSY_MAP_FILE"
    fi

    local unique_tags_count=0
    if [ ${#all_tags[@]} -gt 0 ]; then
        unique_tags_count=$(printf "%s\n" "${all_tags[@]}" | sort -u | grep -v '^$' | wc -l)
    fi

    local unique_groups_count=0
    if [ ${#all_groups[@]} -gt 0 ]; then
        unique_groups_count=$(printf "%s\n" "${all_groups[@]}" | sort -u | grep -v '^$' | wc -l)
    fi

    if [ "$json_output" = true ]; then
        cat <<EOF
{
  "system": {
    "hostname": "$host_name",
    "os": "$os_name",
    "os_details": "$os_desc",
    "kernel": "$kernel_ver",
    "architecture": "$os_arch"
  },
  "configuration": {
    "profile": "$MOSY_PROFILE",
    "remote_name": "$MOSY_REMOTE_NAME",
    "mount_point": "$MOSY_MOUNT_POINT",
    "mount_status": "$mount_label",
    "is_mounted": $is_mount_active,
    "service_status": "$service_status",
    "vault_path": "$MOSY_PROFILE_DIR",
    "sync_map_file": "$MOSY_MAP_FILE",
    "vfs_cache": "$MOSY_VFS_CACHE"
  },
  "metrics": {
    "total_managed": $total_managed,
    "valid_links": $valid_links,
    "broken_links": $broken_links,
    "missing_links": $missing_links,
    "lost_items": $lost_items,
    "unique_tags": $unique_tags_count,
    "unique_groups": $unique_groups_count
  }
}
EOF
        return 0
    fi

    echo -e "${BOLD}=== MountSync Environment Overview ===${NC}"

    echo -e "\n--- System ---"
    printf "%-18s %s\n" "Hostname:" "$host_name"
    printf "%-18s %s\n" "OS:" "$os_desc"
    printf "%-18s %s\n" "Architecture:" "$os_arch"

    echo -e "\n--- Configuration ---"
    printf "%-18s %s\n" "Active Profile:" "$MOSY_PROFILE"
    printf "%-18s %s\n" "Cloud Remote:" "${MOSY_REMOTE_NAME:-[Not configured]}"
    
    if [ "$is_mount_active" = "true" ]; then
        printf "%-18s %s %b\n" "Mount Point:" "$MOSY_MOUNT_POINT" "${GREEN}[MOUNTED]${NC}"
    else
        printf "%-18s %s %b\n" "Mount Point:" "$MOSY_MOUNT_POINT" "${RED}[NOT MOUNTED]${NC}"
    fi

    if [ "$service_status" = "active" ]; then
        printf "%-18s %b\n" "Service Status:" "${GREEN}ACTIVE${NC}"
    elif [ "$service_status" = "inactive" ]; then
        printf "%-18s %b\n" "Service Status:" "${YELLOW}INACTIVE${NC}"
    else
        printf "%-18s %s\n" "Service Status:" "$service_status"
    fi

    printf "%-18s %s\n" "Vault Path:" "$MOSY_PROFILE_DIR"
    printf "%-18s %s\n" "Sync Map:" "$MOSY_MAP_FILE"
    printf "%-18s %s\n" "VFS Cache Mode:" "$MOSY_VFS_CACHE"

    echo -e "\n--- Managed Items ---"
    printf "%-18s %s\n" "Total Managed:" "$total_managed"
    printf "%-18s %b\n" "Valid Links:" "${GREEN}${valid_links}${NC}"
    if [ "$broken_links" -gt 0 ]; then
        printf "%-18s %b\n" "Broken Links:" "${RED}${broken_links}${NC}"
    else
        printf "%-18s %s\n" "Broken Links:" "$broken_links"
    fi
    if [ "$missing_links" -gt 0 ]; then
        printf "%-18s %b\n" "Missing Links:" "${YELLOW}${missing_links}${NC}"
    else
        printf "%-18s %s\n" "Missing Links:" "$missing_links"
    fi
    if [ "$lost_items" -gt 0 ]; then
        printf "%-18s %b\n" "Lost Items:" "${RED}${lost_items}${NC}"
    fi
    printf "%-18s %s\n" "Unique Tags:" "$unique_tags_count"
    printf "%-18s %s\n" "Unique Groups:" "$unique_groups_count"

    return 0
}
