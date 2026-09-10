#!/bin/bash

# Returns 0 if file matches database, lockfile, socket, or high-churn patterns
is_volatile_or_db_file() {
    local file_path="$1"
    MOSY_SAFETY_CATEGORY=""
    MOSY_SAFETY_REASON=""

    # 1. Special UNIX file types (Sockets and Named Pipes)
    if [ -S "$file_path" ]; then
        MOSY_SAFETY_CATEGORY="LOCK_IPC"
        MOSY_SAFETY_REASON="Unix Domain Socket (live IPC endpoint)"
        return 0
    fi
    if [ -p "$file_path" ]; then
        MOSY_SAFETY_CATEGORY="LOCK_IPC"
        MOSY_SAFETY_REASON="Named pipe / FIFO (live IPC stream)"
        return 0
    fi

    local base_name
    base_name=$(basename "$file_path")

    # 2. SQLite Journals, WAL and SHM files
    case "$base_name" in
        *.sqlite-wal|*.sqlite-shm|*.db-wal|*.db-shm|*.db-journal)
            MOSY_SAFETY_CATEGORY="DATABASE"
            MOSY_SAFETY_REASON="Active SQLite WAL/journal file ($base_name)"
            return 0
            ;;
    esac

    # 3. Embedded Database files by extension
    case "$base_name" in
        *.sqlite|*.sqlite3|*.duckdb|*.ldb|*.kdbx|*.rdb)
            MOSY_SAFETY_CATEGORY="DATABASE"
            MOSY_SAFETY_REASON="Embedded database file ($base_name)"
            return 0
            ;;
        *.db)
            MOSY_SAFETY_CATEGORY="DATABASE"
            MOSY_SAFETY_REASON="Database file ($base_name)"
            return 0
            ;;
    esac

    # 4. Runtime locks, sockets, and IPC files by extension / pattern
    case "$base_name" in
        *.sock|*.socket|*.pid|*.lock|*.lck|*.ipc)
            MOSY_SAFETY_CATEGORY="LOCK_IPC"
            MOSY_SAFETY_REASON="Runtime lock or IPC state file ($base_name)"
            return 0
            ;;
    esac

    # 5. High-churn log and cache files
    case "$base_name" in
        *.log|*.log.*|*.cache)
            MOSY_SAFETY_CATEGORY="HIGH_CHURN"
            MOSY_SAFETY_REASON="High-churn log/cache file ($base_name)"
            return 0
            ;;
    esac

    # 6. High-churn directories in path (relative to HOME)
    local check_path="$file_path"
    if [[ -n "$HOME" && "$check_path" == "$HOME/"* ]]; then
        check_path="${check_path#$HOME/}"
    fi
    if [[ "/$check_path" == *"/.cache/"* || "/$check_path" == *"/logs/"* || "/$check_path" == *"/tmp/"* || "/$check_path" == *"/Cache/"* || "/$check_path" == *"/CachedData/"* ]]; then
        MOSY_SAFETY_CATEGORY="HIGH_CHURN"
        MOSY_SAFETY_REASON="High-churn cache/log directory path"
        return 0
    fi

    # 7. SQLite magic header check (first 16 bytes: "SQLite format 3\000")
    if [[ "$base_name" != *.* || "$base_name" == *.db || "$base_name" == *.dat || "$base_name" == *.bin || "$base_name" == *.sqlite* ]]; then
        if [ -f "$file_path" ] && [ -r "$file_path" ]; then
            if head -c 15 "$file_path" 2>/dev/null | grep -q '^SQLite format 3'; then
                MOSY_SAFETY_CATEGORY="DATABASE"
                MOSY_SAFETY_REASON="SQLite database (header: SQLite format 3)"
                return 0
            fi
        fi
    fi

    return 1
}

# Scan a single file for safety risks
scan_file_for_safety() {
    local file="$1"
    is_volatile_or_db_file "$file"
}

# Helper to read reply with TTY and non-interactive EOF detection
_read_safety_prompt() {
    local prompt_text="$1"
    local abort_msg="$2"
    if [ -t 0 ]; then
        read -r -p "$prompt_text" MOSY_SAFETY_PROMPT_REPLY
    else
        if ! read -r MOSY_SAFETY_PROMPT_REPLY; then
            echo "Error: $abort_msg" >&2
            echo "Aborting sync to prevent FUSE lock contention and database corruption (non-interactive). Use --force or --no-guard to override." >&2
            exit 1
        fi
    fi
}

# Prompt user interactively for a single file containing database/locks
prompt_safety_single() {
    local file="$1"
    local category="$2"
    local reason="$3"

    echo -e "\nWARNING: High-Churn / Database / Lockfile detected!\n   File:     $file\n   Category: $category\n   Reason:   $reason"
    echo -e "   Notice:   Mounting active databases or lockfiles directly over FUSE can cause"
    echo -e "             deadlocks, high latency, and data corruption.\n"
    _read_safety_prompt "Do you want to proceed syncing this file to the cloud vault? [y/N]: " "High-risk volatile file detected in $file ($reason)."

    case "$MOSY_SAFETY_PROMPT_REPLY" in
        [Yy]*) return 0 ;;
        *) echo "Sync cancelled by user."; exit 1 ;;
    esac
}

# Prompt user for directory with detected databases/locks/high-churn files
prompt_safety_directory() {
    local target_dir="$1"
    shift
    local flagged_items=("$@")

    echo -e "\nWARNING: High-churn, database, or lock files detected in $target_dir:"
    for item in "${flagged_items[@]}"; do
        echo "   - ${item%%|*} (${item#*|})"
    done
    echo -e "\nNotice: Mounting active databases, logs, or live lockfiles over FUSE may cause"
    echo -e "        application freezes, lock contention, or database corruption."
    echo -e "\nOptions:\n  [s] Skip  - Keep volatile/database files local, sync safe configs only (Recommended)\n  [y] Yes   - Proceed and sync everything (accept risk)\n  [n] No    - Cancel operation (default)\n"

    _read_safety_prompt "Choose an option [s/y/N]: " "High-risk volatile/database files detected in $target_dir."

    case "$MOSY_SAFETY_PROMPT_REPLY" in
        [Ss]*) MOSY_DIR_SAFETY_ACTION="skip" ;;
        [Yy]*) MOSY_DIR_SAFETY_ACTION="all" ;;
        *)     echo "Sync cancelled by user."; exit 1 ;;
    esac
}
