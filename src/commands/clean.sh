#!/bin/bash

_parse_duration_seconds() {
    local str="$1"
    if [[ "$str" =~ ^([0-9]+)d$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 86400 ))
    elif [[ "$str" =~ ^([0-9]+)h$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 3600 ))
    elif [[ "$str" =~ ^([0-9]+)m$ ]]; then
        echo $(( ${BASH_REMATCH[1]} * 60 ))
    elif [[ "$str" =~ ^([0-9]+)s$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$str" =~ ^[0-9]+$ ]]; then
        # Default to days if just a number
        echo $(( str * 86400 ))
    else
        echo ""
    fi
}

_format_bytes_human() {
    local bytes="$1"
    if [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.1f MB\", $bytes/1048576}"
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f KB\", $bytes/1024}"
    else
        echo "${bytes} B"
    fi
}

_get_path_size_bytes() {
    local target="$1"
    if [ -d "$target" ]; then
        du -sb "$target" 2>/dev/null | awk '{print $1}' || du -sk "$target" 2>/dev/null | awk '{print $1 * 1024}' || echo 0
    elif [ -f "$target" ]; then
        stat -c %s "$target" 2>/dev/null || stat -f %z "$target" 2>/dev/null || wc -c < "$target" || echo 0
    else
        echo 0
    fi
}

cmd_clean() {
    local TARGET_PATH=""
    local OLDER_THAN=""
    local DRY_RUN=false
    local FORCE=false

    parse_filter_flags "$@"

    while [ $# -gt 0 ]; do
        case "$1" in
            --older-than)
                OLDER_THAN="$2"
                shift 2
                ;;
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --tag|-t|--group|-g)
                shift 2
                ;;
            *)
                [ -z "$TARGET_PATH" ] && TARGET_PATH="$1"
                shift
                ;;
        esac
    done

    local cut_epoch=""
    if [ -n "$OLDER_THAN" ]; then
        local dur_sec
        dur_sec=$(_parse_duration_seconds "$OLDER_THAN")
        if [ -z "$dur_sec" ]; then
            echo "Error: Invalid duration format for --older-than: '$OLDER_THAN' (e.g. 30d, 7d, 24h)." >&2
            exit 1
        fi
        local now_epoch
        now_epoch=$(date +%s)
        cut_epoch=$(( now_epoch - dur_sec ))
    fi

    local target_items=()

    if [ -n "$TARGET_PATH" ]; then
        local target_rel
        target_rel=$(get_relative_home_path "$TARGET_PATH" 2>/dev/null || echo "$TARGET_PATH")
        target_items+=("$target_rel")
    else
        _collect_item() {
            local l_rel="$1"
            target_items+=("$l_rel")
        }
        foreach_mapping _collect_item
    fi

    if [ ${#target_items[@]} -eq 0 ]; then
        echo "No managed dotfiles found to clean in profile '${MOSY_PROFILE}'."
        exit 0
    fi

    local candidate_files=()
    local candidate_sizes=()
    local total_bytes=0

    for item_rel in "${target_items[@]}"; do
        local local_path="${HOME}/${item_rel}"
        local parent_dir
        parent_dir=$(dirname "$local_path")
        local base_name
        base_name=$(basename "$local_path")

        [ ! -d "$parent_dir" ] && continue

        while IFS= read -r snap_file; do
            [ -z "$snap_file" ] && continue
            [ ! -e "$snap_file" ] && [ ! -L "$snap_file" ] && continue

            # Safety check: Never delete the active path itself
            if [ "$snap_file" = "$local_path" ]; then
                continue
            fi

            # Check age if --older-than is specified
            if [ -n "$cut_epoch" ]; then
                local mtime
                mtime=$(stat -c %Y "$snap_file" 2>/dev/null || stat -f %m "$snap_file" 2>/dev/null || echo 0)
                if [ "$mtime" -gt "$cut_epoch" ]; then
                    continue
                fi
            fi

            local f_size
            f_size=$(_get_path_size_bytes "$snap_file")
            candidate_files+=("$snap_file")
            candidate_sizes+=("$f_size")
            total_bytes=$(( total_bytes + f_size ))
        done < <(find "$parent_dir" -maxdepth 1 \( -name "${base_name}.bak_*" -o -name "${base_name}.backup_*" -o -name "${base_name}${MOSY_BACKUP_EXT}_*" \) 2>/dev/null | sort -u)
    done

    if [ ${#candidate_files[@]} -eq 0 ]; then
        echo "No obsolete backups found matching criteria."
        exit 0
    fi

    local human_total
    human_total=$(_format_bytes_human "$total_bytes")

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] The following backup snapshot(s) would be removed:"
        local idx=0
        for f in "${candidate_files[@]}"; do
            local sz="${candidate_sizes[$idx]}"
            local sz_human
            sz_human=$(_format_bytes_human "$sz")
            local rel_display="${f#$HOME/}"
            echo "  - ~/$rel_display ($sz_human)"
            ((idx++))
        done
        echo "Total: ${#candidate_files[@]} file(s), $human_total reclaimable space."
        exit 0
    fi

    if [ "$FORCE" != true ] && [ -t 0 ] && [ -z "${MOSY_NO_TTY:-}" ]; then
        echo "The following backup snapshot(s) will be deleted:"
        local idx=0
        for f in "${candidate_files[@]}"; do
            local sz="${candidate_sizes[$idx]}"
            local sz_human
            sz_human=$(_format_bytes_human "$sz")
            local rel_display="${f#$HOME/}"
            echo "  - ~/$rel_display ($sz_human)"
            ((idx++))
        done
        echo "Total reclaimable space: $human_total"

        local confirm=""
        read -r -p "Delete these ${#candidate_files[@]} backup snapshot(s)? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
            echo "Clean operation aborted."
            exit 0
        fi
    fi

    local deleted_count=0
    for f in "${candidate_files[@]}"; do
        rm -rf "$f"
        ((deleted_count++))
    done

    echo "Success! Removed $deleted_count backup snapshot(s) (freed $human_total)."
}
