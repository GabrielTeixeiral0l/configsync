#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize counters
TOTAL=0
OK=0
WARN=0
ERR=0

status_callback() {
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
                [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${GREEN}[OK]${NC} $local_rel"
                ((OK++))
            else
                [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${RED}[ERR]${NC} $local_rel (Broken link: cloud source missing)"
                ((ERR++))
            fi
        else
            [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${RED}[ERR]${NC} $local_rel (Wrong target: points to $target)"
            ((ERR++))
        fi
    elif [ -d "$local_path" ] && [ -d "$cloud_path" ]; then
        # Check integrity of symlinks within granularly managed directories
        local dir_ok=true
        local broken_links=0
        while IFS= read -r -d '' link; do
            local target
            target=$(readlink "$link")
            if [[ "$target" == "$MOSY_PROFILE_DIR"* ]] && [ ! -e "$target" ]; then
                dir_ok=false
                ((broken_links++))
            fi
        done < <(find "$local_path" -type l -print0)

        if [ "$dir_ok" = true ]; then
            [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${GREEN}[OK]${NC} $local_rel (directory)"
            ((OK++))
        else
            [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${RED}[ERR]${NC} $local_rel ($broken_links broken links inside directory)"
            ((ERR++))
        fi
    else
        if [ -e "$cloud_path" ]; then
            [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${YELLOW}[WARN]${NC} $local_rel (Missing link: cloud source exists)"
            ((WARN++))
        else
            [ "$QUIET" != true ] && [ "$JSON_OUTPUT" != true ] && echo -e "${RED}[ERR]${NC} $local_rel (Both local and cloud sources missing)"
            ((ERR++))
        fi
    fi
}

cmd_status() {
    local JSON_OUTPUT=false
    local QUIET=false

    parse_filter_flags "$@"

    while [ $# -gt 0 ]; do
        case "$1" in
            --json|-j)
                JSON_OUTPUT=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --tag|-t|--group|-g)
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local is_mount_ok=false
    if is_mounted; then
        is_mount_ok=true
    fi

    local service_status
    if declare -F platform_service_status >/dev/null 2>&1; then
        service_status=$(platform_service_status 2>/dev/null | tr -d '\r\n')
    else
        service_status=$(systemctl --user is-active mosy-mount.service 2>/dev/null | tr -d '\r\n' || true)
    fi
    [ -z "$service_status" ] && service_status="inactive"
    local is_service_ok=false
    [ "$service_status" = "active" ] && is_service_ok=true

    TOTAL=0
    OK=0
    WARN=0
    ERR=0

    if [ -f "$MOSY_MAP_FILE" ]; then
        foreach_mapping status_callback
    fi

    local is_healthy=false
    if [ "$is_mount_ok" = true ] && [ "$ERR" -eq 0 ] && [ "$WARN" -eq 0 ]; then
        is_healthy=true
    fi

    if [ "$QUIET" = true ]; then
        if [ "$is_healthy" = true ]; then
            exit 0
        else
            exit 1
        fi
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        printf '{"profile":"%s","system":{"mounted":%s,"mount_point":"%s","service_active":%s,"service_status":"%s"},"files":{"total":%d,"ok":%d,"warn":%d,"err":%d},"healthy":%s}\n' \
            "$MOSY_PROFILE" "$is_mount_ok" "$MOSY_MOUNT_POINT" "$is_service_ok" "$service_status" "$TOTAL" "$OK" "$WARN" "$ERR" "$is_healthy"
        if [ "$is_healthy" = true ]; then
            exit 0
        else
            exit 1
        fi
    fi

    echo -e "--- System Status ---"
    
    if [ "$is_mount_ok" = true ]; then
        echo -e "Mount Point ($MOSY_MOUNT_POINT): ${GREEN}MOUNTED${NC}"
    else
        echo -e "Mount Point ($MOSY_MOUNT_POINT): ${RED}NOT MOUNTED${NC}"
    fi

    if [ "$is_service_ok" = true ]; then
        echo -e "Systemd Service (mosy-mount): ${GREEN}ACTIVE${NC}"
    else
        echo -e "Systemd Service (mosy-mount): ${YELLOW}INACTIVE ($service_status)${NC}"
    fi

    echo -e "\n--- File Integrity ---"
    
    if [ ! -f "$MOSY_MAP_FILE" ]; then
        echo "No items are currently being managed (map file missing)."
    else
        TOTAL=0
        OK=0
        WARN=0
        ERR=0
        foreach_mapping status_callback
    fi

    echo -e "\n--- Summary ---"
    echo -e "Total: $TOTAL"
    echo -e "${GREEN}OK: $OK${NC}"
    echo -e "${YELLOW}Warnings: $WARN${NC}"
    echo -e "${RED}Errors: $ERR${NC}"
}
