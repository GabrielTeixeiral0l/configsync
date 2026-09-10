#!/bin/bash

_tree_link_status() {
    local local_path="$1"
    local cloud_dir="$2"

    if [ -L "$local_path" ]; then
        local resolved_target
        resolved_target=$(readlink -f "$local_path" 2>/dev/null || true)
        if [ -z "$resolved_target" ] || [ ! -e "$resolved_target" ]; then
            echo "BROKEN"
        elif [[ "$resolved_target" == "$cloud_dir"* ]]; then
            echo "OK"
        else
            echo "BROKEN"
        fi
    elif [ -e "$local_path" ]; then
        echo "UNLINKED"
    else
        echo "MISSING"
    fi
}

_tree_format_status() {
    local status="$1"
    local no_color="$2"

    if [ "$no_color" = true ]; then
        case "$status" in
            OK) echo "[OK]" ;;
            BROKEN) echo "[BROKEN]" ;;
            UNLINKED) echo "[UNLINKED]" ;;
            MISSING) echo "[MISSING]" ;;
            *) echo "[UNKNOWN]" ;;
        esac
    else
        case "$status" in
            OK) printf '\033[32m[OK]\033[0m' ;;
            BROKEN) printf '\033[31m[BROKEN]\033[0m' ;;
            UNLINKED) printf '\033[33m[UNLINKED]\033[0m' ;;
            MISSING) printf '\033[90m[MISSING]\033[0m' ;;
            *) echo "[UNKNOWN]" ;;
        esac
    fi
}

cmd_tree() {
    local ALL_PROFILES=false
    local BY_GROUP=false
    local NO_COLOR=false
    local JSON_OUTPUT=false

    parse_filter_flags "$@"

    while [ $# -gt 0 ]; do
        case "$1" in
            --all-profiles|-a)
                ALL_PROFILES=true
                shift
                ;;
            --by-group)
                BY_GROUP=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
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

    [ ! -t 1 ] && NO_COLOR=true

    local profiles=()
    if [ "$ALL_PROFILES" = true ]; then
        profiles+=("default")
        if [ -d "${MOSY_CLOUD_DIR}/profiles" ]; then
            for pdir in "${MOSY_CLOUD_DIR}/profiles"/*; do
                if [ -d "$pdir" ]; then
                    local pname
                    pname=$(basename "$pdir")
                    [ "$pname" != "default" ] && profiles+=("$pname")
                fi
            done
        fi
    else
        profiles+=("${MOSY_PROFILE}")
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        local p_json_arr=()
        for prof in "${profiles[@]}"; do
            MOSY_PROFILE="$prof"
            load_settings

            local items_json=()
            _collect_tree_json() {
                local l_rel="$1"
                local c_rel="$2"
                local tags="$3"
                local groups="$4"

                local local_path="${HOME}/${l_rel}"
                local status
                status=$(_tree_link_status "$local_path" "$MOSY_CLOUD_DIR")

                local is_dir=false
                [ -d "$local_path" ] && is_dir=true

                local json_tags="[]"
                if [ -n "$tags" ]; then
                    json_tags=$(echo "$tags" | awk -F',' '{printf "["; for(i=1;i<=NF;i++){printf "\"%s\"%s", $i, (i<NF?", ":"")}; printf "]"}')
                fi
                local json_groups="[]"
                if [ -n "$groups" ]; then
                    json_groups=$(echo "$groups" | awk -F',' '{printf "["; for(i=1;i<=NF;i++){printf "\"%s\"%s", $i, (i<NF?", ":"")}; printf "]"}')
                fi

                items_json+=("{\"path\":\"~/${l_rel}\",\"is_directory\":${is_dir},\"status\":\"${status}\",\"tags\":${json_tags},\"groups\":${json_groups}}")
            }
            foreach_mapping _collect_tree_json

            local joined_items
            joined_items=$(IFS=,; echo "${items_json[*]}")
            p_json_arr+=("{\"profile\":\"${prof}\",\"items\":[${joined_items}]}")
        done
        local all_p_json
        all_p_json=$(IFS=,; echo "${p_json_arr[*]}")
        printf '{"profiles":[%s]}\n' "$all_p_json"
        return 0
    fi

    for prof in "${profiles[@]}"; do
        MOSY_PROFILE="$prof"
        load_settings

        local items_rel=()
        local items_tags=()
        local items_groups=()

        _collect_tree_items() {
            local l_rel="$1"
            local c_rel="$2"
            local tags="$3"
            local groups="$4"

            items_rel+=("$l_rel")
            items_tags+=("$tags")
            items_groups+=("$groups")
        }
        foreach_mapping _collect_tree_items

        if [ "$NO_COLOR" = true ]; then
            echo "MountSync (Profile: ${prof})"
        else
            printf '\033[1;34mMountSync (Profile: %s)\033[0m\n' "${prof}"
        fi

        if [ ${#items_rel[@]} -eq 0 ]; then
            echo "└── (no managed items)"
            echo ""
            continue
        fi

        if [ "$BY_GROUP" = true ]; then
            # Group -> Tag -> Item
            declare -A group_map
            declare -A group_tag_map

            local total_items=${#items_rel[@]}
            for ((i=0; i<total_items; i++)); do
                local it="${items_rel[$i]}"
                local tg="${items_tags[$i]}"
                local gr="${items_groups[$i]}"
                [ -z "$gr" ] && gr="ungrouped"
                [ -z "$tg" ] && tg="untagged"

                group_map["$gr"]+="$i "
            done

            local sorted_groups=()
            while IFS= read -r g; do
                [ -n "$g" ] && sorted_groups+=("$g")
            done < <(printf '%s\n' "${!group_map[@]}" | sort)

            local g_count=${#sorted_groups[@]}
            local g_idx=0
            for g in "${sorted_groups[@]}"; do
                ((g_idx++))
                local g_prefix="├──"
                local g_sub_prefix="│   "
                if [ $g_idx -eq $g_count ]; then
                    g_prefix="└──"
                    g_sub_prefix="    "
                fi

                if [ "$NO_COLOR" = true ]; then
                    echo "${g_prefix} [group: ${g}]"
                else
                    printf '%s \033[1;36m[group: %s]\033[0m\n' "${g_prefix}" "${g}"
                fi

                local indices=(${group_map["$g"]})
                local it_count=${#indices[@]}
                local it_idx=0
                for idx in "${indices[@]}"; do
                    ((it_idx++))
                    local it_prefix="├──"
                    if [ $it_idx -eq $it_count ]; then
                        it_prefix="└──"
                    fi

                    local it="${items_rel[$idx]}"
                    local tg="${items_tags[$idx]}"
                    local local_path="${HOME}/${it}"
                    local st
                    st=$(_tree_link_status "$local_path" "$MOSY_CLOUD_DIR")
                    local st_badge
                    st_badge=$(_tree_format_status "$st" "$NO_COLOR")

                    local extra=""
                    [ -n "$tg" ] && extra=" (tags: ${tg})"

                    echo "${g_sub_prefix}${it_prefix} ~/${it} ${st_badge}${extra}"
                done
            done
        else
            # Hierarchical Tree under ~
            echo "└── ~"
            local total_items=${#items_rel[@]}
            for ((i=0; i<total_items; i++)); do
                local it="${items_rel[$i]}"
                local tg="${items_tags[$i]}"
                local gr="${items_groups[$i]}"
                local local_path="${HOME}/${it}"

                local st
                st=$(_tree_link_status "$local_path" "$MOSY_CLOUD_DIR")
                local st_badge
                st_badge=$(_tree_format_status "$st" "$NO_COLOR")

                local meta=()
                [ -n "$tg" ] && meta+=("tags: ${tg}")
                [ -n "$gr" ] && meta+=("group: ${gr}")

                local meta_str=""
                if [ ${#meta[@]} -eq 2 ]; then
                    meta_str=" (${meta[0]} | ${meta[1]})"
                elif [ ${#meta[@]} -eq 1 ]; then
                    meta_str=" (${meta[0]})"
                fi

                local prefix="    ├──"
                if [ $((i + 1)) -eq $total_items ]; then
                    prefix="    └──"
                fi

                local is_dir=""
                if [ -d "$local_path" ]; then
                    is_dir=" [dir]"
                fi

                echo "${prefix} ${it}${is_dir} ${st_badge}${meta_str}"
            done
        fi
        echo ""
    done
}
