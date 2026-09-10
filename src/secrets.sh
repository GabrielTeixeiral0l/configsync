#!/bin/bash

# Load user custom patterns from ~/.config/mosy/secrets.conf if available
load_custom_secret_patterns() {
    CUSTOM_SECRET_REGEXES=()
    CUSTOM_SECRET_FILES=()
    local conf_file="${HOME}/.config/mosy/secrets.conf"
    [ -f "$conf_file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        if [[ "$line" =~ ^file: ]]; then
            CUSTOM_SECRET_FILES+=("${line#file:}")
        else
            CUSTOM_SECRET_REGEXES+=("$line")
        fi
    done < "$conf_file"
}

# Returns 0 if filename matches high-risk secret patterns, and sets MOSY_SECRET_REASON
is_sensitive_filename() {
    local base_name
    base_name=$(basename "$1")

    case "$base_name" in
        .env|.env.*)
            MOSY_SECRET_REASON="High-risk sensitive filename pattern (.env*)"
            return 0
            ;;
        id_rsa|id_ed25519|id_ecdsa|id_dsa|credentials.json|service_account.json)
            MOSY_SECRET_REASON="High-risk sensitive filename pattern ($base_name)"
            return 0
            ;;
        *.pem|*.key|*.p12|*.pfx)
            MOSY_SECRET_REASON="High-risk sensitive filename pattern (*.${base_name##*.})"
            return 0
            ;;
    esac

    for pat in "${CUSTOM_SECRET_FILES[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$base_name" == $pat ]]; then
            MOSY_SECRET_REASON="High-risk sensitive filename pattern ($pat)"
            return 0
        fi
    done
    return 1
}

# Scan a single file for secret patterns
scan_file_for_secrets() {
    local file="$1"
    MOSY_SECRET_REASON=""

    [ -f "$file" ] && [ -r "$file" ] || return 1
    is_sensitive_filename "$file" && return 0

    # Skip files larger than 1MB or binary files
    local file_size
    file_size=$(wc -c < "$file" 2>/dev/null || echo 0)
    [ "$file_size" -le 1048576 ] || return 1
    grep -qI . "$file" 2>/dev/null || return 1

    local patterns=(
        "Unencrypted Private Key:-----BEGIN ((RSA|OPENSSH|EC|DSA|ENCRYPTED) )?PRIVATE KEY|-----BEGIN PGP PRIVATE KEY BLOCK"
        "AWS Access Key ID:\bAKIA[0-9A-Z]{16}\b"
        "GitHub Access Token:\b(gh[pousr]_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{22}_[A-Za-z0-9_]{59})\b"
        "Slack API Token:\bxox[baprs]-[0-9a-zA-Z]{10,48}\b"
        "Stripe Live API Key:\b(sk|rk)_live_[0-9a-zA-Z]{24,}\b"
        "Generic High-Risk Secret Assignment:(password|secret|api_key|access_token|private_key)[[:space:]]*[:=][[:space:]]*['\"][^'\"]{6,}['\"]"
    )

    for entry in "${patterns[@]}"; do
        local reason="${entry%%:*}"
        local regex="${entry#*:}"
        if grep -E -i -q -m 1 -e "$regex" "$file" 2>/dev/null; then
            MOSY_SECRET_REASON="$reason"
            return 0
        fi
    done

    for regex in "${CUSTOM_SECRET_REGEXES[@]}"; do
        if grep -E -q -m 1 -e "$regex" "$file" 2>/dev/null; then
            MOSY_SECRET_REASON="Custom Secret Pattern ($regex)"
            return 0
        fi
    done

    return 1
}

# Helper to read reply with TTY and non-interactive EOF detection
_read_secret_prompt() {
    local prompt_text="$1"
    local abort_msg="$2"
    if [ -t 0 ]; then
        read -r -p "$prompt_text" MOSY_PROMPT_REPLY
    else
        if ! read -r MOSY_PROMPT_REPLY; then
            echo "Error: $abort_msg" >&2
            echo "Aborting sync to prevent cloud secret leak (non-interactive). Use --force to override." >&2
            exit 1
        fi
    fi
}

# Prompt user interactively for a single file containing secrets
prompt_secret_single() {
    local file="$1"
    local reason="$2"

    echo -e "\nWARNING: Potential secret leak detected!\n   File:   $file\n   Reason: $reason\n"
    _read_secret_prompt "Do you want to proceed syncing this file to the cloud? [y/N]: " "Potential secret detected in $file: $reason"

    case "$MOSY_PROMPT_REPLY" in
        [Yy]*) return 0 ;;
        *) echo "Sync cancelled by user."; exit 1 ;;
    esac
}

# Prompt user for directory with detected secrets
prompt_secret_directory() {
    local target_dir="$1"
    shift
    local flagged_items=("$@")

    echo -e "\nWARNING: Potential secret leaks detected in $target_dir:"
    for item in "${flagged_items[@]}"; do
        echo "   - ${item%%|*} (${item#*|})"
    done
    echo -e "\nOptions:\n  [y] Yes   - Proceed and sync everything (including secrets)\n  [s] Skip  - Keep sensitive files local only, sync the rest\n  [n] No    - Cancel operation (default)\n"

    _read_secret_prompt "Choose an option [y/s/N]: " "Potential secrets detected in directory $target_dir."

    case "$MOSY_PROMPT_REPLY" in
        [Yy]*) MOSY_DIR_SECRET_ACTION="all" ;;
        [Ss]*) MOSY_DIR_SECRET_ACTION="skip" ;;
        *)     echo "Sync cancelled by user."; exit 1 ;;
    esac
}
