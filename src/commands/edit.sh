#!/bin/bash

_find_editor_binary() {
    local candidate="${VISUAL:-${EDITOR:-}}"
    if [ -n "$candidate" ] && command -v "$candidate" >/dev/null 2>&1; then
        echo "$candidate"
        return 0
    fi
    for fallback in nano vim vi ed; do
        if command -v "$fallback" >/dev/null 2>&1; then
            echo "$fallback"
            return 0
        fi
    done
    echo "${VISUAL:-${EDITOR:-nano}}"
}

_is_folder_capable_editor() {
    local editor_name
    editor_name=$(basename "$1")
    case "$editor_name" in
        code|code-insiders|cursor|zed|atom|subl|sublime_text)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_is_editable_text_file() {
    local file="$1"
    [ -e "$file" ] || [ -L "$file" ] || return 1
    [ -d "$file" ] && return 0
    [ -r "$file" ] || return 1

    # Empty files are editable
    [ ! -s "$file" ] && return 0

    # 1. Fast extension filter for known binary / media formats
    local base_name
    base_name=$(basename "$file")
    case "$base_name" in
        *.png|*.jpg|*.jpeg|*.gif|*.ico|*.webp|*.mp3|*.ogg|*.wav|*.flac|*.m4a|*.mp4|*.mkv|*.avi|*.pdf|*.zip|*.tar*|*.gz|*.xz|*.7z|*.sqlite*|*.db*|*.bin|*.iso|*.pyc|*.so|*.dylib|*.exe)
            return 1
            ;;
    esac

    # 2. Heuristic using 'file' utility if available
    if command -v file >/dev/null 2>&1; then
        local mime
        mime=$(file -b -L --mime-type "$file" 2>/dev/null || true)
        case "$mime" in
            text/*|application/json|application/xml|application/javascript|application/x-sh|application/x-shellscript|application/toml|application/yaml|application/x-yaml|inode/x-empty)
                return 0
                ;;
            *)
                if file -b -L "$file" 2>/dev/null | grep -qi "text"; then
                    return 0
                fi
                return 1
                ;;
        esac
    fi

    # 3. Fallback: check for null byte in first 512 bytes
    local c_total c_no_null
    c_total=$(head -c 512 "$file" 2>/dev/null | wc -c)
    c_no_null=$(head -c 512 "$file" 2>/dev/null | tr -d '\000' | wc -c)
    if [ "$c_total" -ne "$c_no_null" ]; then
        return 1
    fi

    return 0
}

cmd_edit() {
    local QUERY=""
    local NO_BACKUP=false

    parse_filter_flags "$@"

    while [ $# -gt 0 ]; do
        case "$1" in
            --no-backup)
                NO_BACKUP=true
                shift
                ;;
            --tag|-t|--group|-g)
                shift 2
                ;;
            *)
                [ -z "$QUERY" ] && QUERY="$1"
                shift
                ;;
        esac
    done

    local managed_roots=()
    _collect_managed_item() {
        local l_rel="$1"
        managed_roots+=("$l_rel")
    }
    foreach_mapping _collect_managed_item

    if [ ${#managed_roots[@]} -eq 0 ]; then
        echo "Error: No managed dotfiles found in profile '${MOSY_PROFILE}'." >&2
        exit 1
    fi

    local selected_item=""

    if [ -n "$QUERY" ]; then
        local query_rel
        query_rel=$(get_relative_home_path "$QUERY" 2>/dev/null || echo "$QUERY")

        # 1. Exact match check against top-level roots
        for item in "${managed_roots[@]}"; do
            if [ "$item" = "$query_rel" ] || [ "$item" = "$QUERY" ]; then
                selected_item="$item"
                break
            fi
        done

        # 2. Substring / partial match check against top-level roots
        local matches=()
        if [ -z "$selected_item" ]; then
            local lower_query
            lower_query=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')

            for item in "${managed_roots[@]}"; do
                local lower_item
                lower_item=$(echo "$item" | tr '[:upper:]' '[:lower:]')
                if [[ "$lower_item" == *"$lower_query"* ]]; then
                    matches+=("$item")
                fi
            done

            # 3. If no top-level matches, search inside managed directories (lazy scan)
            if [ ${#matches[@]} -eq 0 ]; then
                for root in "${managed_roots[@]}"; do
                    local root_path="${HOME}/${root}"
                    if [ -d "$root_path" ]; then
                        while IFS= read -r sub_file; do
                            [ -z "$sub_file" ] && continue
                            [ -d "$sub_file" ] && continue
                            local sub_rel="${sub_file#$HOME/}"
                            local lower_sub
                            lower_sub=$(echo "$sub_rel" | tr '[:upper:]' '[:lower:]')
                            if [[ "$lower_sub" == *"$lower_query"* ]]; then
                                if _is_editable_text_file "$sub_file"; then
                                    matches+=("$sub_rel")
                                fi
                            fi
                        done < <(find "$root_path/" -maxdepth 3 \( -type f -o -type l \) ! -path '*/.git/*' 2>/dev/null | sort)
                    fi
                done
            fi

            if [ ${#matches[@]} -eq 1 ]; then
                selected_item="${matches[0]}"
            elif [ ${#matches[@]} -gt 1 ]; then
                if [ -t 0 ] && [ -z "${MOSY_NO_TTY:-}" ]; then
                    echo "Multiple items match '$QUERY':"
                    local idx=1
                    for m in "${matches[@]}"; do
                        echo "  [$idx] ~/$m"
                        ((idx++))
                    done
                    local choice=""
                    read -r -p "Select item to edit [1-${#matches[@]}, default: 1]: " choice
                    if [ -z "$choice" ]; then
                        selected_item="${matches[0]}"
                    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#matches[@]} ]; then
                        selected_item="${matches[$((choice - 1))]}"
                    else
                        echo "Invalid selection. Aborting." >&2
                        exit 1
                    fi
                else
                    selected_item="${matches[0]}"
                fi
            fi
        fi

        if [ -z "$selected_item" ]; then
            echo "Error: No managed text dotfile found matching '$QUERY'." >&2
            echo "Run 'mosy list' to view all managed items." >&2
            exit 1
        fi
    else
        # No query supplied -> present top-level items
        if [ -t 0 ] && [ -z "${MOSY_NO_TTY:-}" ] && [ ${#managed_roots[@]} -gt 1 ]; then
            echo "Select a managed dotfile to edit:"
            local idx=1
            for item in "${managed_roots[@]}"; do
                local is_dir=""
                [ -d "${HOME}/${item}" ] && is_dir=" (directory)"
                echo "  [$idx] ~/${item}${is_dir}"
                ((idx++))
            done
            local choice=""
            read -r -p "Select item [1-${#managed_roots[@]}, default: 1]: " choice
            if [ -z "$choice" ]; then
                selected_item="${managed_roots[0]}"
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#managed_roots[@]} ]; then
                selected_item="${managed_roots[$((choice - 1))]}"
            else
                echo "Invalid selection. Aborting." >&2
                exit 1
            fi
        else
            selected_item="${managed_roots[0]}"
        fi
    fi

    local target_path="${HOME}/${selected_item}"
    if [ ! -e "$target_path" ] && [ ! -L "$target_path" ]; then
        echo "Error: Target file ~/$selected_item does not exist on disk." >&2
        exit 1
    fi

    local editor_cmd
    editor_cmd=$(_find_editor_binary)

    # If target is a directory and editor is terminal/file-based, prompt for editable text files inside
    if [ -d "$target_path" ] && ! _is_folder_capable_editor "$editor_cmd"; then
        local inner_files=()
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [ -d "$f" ] && continue
            if _is_editable_text_file "$f"; then
                inner_files+=("$f")
            fi
        done < <(find "$target_path/" -maxdepth 3 \( -type f -o -type l \) ! -path '*/.git/*' 2>/dev/null | sort)

        if [ ${#inner_files[@]} -eq 0 ]; then
            echo "Error: ~/$selected_item is a directory containing no editable text files." >&2
            exit 1
        fi

        if [ -t 0 ] && [ -z "${MOSY_NO_TTY:-}" ]; then
            echo "~/$selected_item is a directory. Select a text file inside to edit:"
            local f_idx=1
            for f in "${inner_files[@]}"; do
                local f_rel="${f#$HOME/}"
                echo "  [$f_idx] ~/$f_rel"
                ((f_idx++))
            done

            local f_choice=""
            read -r -p "Select file [1-${#inner_files[@]}, default: 1]: " f_choice
            if [ -z "$f_choice" ]; then
                target_path="${inner_files[0]}"
                selected_item="${target_path#$HOME/}"
            elif [[ "$f_choice" =~ ^[0-9]+$ ]] && [ "$f_choice" -ge 1 ] && [ "$f_choice" -le ${#inner_files[@]} ]; then
                target_path="${inner_files[$((f_choice - 1))]}"
                selected_item="${target_path#$HOME/}"
            else
                echo "Invalid selection. Aborting." >&2
                exit 1
            fi
        else
            target_path="${inner_files[0]}"
            selected_item="${target_path#$HOME/}"
        fi
    fi

    # Final check: warn if attempting to open non-text binary in editor
    if [ -f "$target_path" ] && ! _is_editable_text_file "$target_path"; then
        echo "Error: ~/$selected_item is a binary file (not a text file)." >&2
        exit 1
    fi

    # Create safety backup before editing unless explicitly disabled
    if [ "$NO_BACKUP" != true ]; then
        local backup_path
        backup_path=$(generate_backup_path "$target_path")
        if [ -L "$target_path" ]; then
            local cloud_target
            cloud_target=$(readlink -f "$target_path" 2>/dev/null || true)
            if [ -n "$cloud_target" ] && [ -e "$cloud_target" ]; then
                if [ -d "$cloud_target" ]; then
                    cp -r "$cloud_target" "$backup_path"
                else
                    cp "$cloud_target" "$backup_path"
                fi
            fi
        else
            if [ -d "$target_path" ]; then
                cp -r "$target_path" "$backup_path"
            else
                cp "$target_path" "$backup_path"
            fi
        fi
        log_info "Created safety backup before editing: $(basename "$backup_path")"
    fi

    echo "Opening ~/$selected_item with $editor_cmd..."
    eval "$editor_cmd \"\$target_path\""
}
