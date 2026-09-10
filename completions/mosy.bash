_mosy_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="add init pull list status doctor info diff history rollback backup snapshot edit which clean tree remove uninstall config version update link"

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        add)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--tag -t --group -g --link --target --to --force -f --scan-secrets --scan --no-scan --guard --no-guard" -- "$cur") )
            fi
            ;;
        link)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--tag -t --group -g --force -f" -- "$cur") )
            fi
            ;;
        status)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--json -j --quiet -q --tag -t --group -g" -- "$cur") )
            fi
            ;;
        doctor)
            if [ $COMP_CWORD -eq 2 ]; then
                COMPREPLY=( $(compgen -W "--fix -f" -- "$cur") )
            fi
            ;;
        info)
            if [ $COMP_CWORD -eq 2 ]; then
                COMPREPLY=( $(compgen -W "--json -j" -- "$cur") )
            fi
            ;;
        diff)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--backup -b --compare-profile -c --tag -t --group -g" -- "$cur") )
            fi
            ;;
        history)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--json -j --tag -t --group -g" -- "$cur") )
            fi
            ;;
        rollback)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--force -f" -- "$cur") )
            fi
            ;;
        backup|snapshot)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--tag -t --group -g" -- "$cur") )
            fi
            ;;
        edit)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--no-backup --tag -t --group -g" -- "$cur") )
            fi
            ;;
        which)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--json -j" -- "$cur") )
            fi
            ;;
        clean)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--older-than --dry-run -n --force -f --tag -t --group -g" -- "$cur") )
            fi
            ;;
        tree)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--all-profiles -a --by-group --no-color --json --tag -t --group -g" -- "$cur") )
            fi
            ;;
        config)
            if [ $COMP_CWORD -eq 2 ]; then
                COMPREPLY=( $(compgen -W "set" -- "$cur") )
            elif [ $COMP_CWORD -eq 3 ] && [ "$prev" == "set" ]; then
                local keys="MOSY_REMOTE_NAME MOSY_MOUNT_POINT MOSY_VFS_CACHE MOSY_CLOUD_DIR MOSY_BACKUP_EXT MOSY_LOG_LEVEL MOSY_DRY_RUN MOSY_SCAN_SECRETS MOSY_SAFETY_GUARD"
                COMPREPLY=( $(compgen -W "$keys" -- "$cur") )
            fi
            ;;
    esac
}
complete -F _mosy_completions mosy
