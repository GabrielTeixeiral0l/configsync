#!/bin/bash

cmd_add() {
    check_mount
    local RAW_TARGET=""
    local LINK_TARGET=""
    local FORCE=false
    local SCAN_SECRETS_OVERRIDE=""
    local SAFETY_GUARD_OVERRIDE=""
    parse_filter_flags "$@"
    local TAGS="$MOSY_FILTER_TAG"
    local ITEM_GROUPS="$MOSY_FILTER_GROUP"

    while [ $# -gt 0 ]; do
        case "$1" in
            --tag|-t|--group|-g)
                shift 2
                ;;
            --link|--target|--to)
                LINK_TARGET="$2"
                shift 2
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --scan-secrets|--scan)
                SCAN_SECRETS_OVERRIDE="true"
                shift
                ;;
            --no-scan)
                SCAN_SECRETS_OVERRIDE="false"
                shift
                ;;
            --guard)
                SAFETY_GUARD_OVERRIDE="true"
                shift
                ;;
            --no-guard)
                SAFETY_GUARD_OVERRIDE="false"
                shift
                ;;
            *)
                [ -z "$RAW_TARGET" ] && RAW_TARGET="$1"
                shift
                ;;
        esac
    done

    if [ -n "$LINK_TARGET" ] && [ -n "$RAW_TARGET" ]; then
        source "${SCRIPT_DIR}/src/commands/link.sh"
        cmd_link "$RAW_TARGET" "$LINK_TARGET" ${TAGS:+--tag "$TAGS"} ${ITEM_GROUPS:+--group "$ITEM_GROUPS"} ${FORCE:+--force}
        return $?
    fi

    if [ -z "$RAW_TARGET" ]; then
        echo "Usage: mosy add <file_or_directory> [--tag <tags>] [--group <groups>] [--scan-secrets] [--no-guard] [--force]"
        exit 1
    fi

    if [ -L "$RAW_TARGET" ]; then
        echo "Warning: $RAW_TARGET is already a symbolic link."
        exit 0
    fi

    if [ ! -e "$RAW_TARGET" ] && [ ! -S "$RAW_TARGET" ] && [ ! -p "$RAW_TARGET" ]; then
        echo "Error: $RAW_TARGET does not exist."
        exit 1
    fi

    TARGET=$(realpath "$RAW_TARGET")
    if [[ "$TARGET" != "$HOME"* ]]; then
        echo "Error: Target must be within your home directory ($HOME)."
        exit 1
    fi

    REL_PATH=$(get_relative_home_path "$RAW_TARGET")
    CLOUD_DEST="$MOSY_PROFILE_DIR/$REL_PATH"

    local SHOULD_SCAN="${SCAN_SECRETS_OVERRIDE:-$MOSY_SCAN_SECRETS}"
    local SHOULD_GUARD="${SAFETY_GUARD_OVERRIDE:-$MOSY_SAFETY_GUARD}"

    echo "Syncing $REL_PATH..."

    if [ -d "$TARGET" ]; then
        local skipped_safety_files=()
        local skipped_secret_files=()

        # 1. Safety Guard scan (Databases, Locks, Sockets, Caches)
        if [ "$SHOULD_GUARD" = "true" ] && [ "$FORCE" != "true" ]; then
            local flagged_safety_items=()
            while IFS= read -r -d '' file; do
                if is_ignored "$file"; then
                    continue
                fi
                if [ -L "$file" ]; then
                    continue
                fi
                if scan_file_for_safety "$file"; then
                    local rel_file="${file#$TARGET/}"
                    flagged_safety_items+=("$rel_file|$MOSY_SAFETY_REASON")
                fi
            done < <(find "$TARGET" \( -type f -o -type s -o -type p \) -print0 2>/dev/null)

            if [ ${#flagged_safety_items[@]} -gt 0 ]; then
                MOSY_DIR_SAFETY_ACTION=""
                prompt_safety_directory "$TARGET" "${flagged_safety_items[@]}"
                if [ "$MOSY_DIR_SAFETY_ACTION" = "skip" ]; then
                    for item in "${flagged_safety_items[@]}"; do
                        local sfile="${item%%|*}"
                        skipped_safety_files+=("$sfile")
                    done
                fi
            fi
        fi

        # 2. Secret Leak scan
        if [ "$SHOULD_SCAN" = "true" ] && [ "$FORCE" != "true" ]; then
            local flagged_secret_items=()
            while IFS= read -r -d '' file; do
                if is_ignored "$file"; then
                    continue
                fi
                if [ -L "$file" ]; then
                    continue
                fi
                local rel_file="${file#$TARGET/}"
                local already_skipped=false
                for sf in "${skipped_safety_files[@]}"; do
                    if [ "$rel_file" = "$sf" ]; then
                        already_skipped=true
                        break
                    fi
                done
                [ "$already_skipped" = true ] && continue

                if scan_file_for_secrets "$file"; then
                    flagged_secret_items+=("$rel_file|$MOSY_SECRET_REASON")
                fi
            done < <(find "$TARGET" -type f -print0 2>/dev/null)

            if [ ${#flagged_secret_items[@]} -gt 0 ]; then
                MOSY_DIR_SECRET_ACTION=""
                prompt_secret_directory "$TARGET" "${flagged_secret_items[@]}"
                if [ "$MOSY_DIR_SECRET_ACTION" = "skip" ]; then
                    for item in "${flagged_secret_items[@]}"; do
                        local sfile="${item%%|*}"
                        skipped_secret_files+=("$sfile")
                    done
                fi
            fi
        fi

        # Sync directory granularly without modifying or deleting local ignored/skipped files
        mkdir -p "$CLOUD_DEST"
        
        while IFS= read -r -d '' file; do
            local rel_file="${file#$TARGET/}"
            local cloud_file="$CLOUD_DEST/$rel_file"

            if is_ignored "$file"; then
                log_debug "Ignoring local file: $rel_file"
                continue
            fi

            # Check if file was skipped during safety guard or secret detection
            local is_skipped_safety=false
            for sf in "${skipped_safety_files[@]}"; do
                if [ "$rel_file" = "$sf" ]; then
                    is_skipped_safety=true
                    break
                fi
            done
            if [ "$is_skipped_safety" = true ]; then
                log_info "Keeping file local (skipped): $rel_file"
                continue
            fi

            local is_skipped_secret=false
            for sf in "${skipped_secret_files[@]}"; do
                if [ "$rel_file" = "$sf" ]; then
                    is_skipped_secret=true
                    break
                fi
            done
            if [ "$is_skipped_secret" = true ]; then
                log_info "Skipping secret file (kept local): $rel_file"
                continue
            fi

            if [ -L "$file" ]; then
                continue
            fi

            mkdir -p "$(dirname "$cloud_file")"
            if [ -e "$cloud_file" ]; then
                echo "Warning: Cloud version already exists at $rel_file. Backing up local copy."
                mosy_backup "$file" || continue
            else
                mv "$file" "$cloud_file" || continue
            fi
            ln -s "$cloud_file" "$file"
        done < <(find "$TARGET" \( -type f -o -type s -o -type p \) -print0 2>/dev/null)
    else
        if [ "$SHOULD_GUARD" = "true" ] && [ "$FORCE" != "true" ]; then
            if scan_file_for_safety "$TARGET"; then
                prompt_safety_single "$TARGET" "$MOSY_SAFETY_CATEGORY" "$MOSY_SAFETY_REASON"
            fi
        fi

        if [ "$SHOULD_SCAN" = "true" ] && [ "$FORCE" != "true" ]; then
            if scan_file_for_secrets "$TARGET"; then
                prompt_secret_single "$TARGET" "$MOSY_SECRET_REASON"
            fi
        fi

        local CLOUD_DEST_DIR
        CLOUD_DEST_DIR=$(dirname "$CLOUD_DEST")
        mkdir -p "$CLOUD_DEST_DIR"

        if [ -e "$CLOUD_DEST" ]; then
            echo "Warning: A version already exists in the cloud at $REL_PATH. Backing up local copy."
            mosy_backup "$TARGET" || exit 1
        else
            mv "$TARGET" "$CLOUD_DEST" || exit 1
        fi
        ln -s "$CLOUD_DEST" "$TARGET"
    fi

    touch "$MOSY_MAP_FILE"
    update_map_remove_entry "$REL_PATH"
    echo "$REL_PATH|$REL_PATH|$TAGS|$ITEM_GROUPS" >> "$MOSY_MAP_FILE"

    echo "Success! $REL_PATH is now synced."
}
