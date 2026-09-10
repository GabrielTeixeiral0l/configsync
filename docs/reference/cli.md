# CLI Reference (`mosy`)

This reference manual provides exhaustive details on the `mosy` command-line interface, including global flags and all 13 subcommands. `mosy` is the command-line utility for MountSync, enabling user-space cloud vault synchronization using symbolic links and rclone virtual file system mounts.

---

## Global Syntax

```text
mosy [-p|--profile PROFILE] SUBCOMMAND [options] [arguments]
```

---

## Global Flags

Global flags must be specified before the subcommand.

### `-p`, `--profile`

* **Purpose**: Specifies the target synchronization profile for the command execution. If omitted, MountSync uses the `default` profile.
* **Syntax**: `-p PROFILE` or `--profile PROFILE`
* **Arguments**: `PROFILE` - The string name of the profile (e.g., `work`, `personal`, `default`).
* **Environment Variable Equivalent**: `MOSY_PROFILE`
* **Output Example**:
  ```text
  $ mosy -p work list
  Items managed by MountSync:
  - .config/nvim [tags: work] [groups: config]
  ```

---

## Subcommands Reference

| Command | Syntax | Description |
| :--- | :--- | :--- |
| [`add`](#1-add) | `mosy add <path> [options]` | Add a file or directory to cloud vault with granular symlinking and secret scanning |
| [`link`](#1b-link) | `mosy link <local> [target] [options]` | Map a local divergent OS path to an existing cloud vault item |
| [`init`](#2-init) | `mosy init [options]` | Recreate all managed symlinks on local machine from `sync-map.conf` |
| [`pull`](#3-pull) | `mosy pull [options]` | Link missing cloud items without overwriting existing local files |
| [`list`](#4-list) | `mosy list [options]` | List all managed dotfiles with associated tags and groups |
| [`status`](#5-status) | `mosy status [options]` | Show cloud mount health, systemd service state, and symlink integrity |
| [`doctor`](#6-doctor) | `mosy doctor [--fix]` | Run system diagnostics and automatically remediate broken links and services |
| [`info`](#7-info) | `mosy info [--json]` | Display environment overview dashboard and managed dotfile metrics |
| [`diff`](#8-diff) | `mosy diff [path] [options]` | Inspect differences against safety backups, physical vault copies, or profiles |
| [`history`](#9-history) | `mosy history [path] [--json]` | List timestamped backup snapshots for managed dotfiles in reverse chronological order |
| [`rollback`](#10-rollback) | `mosy rollback <path> [time]` | Safely restore a previous backup snapshot with automated pre-rollback safety backup |
| [`backup`](#11-backup) | `mosy backup [path] [options]` | Create on-demand timestamped safety backup snapshots for dotfiles |
| [`edit`](#12-edit) | `mosy edit <item> [options]` | Open managed dotfile in default editor with automatic pre-edit safety backup |
| [`which`](#13-which) | `mosy which <path> [--json]` | Inspect whether a local path is managed by MountSync and check link health |
| [`clean`](#14-clean) | `mosy clean [path] [options]` | Purge obsolete backup snapshots with duration filters and simulation mode |
| [`tree`](#15-tree) | `mosy tree [options]` | Render visual hierarchy tree of managed items with link health badges |
| [`remove`](#16-remove) | `mosy remove <path>` | Stop syncing an item and revert symlink back to a standalone local file |
| [`config`](#17-config) | `mosy config [set <k> <v>]` | View current settings or update configuration key-value pairs |
| [`version`](#18-version) | `mosy version` | Display installed version and check GitHub for latest updates |
| [`update`](#19-update) | `mosy update` | Update MountSync to the latest version |
| [`uninstall`](#20-uninstall) | `mosy uninstall` | Interactive wizard to revert links and cleanly remove MountSync |

---

### 1. `add`

* **Purpose**: Adds a local file or directory to MountSync management. For directories, it performs granular synchronization by preserving the local physical directory structure, moving only non-ignored files into the cloud vault and symlinking them individually. All ignored files (such as `.git`, `.env`, `node_modules`, or rules in `.mosyignore`) and volatile files skipped via the Safety Guard (such as active SQLite databases, runtime locks, sockets, or cache dirs) remain safely on the local disk without deletion. The item is appended to `sync-map.conf`.
* **Syntax**:
  ```text
  mosy [-p PROFILE] add FILE_OR_DIRECTORY [-t|--tag TAGS] [-g|--group GROUPS] [--scan-secrets|--scan] [--no-scan] [--guard|--no-guard] [-f|--force]
  ```
* **Arguments**:
  * `FILE_OR_DIRECTORY`: Path to a file or directory inside the user's home directory (`$HOME`). Relative paths are automatically resolved relative to `$HOME`.
* **Options/Flags**:
  * `-t, --tag TAGS`: Comma-separated list of tags to associate with the item (e.g., `work,dev`).
  * `-g, --group GROUPS`: Comma-separated list of groups to associate with the item (e.g., `dotfiles,configs`).
  * `--link, --target, --to TARGET`: Delegate to `mosy link` to map this local file to an existing cloud vault target.
  * `--scan-secrets`, `--scan`: Enable pre-vaulting regex inspection for unencrypted credentials, tokens, and private keys.
  * `--no-scan`: Bypass secret scanning even if `MOSY_SCAN_SECRETS=true` is enabled in configuration.
  * `--guard`: Explicitly enable the high-churn, database & lockfile safety guard inspection.
  * `--no-guard`: Disable safety guard scanning even if `MOSY_SAFETY_GUARD=true` is enabled.
  * `-f, --force`: Bypass interactive secret and safety confirmation prompts and force synchronization.
* **Output Example**:
  ```text
  $ mosy add ~/.bashrc --tag shell,main --group dotfiles
  Syncing .bashrc...
  Success! .bashrc is now synced.
  ```
* **Exit Codes**:
  * `0`: Success, or item is already a symbolic link.
  * `1`: Failure (cloud drive not mounted, target missing, target outside `$HOME`, secret detected in non-interactive mode or rejected by user, or backup/move failure).

---

### 1b. `link`

* **Purpose**: Maps a local divergent path (common in multi-OS setups such as macOS `~/Library/...` or Windows `AppData/Roaming/...`) to an existing file or directory in the cloud vault. It automatically determines platform tags, inherits groups from the vault target, backs up pre-existing local files, creates the symlink, and appends the entry to `sync-map.conf`.
* **Syntax**:
  ```text
  mosy [-p PROFILE] link LOCAL_PATH [CLOUD_TARGET] [-t|--tag TAGS] [-g|--group GROUPS] [-f|--force]
  ```
* **Arguments**:
  * `LOCAL_PATH`: Local destination path inside `$HOME` (e.g., `~/AppData/Roaming/Code/User/settings.json` or `~/Library/Application Support/Code/User/settings.json`).
  * `CLOUD_TARGET` *(Optional)*: Relative path of the existing target within the cloud vault (e.g., `.config/Code/User/settings.json`). If omitted, MountSync automatically searches the vault for items matching the file basename.
* **Options/Flags**:
  * `-t, --tag TAGS`: Comma-separated list of tags. Defaults to the detected host platform (`windows`, `macos`, `linux`, `wsl`).
  * `-g, --group GROUPS`: Comma-separated list of groups. Automatically inherits groups from the vault target if already registered in `sync-map.conf`.
  * `-f, --force`: Automatically select first match if multiple candidates are found and skip interactive prompts.
* **Output Example**:
  ```text
  $ mosy link ~/AppData/Roaming/Code/User/settings.json .config/Code/User/settings.json
  Success! Linked ~/AppData/Roaming/Code/User/settings.json -> vault/.config/Code/User/settings.json (tags: windows).
  ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (cloud drive not mounted, cloud target missing, or local path outside `$HOME`).

---

### 2. `init`

* **Purpose**: Configures the local machine by reading `sync-map.conf` from the cloud vault and establishing symbolic links for all managed items. By default, it automatically filters entries for the host platform (`linux`, `macos`, `windows`, `wsl`), universal tags (`all`, `unix`), and untagged items, while ignoring foreign OS paths.
* **Syntax**:
  ```text
  mosy [-p PROFILE] init [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `-t, --tag TAGS`: Filters processing to only items containing at least one of the specified tags.
  * `-g, --group GROUPS`: Filters processing to only items containing at least one of the specified groups.
* **Output Example**:
  ```text
  $ mosy init --tag dev
  Configuring PC from sync map...
  Creating link for .config/nvim...
  PC configured successfully!
  ```
* **Exit Codes**:
  * `0`: Success (including when `sync-map.conf` is missing or no entries match filters).
  * `1`: Failure (cloud drive not mounted).

---

### 3. `pull`

* **Purpose**: Performs a non-destructive check against `sync-map.conf` and creates symbolic links for managed items present in the cloud vault that are not yet linked or existing on the local machine.
* **Syntax**:
  ```text
  mosy [-p PROFILE] pull [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `-t, --tag TAGS`: Filters processing to only items matching the given tags.
  * `-g, --group GROUPS`: Filters processing to only items matching the given groups.
* **Output Example**:
  ```text
  $ mosy pull -g dotfiles
  Linked .tmux.conf
  ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (cloud drive not mounted).

---

### 4. `list`

* **Purpose**: Lists all files and directories currently managed under the active profile's `sync-map.conf`, along with their configured tags and groups.
* **Syntax**:
  ```text
  mosy [-p PROFILE] list [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `-t, --tag TAGS`: Shows only items matching the specified tags.
  * `-g, --group GROUPS`: Shows only items matching the specified groups.
* **Output Example**:
  ```text
  $ mosy list
  Items managed by MountSync:
  - .bashrc [tags: shell] [groups: dotfiles]
  - .config/nvim [tags: dev] [groups: config]
  ```
* **Exit Codes**:
  * `0`: Success.

---

### 5. `status`

* **Purpose**: Evaluates and displays the status of the cloud mount point, the systemd user service (`mosy-mount.service`), and file integrity across all managed items.
* **Syntax**:
  ```text
  mosy [-p PROFILE] status [--json|-j] [--quiet|-q] [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `--json, -j`: Outputs system status and file integrity in structured JSON format (suitable for Waybar, Polybar, tmux, and custom scripts).
  * `--quiet, -q`: Suppresses all output and returns exit code only (`0` for healthy system, `1` if issues detected).
  * `-t, --tag TAGS`: Filters integrity checks by tags.
  * `-g, --group GROUPS`: Filters integrity checks by groups.
* **Output Example**:
  * Standard text format:
    ```text
    $ mosy status
    --- System Status ---
    Mount Point (/home/user/GoogleDrive): MOUNTED
    Systemd Service (mosy-mount): ACTIVE

    --- File Integrity ---
    [OK] .bashrc
    [WARN] .config/nvim (Missing link: cloud source exists)

    --- Summary ---
    Total: 2
    OK: 1
    Warnings: 1
    Errors: 0
    ```
  * Machine-readable JSON format:
    ```json
    $ mosy status --json
    {"profile":"default","system":{"mounted":true,"mount_point":"/home/user/GoogleDrive","service_active":true,"service_status":"active"},"files":{"total":2,"ok":1,"warn":1,"err":0},"healthy":false}
    ```
* **Exit Codes**:
  * `0`: Success (system healthy in `--quiet` / `--json` modes, or text output completed).
  * `1`: Failure (mount inactive or file integrity errors/warnings detected in `--quiet` / `--json` modes).

---

### 6. `doctor`

* **Purpose**: Performs a deep diagnostic audit of the entire MountSync infrastructure, dependencies, mount points, background services, cloud connectivity, token authentication, vault storage permissions, and symlink integrity. When invoked with `--fix`, automatically remediates resolvable issues safely and non-destructively.
* **Syntax**:
  ```text
  mosy [-p PROFILE] doctor [--fix]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `--fix, -f`: Attempts automatic safe remediation of detected issues (e.g. creating missing mount directories, starting inactive systemd services, recreating valid missing symlinks, and correcting configuration permissions).
* **Output Example**:
  * Diagnostic check:
    ```text
    $ mosy doctor
    --- Dependencies & Environment ---
    [OK] rclone: found (/usr/bin/rclone)
    [OK] mountpoint: found
    [OK] POSIX utilities: all essential tools present
    [OK] Service manager: systemctl (systemd)
    [OK] Configuration directory: ~/.config/mosy

    --- Mount Point & Services ---
    [OK] Systemd service (mosy-mount): ACTIVE
    [OK] Mount Point (/home/user/GoogleDrive): MOUNTED
    [OK] rclone process: RUNNING

    --- Cloud Connectivity & Storage ---
    [OK] Cloud connectivity (gdrive:): REACHABLE & AUTHENTICATED
    [OK] Vault storage (/home/user/GoogleDrive/mosy_vault): READ/WRITE
    [OK] Storage free space: 42G available

    --- Mapping & Symlink Integrity ---
    [OK] .bashrc
    [OK] .config/nvim

    --- Database & Lockfile Safety Audit ---
    [OK] No active databases, sockets, or lockfiles detected over FUSE

    --- Doctor Summary ---
    Total checks: 13
    OK: 13
    Warnings: 0
    Errors: 0
    ```
* **Exit Codes**:
  * `0`: Success (all checks passed or all errors remediated).
  * `1`: One or more diagnostic errors detected (or remediation failed).

---

### 7. `info`

* **Purpose**: Displays a comprehensive environment overview dashboard containing system facts, active MountSync configuration, cloud mount and background service health, and managed item statistics. Supports `--json` for machine-readable output and status bar integrations.
* **Syntax**:
  ```text
  mosy [-p PROFILE] info [--json|-j]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `--json, -j`: Output full environment overview and metrics formatted as JSON.
* **Output Example**:
  * Default human-readable output:
    ```text
    $ mosy info
    === MountSync Environment Overview ===

    --- System ---
    Hostname:          archlinux
    OS:                Linux 6.6.10-arch1-1 (x86_64)
    Architecture:      x86_64

    --- Configuration ---
    Active Profile:    default
    Cloud Remote:      gdrive:
    Mount Point:       /home/user/GoogleDrive [MOUNTED]
    Service Status:    ACTIVE
    Vault Path:        /home/user/GoogleDrive/mosy_vault
    Sync Map:          /home/user/GoogleDrive/mosy_vault/sync-map.conf
    VFS Cache Mode:    writes

    --- Managed Items ---
    Total Managed:     4
    Valid Links:       3
    Broken Links:      0
    Missing Links:     1
    Unique Tags:       2
    Unique Groups:     1
    ```
  * JSON output:
    ```text
    $ mosy info --json
    {
      "system": {
        "hostname": "archlinux",
        "os": "Linux",
        "os_details": "Linux 6.6.10-arch1-1 (x86_64)",
        "kernel": "6.6.10-arch1-1",
        "architecture": "x86_64"
      },
      "configuration": {
        "profile": "default",
        "remote_name": "gdrive:",
        "mount_point": "/home/user/GoogleDrive",
        "mount_status": "MOUNTED",
        "is_mounted": true,
        "service_status": "active",
        "vault_path": "/home/user/GoogleDrive/mosy_vault",
        "sync_map_file": "/home/user/GoogleDrive/mosy_vault/sync-map.conf",
        "vfs_cache": "writes"
      },
      "metrics": {
        "total_managed": 4,
        "valid_links": 3,
        "broken_links": 0,
        "missing_links": 1,
        "lost_items": 0,
        "unique_tags": 2,
        "unique_groups": 1
      }
    }
    ```
* **Exit Codes**:
  * `0`: Success (including when mount point is unmounted or sync map is empty).

---

### 8. `diff`

* **Purpose**: Inspects differences between managed dotfiles and their safety backups (`.bak_*`), physical unlinked local files and cloud vault counterparts, or cross-profile file versions. Automatically utilizes colored output (`diff --color=always`, `delta`, or ANSI color wrapper).
* **Syntax**:
  ```text
  mosy [-p PROFILE] diff [PATH] [-b|--backup [TIMESTAMP]] [-c|--compare-profile PROFILE] [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**:
  * `PATH`: (Optional) File or directory path to inspect. If omitted, diffs all managed items matching active filters.
* **Options/Flags**:
  * `-b, --backup [TIMESTAMP]`: Compare against a specific timestamped backup snapshot, or latest `.bak_*` if timestamp omitted.
  * `-c, --compare-profile, --profile-target PROFILE`: Compare the active profile's file against another profile.
  * `-t, --tag TAGS`: Filter items by tags when diffing all items.
  * `-g, --group GROUPS`: Filter items by groups when diffing all items.
* **Output Example**:
  * Diff against latest safety backup:
    ```text
    $ mosy diff ~/.bashrc
    === Diff: Backup (.bashrc.bak_20260821_120000) vs Current (.bashrc) ===
    --- .bashrc.bak_20260821_120000
    +++ current:.bashrc
    @@ -10,3 +10,4 @@
     alias ll='ls -la'
    +export EDITOR=nvim
    ```
  * Cross-profile diff:
    ```text
    $ mosy -p work diff ~/.gitconfig --compare-profile default
    === Diff: Profile 'work' vs Profile 'default' for .gitconfig ===
    --- work:.gitconfig
    +++ default:.gitconfig
    @@ -1,4 +1,4 @@
     [user]
    -    email = dev@company.com
    +    email = dev@personal.me
    ```
* **Exit Codes**:
  * `0`: Success (including when differences are found or no backups exist).
  * `1`: Failure (target file or requested backup not found).

---

### 9. `history`

* **Purpose**: Lists timestamped safety backup snapshots (`.bak_YYYYMMDD_HHMMSS`) associated with a specific dotfile or across all managed items, displayed in reverse chronological order with formatted dates and file sizes.
* **Syntax**:
  ```text
  mosy [-p PROFILE] history [PATH] [-j|--json] [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**:
  * `PATH`: (Optional) Path to a specific managed file or directory. If omitted, lists snapshots for all managed items in the profile.
* **Options/Flags**:
  * `-j, --json`: Format output as a JSON array of snapshot objects (suitable for scripts and bar integrations).
  * `-t, --tag TAGS`: Filter items by tags when viewing global history.
  * `-g, --group GROUPS`: Filter items by groups when viewing global history.
* **Output Example**:
  ```text
  $ mosy history ~/.bashrc
  Backup History for ~/.bashrc:
    [1] 2026-08-25 16:30:15 (1.2 KB)  /home/user/.bashrc.bak_20260825_163015
    [2] 2026-08-20 10:00:00 (1.1 KB)  /home/user/.bashrc.bak_20260820_100000
  ```
* **Exit Codes**:
  * `0`: Success.

---

### 10. `rollback`

* **Purpose**: Safely restores a previous backup snapshot to the local system and cloud vault. Before performing the restoration, it automatically generates a pre-rollback safety backup of the current state, ensuring complete non-destructiveness (**Zero Data Loss**).
* **Syntax**:
  ```text
  mosy [-p PROFILE] rollback PATH [TIMESTAMP_OR_INDEX] [-f|--force]
  ```
* **Arguments**:
  * `PATH`: The managed file or directory to restore.
  * `TIMESTAMP_OR_INDEX`: (Optional) Specific backup timestamp string (e.g. `20260825_163015`), substring, or 1-based index (e.g. `1`, `2`). If omitted in interactive terminal, prompts with a numbered selection menu; in non-interactive mode, restores the most recent snapshot.
* **Options/Flags**:
  * `-f, --force`: Bypass interactive selection prompt and restore the latest snapshot immediately.
* **Output Example**:
  ```text
  $ mosy rollback ~/.bashrc 1
  Rolling back ~/.bashrc to .bashrc.bak_20260825_163015...
  Success! Rolled back ~/.bashrc to .bashrc.bak_20260825_163015.
  ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (missing path, no backup snapshots available, or invalid timestamp/index).

---

### 11. `backup`

* **Purpose**: Creates on-demand timestamped safety backup snapshots (`.bak_YYYYMMDD_HHMMSS`) for a specific managed item or across all dotfiles managed in the active profile before making sensitive edits. The alias `mosy snapshot` can be used interchangeably. The active symlink to the cloud vault remains untouched and valid.
* **Syntax**:
  ```text
  mosy [-p PROFILE] backup [PATH] [-t|--tag TAGS] [-g|--group GROUPS]
  # Or using snapshot alias:
  mosy [-p PROFILE] snapshot [PATH] [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**:
  * `PATH`: (Optional) File or directory path to back up. If omitted, creates backups for all managed items in the active profile matching tag/group filters.
* **Options/Flags**:
  * `-t, --tag TAGS`: Filter items by tags when creating batch backups.
  * `-g, --group GROUPS`: Filter items by groups when creating batch backups.
* **Output Example**:
  * Backup a single file:
    ```text
    $ mosy backup ~/.bashrc
    Success! Created safety backup for ~/.bashrc (.bashrc.bak_20260830_110000).
    ```
  * Batch backup all managed dotfiles:
    ```text
    $ mosy backup
    Creating safety snapshots for managed dotfiles...
      [OK] ~/.bashrc -> .bashrc.bak_20260830_110000
      [OK] ~/.config/nvim/init.lua -> init.lua.bak_20260830_110000
    Done! Backed up 2 item(s) successfully.
    ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (target file does not exist or read error).

---

### 12. `edit`

* **Purpose**: Locates a managed dotfile (via exact path or case-insensitive substring search) and opens it directly in the user's configured editor (`$VISUAL`, `$EDITOR`, or fallback `nano`/`vim`/`vi`). Automatically creates a timestamped safety backup snapshot (`.bak_YYYYMMDD_HHMMSS`) before launching the editor, unless `--no-backup` is passed.
* **Syntax**:
  ```text
  mosy [-p PROFILE] edit [QUERY] [--no-backup] [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**:
  * `QUERY`: (Optional) Path, filename, or substring identifying the managed dotfile (e.g. `aliases`, `nvim`, `~/.bashrc`). If omitted, prompts with an interactive selection menu.
* **Options/Flags**:
  * `--no-backup`: Skip automatic creation of pre-edit safety backup snapshot.
  * `-t, --tag TAGS`: Filter items by tags when searching/selecting.
  * `-g, --group GROUPS`: Filter items by groups when searching/selecting.
* **Output Example**:
  ```text
  $ mosy edit aliases
  Created safety backup before editing: .bash_aliases.bak_20260831_160000
  Opening ~/.bash_aliases with nvim...
  ```
* **Exit Codes**:
  * `0`: Success (or editor exit code).
  * `1`: Failure (target not found or no managed dotfiles in profile).

---

### 13. `which`

* **Purpose**: Inspects whether a specific local file or directory path is managed by MountSync in the active profile. Displays metadata including active profile, root mapping entry, cloud vault target, link integrity status, associated tags and groups, and snapshot history count. Supports `--json` for status bars (`Waybar`, `Polybar`) and script integrations.
* **Syntax**:
  ```text
  mosy [-p PROFILE] which PATH [--json|-j]
  ```
* **Arguments**:
  * `PATH`: Local file or directory path to inspect.
* **Options/Flags**:
  * `--json, -j`: Output result in machine-readable JSON format.
* **Output Example**:
  * Human-readable output:
    ```text
    $ mosy which ~/.bashrc
    Item:         ~/.bashrc
    Managed:      Yes (Profile: default)
    Root Entry:   ~/.bashrc
    Cloud Target: /home/user/GoogleDrive/mosy_vault/.bashrc
    Link Status:  OK (Active Symlink)
    Tags:         shell, core
    Groups:       env
    Snapshots:    3 in history
    ```
  * Machine-readable JSON output:
    ```json
    $ mosy which ~/.bashrc --json
    {"path":"~/.bashrc","absolute_path":"/home/user/.bashrc","managed":true,"profile":"default","matched_root":"~/.bashrc","cloud_target":"/home/user/GoogleDrive/mosy_vault/.bashrc","status":"OK","tags":["shell", "core"],"groups":["env"],"snapshot_count":3}
    ```
* **Exit Codes**:
  * `0`: Success (target is managed and link status is OK).
  * `1`: Failure (target is not managed, link is broken/misconfigured, or path argument is missing).

---

### 14. `clean`

* **Purpose**: Safely scans `$HOME` for obsolete backup snapshots (`.bak_YYYYMMDD_HHMMSS`, `.backup_*`, and custom `${MOSY_BACKUP_EXT}`) created by MountSync, removing them to free local disk space while guaranteeing that active dotfiles and symlinks remain untouched. Supports duration filters (`--older-than 30d`), simulation (`--dry-run`), and tag/group filtering.
* **Syntax**:
  ```text
  mosy [-p PROFILE] clean [PATH] [--older-than <duration>] [--dry-run|-n] [--force|-f] [-t|--tag TAGS] [-g|--group GROUPS]
  ```
* **Arguments**:
  * `PATH`: (Optional) Clean backup snapshots for a specific file or directory only. If omitted, cleans backups for all managed items in the active profile.
* **Options/Flags**:
  * `--older-than <duration>`: Only delete snapshots older than duration (e.g. `30d`, `7d`, `24h`, `60m`).
  * `--dry-run, -n`: Simulate deletion without removing any files, displaying candidates and total reclaimable space.
  * `--force, -f`: Skip interactive confirmation prompt.
  * `-t, --tag TAGS`: Filter managed items by tags.
  * `-g, --group GROUPS`: Filter managed items by groups.
* **Output Example**:
  * Simulation mode (`--dry-run`):
    ```text
    $ mosy clean --older-than 30d --dry-run
    [DRY RUN] The following backup snapshot(s) would be removed:
      - ~/.bashrc.bak_20260715_100000 (1.2 KB)
      - ~/.bash_aliases.bak_20260710_083000 (4.5 KB)
    Total: 2 file(s), 5.7 KB reclaimable space.
    ```
  * Clean execution:
    ```text
    $ mosy clean --older-than 30d --force
    Success! Removed 2 backup snapshot(s) (freed 5.7 KB).
    ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (invalid duration format or error).

---

### 15. `tree`

* **Purpose**: Renders an ASCII/Unicode visual hierarchy tree of all managed dotfiles and folders, displaying directory structure, tags, groups, and real-time symlink health badges (`✔ OK`, `✖ BROKEN`, `⚠ UNLINKED`, `? MISSING`). Supports alternate grouping (`--by-group`), multi-profile topologies (`--all-profiles`), clean pipe output (`--no-color`), and JSON export (`--json`).
* **Syntax**:
  ```text
  mosy [-p PROFILE] tree [options]
  ```
* **Arguments**: None.
* **Options/Flags**:
  * `--all-profiles, -a`: Render tree for all configured profiles in the cloud vault.
  * `--by-group`: Group dotfiles by `Group -> Item` rather than filesystem hierarchy.
  * `--no-color`: Disable ANSI color escape codes (automatically enabled when stdout is not a TTY).
  * `--json`: Export tree hierarchy in JSON format.
  * `-t, --tag TAGS`: Filter items by tags.
  * `-g, --group GROUPS`: Filter items by groups.
* **Output Example**:
  * Default tree view:
    ```text
    $ mosy tree
    MountSync (Profile: default)
    └── ~
        ├── .bashrc [✔ OK] (tags: shell | group: env)
        ├── .bash_aliases [✔ OK]
        ├── .config
        │   └── nvim
        │       ├── init.lua [✔ OK] (tags: dev)
        │       └── lua/plugins.lua [✔ OK]
        └── scripts [dir] [✔ OK] (tags: dev | group: tools)
    ```
  * Grouped view:
    ```text
    $ mosy tree --by-group
    MountSync (Profile: default)
    ├── [group: env]
    │   └── ~/.bashrc [✔ OK] (tags: shell)
    └── [group: tools]
        └── ~/scripts [✔ OK] (tags: dev)
    ```
* **Exit Codes**:
  * `0`: Success.

---

### 16. `remove`

* **Purpose**: Removes an item from MountSync management by restoring the target as a standalone local file/directory copied back from the cloud vault, removing its entry from `sync-map.conf`. The original cloud vault copy remains preserved.
* **Syntax**:
  ```text
  mosy [-p PROFILE] remove PATH
  ```
* **Arguments**:
  * `PATH`: The file or directory path to unmanage.
* **Options/Flags**: None.
* **Output Example**:
  ```text
  $ mosy remove ~/.bashrc
  Reverting .bashrc to local file...
  Success! .bashrc is now a local file.
  Note: The cloud copy remains in the vault for your other devices.
  ```
* **Exit Codes**:
  * `0`: Success (or cleanup of a broken link).
  * `1`: Failure (missing path argument, target is not a symlink managed by MountSync, or copy failure).

---

### 17. `config`

* **Purpose**: Views all MountSync configuration settings or updates a specific configuration key in `~/.config/mosy/config`.
* **Syntax**:
  * View configuration:
    ```text
    mosy config
    ```
  * Set key-value pair:
    ```text
    mosy config set KEY VALUE
    ```
* **Arguments**:
  * `set`: Subcommand action to modify a setting.
  * `KEY`: Configuration parameter name. Valid keys: `MOSY_REMOTE_NAME`, `MOSY_MOUNT_POINT`, `MOSY_VFS_CACHE`, `MOSY_CLOUD_DIR`, `MOSY_BACKUP_EXT`, `MOSY_LOG_LEVEL`, `MOSY_DRY_RUN`, `MOSY_SCAN_SECRETS`, `MOSY_SAFETY_GUARD`.
  * `VALUE`: New value for the configuration key.
* **Options/Flags**: None.
* **Output Example**:
  * View config:
    ```text
    $ mosy config
    --- Mosy Configuration ---

    [Remote]
    MOSY_REMOTE_NAME     "gdrive:"    # The rclone remote name (e.g., gdrive:).
    MOSY_MOUNT_POINT     "/home/user/GoogleDrive"    # Local mount path. (Default: /home/user/GoogleDrive)
    MOSY_VFS_CACHE       "writes"    # rclone VFS cache mode (e.g., writes, full, off). (Default: writes)
    MOSY_CLOUD_DIR       "/home/user/GoogleDrive/mosy_vault"    # Root folder inside mount. (Default: ${MOSY_MOUNT_POINT}/mosy_vault)

    [Behavior]
    MOSY_BACKUP_EXT      ".bak"    # Extension for conflict backups. (Default: .bak)
    MOSY_LOG_LEVEL       "INFO"    # Verbosity: INFO, DEBUG, SILENT (Default: INFO)
    MOSY_DRY_RUN         "false"    # If true, simulate actions without changes. (Default: false)
    MOSY_SCAN_SECRETS    "false"    # Scan for secrets on add. (Default: false)
    MOSY_SAFETY_GUARD    "true"     # Scan for SQLite DBs, locks, sockets, and caches on add. (Default: true)
    ```
  * Set config:
    ```text
    $ mosy config set MOSY_LOG_LEVEL DEBUG
    Configured MOSY_LOG_LEVEL="DEBUG"
    ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (invalid key or value).

---

### 18. `version`

* **Purpose**: Displays the currently installed MountSync version, commit hash, and checks GitHub Releases for new updates.
* **Syntax**:
  ```text
  mosy version
  ```
* **Arguments**: None.
* **Options/Flags**: None.
* **Exit Codes**:
  * `0`: Success.

---

### 19. `update`

* **Purpose**: Fetches and applies the latest updates from the MountSync GitHub repository, updating the installed scripts and completion files.
* **Syntax**:
  ```text
  mosy update
  ```
* **Arguments**: None.
* **Options/Flags**: None.
* **Output Example**:
  ```text
  $ mosy update
  Updating MountSync...
  Update complete!
  ```
* **Exit Codes**:
  * `0`: Success.
  * `1`: Failure (installation repository directory missing or git pull/install error).

---

### 20. `uninstall`

* **Purpose**: Interactive uninstallation wizard that prompts to revert managed items to local files, unmount the cloud drive, disable and remove the systemd user service, and delete binary and completion files.
* **Syntax**:
  ```text
  mosy uninstall
  ```
* **Arguments**: None.
* **Options/Flags**: None.
* **Output Example**:
  ```text
  $ mosy uninstall
  === MountSync Uninstall ===
  Do you want to revert all synced files to local files? (y/N) n
  The installation folder (/home/user/.mountsync) and binary will be removed. Confirm? (y/N) y
  Cleaning up system integration...
  Do you want to unmount the cloud drive (/home/user/GoogleDrive) now? (y/N) y
  Stopping service and unmounting...
  Disabling service and removing files...
  MountSync uninstalled successfully. Goodbye!
  ```
* **Exit Codes**:
  * `0`: Success or cancellation.

---

## Related Documents

* [Quickstart Tutorial](../tutorials/quickstart.md)
* [Multiple Profiles Guide](../how-to/profiles.md)
* [Tags and Groups Guide](../how-to/tags-and-groups.md)
* [Ignore Patterns Guide](../how-to/mosyignore.md)
* [Diagnostics & Auto-Remediation Guide](../how-to/doctor-and-diagnostics.md)
* [Diff and Backups Inspection Guide](../how-to/diff-and-backups.md)
* [Secret Leak Prevention Guide](../how-to/secrets-prevention.md)
* [Multi-Machine Synchronization Guide](../how-to/multi-machine-sync.md)
* [Configuration Reference](configuration.md)
* [Architecture & Design](../explanation/architecture.md)
* [Documentation Portal](../README.md)
