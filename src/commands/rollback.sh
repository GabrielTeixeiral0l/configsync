_extract_snapshot_timestamp() {
    local snap_name="$1"
    if [[ "$snap_name" =~ \.(bak|backup)_([0-9_]+)$ ]]; then
        echo "${BASH_REMATCH[2]}"
    elif [[ "$snap_name" =~ \.(bak|backup)$ ]]; then
        echo "legacy"
    else
        echo "${snap_name##*_}"
    fi
}

# Format timestamp string YYYYMMDD_HHMMSS or Unix epoch timestamp into human readable format
_format_snapshot_datetime() {
    local raw_ts="$1"
    if [[ "$raw_ts" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
    elif [[ "$raw_ts" =~ ^[0-9]{9,12}$ ]]; then
        date -d @"$raw_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$raw_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$raw_ts"
    else
        echo "$raw_ts"
    fi
}

cmd_rollback() {
    local TARGET_ARG=""
    local SNAPSHOT_ARG=""
    local FORCE=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f)
                FORCE=true
                shift
                ;;
            *)
                if [ -z "$TARGET_ARG" ]; then
                    TARGET_ARG="$1"
                elif [ -z "$SNAPSHOT_ARG" ]; then
                    SNAPSHOT_ARG="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$TARGET_ARG" ]; then
        echo "Usage: mosy rollback <path> [timestamp_or_index] [--force]"
        exit 1
    fi

    local local_path=""
    if [ "${TARGET_ARG:0:2}" = "~/" ]; then
        local_path="${HOME}/${TARGET_ARG:2}"
    elif [ "${TARGET_ARG:0:1}" = "/" ]; then
        local_path="$TARGET_ARG"
    else
        local_path="${HOME}/${TARGET_ARG}"
    fi
    local rel_path="${local_path#$HOME/}"
    local parent_dir
    parent_dir=$(dirname "$local_path")
    local base_name
    base_name=$(basename "$local_path")

    if [ ! -d "$parent_dir" ]; then
        echo "Error: Directory $parent_dir does not exist."
        exit 1
    fi

    local snaps=()
    while IFS= read -r snap_file; do
        [ -n "$snap_file" ] && snaps+=("$snap_file")
    done < <(find "$parent_dir" -maxdepth 1 \( -name "${base_name}.bak*" -o -name "${base_name}.backup*" -o -name "${base_name}${MOSY_BACKUP_EXT}*" \) 2>/dev/null | sort -r)

    if [ ${#snaps[@]} -eq 0 ]; then
        echo "Error: No backup snapshots found for ~/$rel_path."
        exit 1
    fi

    local selected_snap=""

    if [ -n "$SNAPSHOT_ARG" ]; then
        # Check if SNAPSHOT_ARG is an integer index (1-based)
        if [[ "$SNAPSHOT_ARG" =~ ^[0-9]+$ ]] && [ "$SNAPSHOT_ARG" -ge 1 ] && [ "$SNAPSHOT_ARG" -le ${#snaps[@]} ]; then
            selected_snap="${snaps[$((SNAPSHOT_ARG - 1))]}"
        else
            # Try to match by timestamp or filename substring
            for snap in "${snaps[@]}"; do
                if [[ "$snap" == *"$SNAPSHOT_ARG"* ]]; then
                    selected_snap="$snap"
                    break
                fi
            done
        fi

        if [ -z "$selected_snap" ]; then
            echo "Error: Snapshot '$SNAPSHOT_ARG' not found for ~/$rel_path."
            echo "Run 'mosy history ~/$rel_path' to view available snapshots."
            exit 1
        fi
    else
        # Interactive selection if TTY, otherwise pick the latest snapshot
        if [ -t 0 ] && [ -z "${MOSY_NO_TTY:-}" ] && [ "$FORCE" != true ] && [ ${#snaps[@]} -gt 1 ]; then
            echo "Available snapshots for ~/$rel_path:"
            local idx=1
            for snap in "${snaps[@]}"; do
                local snap_name
                snap_name=$(basename "$snap")
                local raw_ts
                raw_ts=$(_extract_snapshot_timestamp "$snap_name")
                local dt
                dt=$(_format_snapshot_datetime "$raw_ts")
                echo "  [$idx] $dt  ($snap_name)"
                ((idx++))
            done

            local choice=""
            read -r -p "Select snapshot to restore [1-${#snaps[@]}, default: 1]: " choice
            if [ -z "$choice" ]; then
                selected_snap="${snaps[0]}"
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#snaps[@]} ]; then
                selected_snap="${snaps[$((choice - 1))]}"
            else
                echo "Invalid selection. Aborting rollback."
                exit 1
            fi
        else
            selected_snap="${snaps[0]}"
        fi
    fi

    if [ ! -e "$selected_snap" ]; then
        echo "Error: Snapshot file $selected_snap is missing."
        exit 1
    fi

    echo "Rolling back ~/$rel_path to $(basename "$selected_snap")..."

    # 1. Create pre-rollback safety backup of current state
    if [ -e "$local_path" ] || [ -L "$local_path" ]; then
        local pre_rollback_backup
        pre_rollback_backup=$(generate_backup_path "$local_path")
        if [ -L "$local_path" ]; then
            local cloud_target
            cloud_target=$(readlink -f "$local_path" 2>/dev/null || true)
            if [ -e "$cloud_target" ]; then
                if [ -d "$cloud_target" ]; then
                    cp -r "$cloud_target" "$pre_rollback_backup"
                else
                    cp "$cloud_target" "$pre_rollback_backup"
                fi
            fi
        else
            if [ -d "$local_path" ]; then
                cp -r "$local_path" "$pre_rollback_backup"
            else
                cp "$local_path" "$pre_rollback_backup"
            fi
        fi
        log_info "Created safety backup before rollback: $(basename "$pre_rollback_backup")"
    fi

    # 2. Restore snapshot to target
    if [ -L "$local_path" ]; then
        local cloud_target
        cloud_target=$(readlink -f "$local_path" 2>/dev/null || true)
        if [ -n "$cloud_target" ] && [ -d "$cloud_target" ]; then
            rm -rf "$cloud_target"
            cp -r "$selected_snap" "$cloud_target"
        elif [ -n "$cloud_target" ]; then
            cp "$selected_snap" "$cloud_target"
        else
            # Dangling symlink: recreate destination from profile
            local cloud_dest="${MOSY_PROFILE_DIR}/${rel_path}"
            mkdir -p "$(dirname "$cloud_dest")"
            if [ -d "$selected_snap" ]; then
                cp -r "$selected_snap" "$cloud_dest"
            else
                cp "$selected_snap" "$cloud_dest"
            fi
            rm -f "$local_path"
            ln -s "$cloud_dest" "$local_path"
        fi
    else
        rm -rf "$local_path"
        if [ -d "$selected_snap" ]; then
            cp -r "$selected_snap" "$local_path"
        else
            cp "$selected_snap" "$local_path"
        fi
    fi

    echo "Success! Rolled back ~/$rel_path to $(basename "$selected_snap")."
}
