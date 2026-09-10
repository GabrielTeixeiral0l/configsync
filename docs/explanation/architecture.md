# MountSync Architecture & Design

This document explains the design principles, core mental model, data flow, safety mechanisms, system integrations, and codebase structure of **MountSync** (`mosy`), helping developers and system administrators build a comprehensive understanding of how MountSync operates.

---

## 1. Core Mental Model

MountSync provides seamless dotfile and workspace synchronization by combining Linux symbolic links with cloud storage mounted as a local filesystem.

### 1.1 The 4-Layer Indirection Pipeline

MountSync establishes a four-tier path mapping model for every managed item:

```text
+-------------------+      symlink      +-----------------------+
|  Local Path       |  -------------->  |  Local Mount Point    |
|  (~/.bashrc)      |                   |  (~/GoogleDrive/...)  |
+-------------------+                   +-----------------------+
                                                    |
                                                    | rclone FUSE Mount
                                                    v
+-------------------+      network      +-----------------------+
| Remote Storage    |  <--------------  | VFS Write Cache       |
| (Google Drive)    |      rclone       | (~/.cache/rclone)     |
+-------------------+                   +-----------------------+
```

1. **Local File / Application Level**: Applications interact with files at standard system paths (for example, `~/.config/app/config.json` or `~/.bashrc`). The application is entirely unaware that the file resides in cloud storage.
2. **Symbolic Link Level**: The file at the local target path is replaced by a relative or absolute symbolic link pointing to a location inside the local mount point.
3. **FUSE Mount & VFS Cache Level**: An `rclone mount` process exposes remote cloud storage as a standard POSIX filesystem at a local mount point (such as `~/GoogleDrive`). MountSync relies on `rclone` Virtual File System (VFS) caching (`--vfs-cache-mode writes`) to handle synchronous write calls cleanly without blocking user applications.
4. **Remote Cloud Storage Level**: Behind the mount point, `rclone` streams local changes across the network to the actual remote cloud provider (Google Drive, Dropbox, Nextcloud, AWS S3, etc.).

### 1.2 Declarative Sync Map (`sync-map.conf`)

The source of truth for all managed items is the manifest file `sync-map.conf` stored inside the cloud vault (`MOSY_MOUNT_POINT/mosy_vault/sync-map.conf` or profile directory).

Each record defines:
- **Local relative path** (relative to `$HOME`)
- **Cloud relative path** (relative to vault root)
- **Tags** (comma-separated tags for conditional filtering)
- **Groups** (comma-separated environment or machine groups)

```text
.bashrc|.bashrc|dotfiles,shell|desktop,laptop
.config/nvim|.config/nvim|editor|dev-machine
```

---

## 2. Non-Destructive Safety Philosophy

MountSync adheres to strict data preservation principles. It never silently overwrites local unmanaged files or uncommitted cloud states.

### 2.1 Conflict Avoidance During Pull and Init

When executing `mosy init` or `mosy pull`:
- **Clean path**: If no file exists at the local target location, MountSync creates necessary parent directories and creates the symbolic link pointing to the cloud vault item.
- **Existing identical symlink**: If a symbolic link already points to the correct cloud vault target, MountSync leaves it unchanged.
- **Conflict detected**: If a real file, directory, or conflicting symlink already exists at the local target location, MountSync stops and triggers a timestamped backup before proceeding.

### 2.2 Timestamped Backup Strategy

Before replacing a conflicting local item, MountSync invokes `mosy_backup()`, which renames the conflicting file or directory using the configured extension (`MOSY_BACKUP_EXT`) appended with an ISO-style timestamp (`YYYYMMDD_HHMMSS`).

```text
Target Path:     ~/.bashrc
Backup Created:  ~/.bashrc.bak_20260813_165234
```

This ensures that:
- User modifications made locally prior to running `mosy pull` or `mosy init` are preserved on disk.
- Rolling back a conflict simply requires inspecting and moving `.bak_TIMESTAMP` files back into place.
- No automated operation performs an unrecoverable `rm -rf` or file truncation.

---

## 3. Systemd Service Integration and VFS Caching

To guarantee that cloud storage is transparently available at boot time, MountSync integrates with Systemd user services and `rclone` VFS caching.

### 3.1 Service Lifecycle (`mosy-mount.service`)

During installation, MountSync configures a Systemd user unit located at `~/.config/systemd/user/mosy-mount.service`:

```ini
[Unit]
Description=Rclone Mount for MountSync
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount GoogleDrive: /home/user/GoogleDrive --vfs-cache-mode writes
ExecStop=/bin/fusermount -u /home/user/GoogleDrive
Restart=on-failure

[Install]
WantedBy=default.target
```

Key aspects of this service:
- **Network Dependency**: Starts after `network-online.target` is reached.
- **Automatic Recovery**: Uses `Restart=on-failure` to remount if network interruptions disrupt the FUSE session.
- **Clean Unmounting**: Employs `fusermount -u` on service shutdown to prevent stale mount points.

### 3.2 Role of VFS Cache (`--vfs-cache-mode writes`)

Direct writes to network mounts can cause latency or failures in applications expecting immediate POSIX file system responses. `--vfs-cache-mode writes` acts as a write-ahead buffer:
1. Files opened for writing are written locally to `~/.cache/rclone/vfs/...`.
2. As soon as the file descriptor is closed, `rclone` asynchronously uploads the cached file to cloud storage in the background.
3. Subsequent read operations served during or after upload retrieve data seamlessly from cache or remote storage.

---

## 4. Codebase Architecture

MountSync is engineered around modular shell scripting principles: a lean executable frontend delegating to modular core routines and subcommand scripts.

```text
mountsync/
├── mosy                      # Main CLI entry point
├── install.sh                # Interactive installer & systemd service setup
├── src/
│   ├── core.sh               # Core initialization, settings, logging, backup routines
│   ├── secrets.sh            # Secret leak prevention and credential pattern scanner
│   ├── ignore.sh             # Custom ignore pattern matching (.mosyignore)
│   └── commands/             # Individual subcommand handlers
│       ├── add.sh            # Adds local file/dir to cloud vault & symlinks
│       ├── config.sh         # Manages configuration & profile settings
│       ├── diff.sh           # Change inspection (backups, vault, profiles)
│       ├── doctor.sh         # Deep diagnostics & automated remediation (--fix)
│       ├── info.sh           # Environment overview dashboard & metrics (--json)
│       ├── init.sh           # Links all items in manifest for setup
│       ├── list.sh           # Formats & outputs managed files
│       ├── pull.sh           # Links missing items from sync map
│       ├── remove.sh         # Restores cloud item back to local path
│       ├── status.sh         # Verifies symlinks & integrity status
│       ├── uninstall.sh      # Cleanly removes MountSync & unwraps links
│       ├── update.sh         # Updates repository to latest version
│       └── version.sh        # Displays version information
└── docs/                     # Diataxis-structured documentation suite
    ├── README.md             # Documentation portal index
    ├── tutorials/            # Learning-oriented guides
    ├── how-to/               # Problem-oriented recipes
    ├── reference/            # Technical manuals and specifications
    └── explanation/          # Architecture and mental models
```

### 4.1 Single Entry Point (`mosy`)

The `mosy` script acts as the entry parser:
1. **Global Option Dispatch**: Extracts global flags such as `-p` / `--profile` and sets environment variables (`MOSY_PROFILE`).
2. **Environment Loading**: Sources `src/core.sh`, which loads `~/.config/mosy/config` and enforces default environment parameters (`MOSY_REMOTE_NAME`, `MOSY_MOUNT_POINT`, `MOSY_CLOUD_DIR`, `MOSY_PROFILE_DIR`).
3. **Subcommand Dispatch**: Dynamically sources the matching command file from `src/commands/${command}.sh` and executes `cmd_${command}` passing remaining arguments.

### 4.2 Core Architecture (`src/core.sh`, `src/secrets.sh`, `src/ignore.sh`)

- **`load_settings`**: Loads configuration files while respecting pre-set environment overrides. Resolves active profiles and sync map file locations (`sync-map.conf`).
- **`check_mount`**: Ensures the cloud mount point is currently active via `platform_is_mounted`.
- **`foreach_mapping`**: Iterator function that reads `sync-map.conf`, evaluates tags/groups filters (`MOSY_FILTER_TAG`, `MOSY_FILTER_GROUP`), performs automated platform tag matching, and passes matching entries to callback functions.
- **`mosy_backup`**: Implements safety backups for local path collisions.
- **`ignore.sh`**: Handles ignore pattern evaluation and hierarchical traversal up to `$HOME`.
- **`secrets.sh`**: Inspects files for sensitive credentials, keys, and tokens prior to cloud staging.

### 4.3 Platform Adapter Architecture (`src/platform/`)

MountSync decouples operating system differences (service managers, mount checks, symlink behaviors, CLI wrappers) into dedicated platform modules loaded dynamically by `src/platform/init.sh`:

```text
                     ┌───────────────────────────────┐
                     │          install.sh           │
                     │          src/core.sh          │
                     └───────────────┬───────────────┘
                                     │
                        [src/platform/detect.sh]
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           ▼                         ▼                         ▼
 🐧 src/platform/linux.sh   🍏 src/platform/darwin.sh  🪟 src/platform/windows.sh
 • Systemd user service     • Launchd .plist agent    • NTFS symlinks
 • POSIX mount validation   • df/mount validation     • mosy.cmd & mosy.ps1
 • ~/.config/ paths         • LaunchAgents paths      • Background runner
```

1. **`detect.sh`**: Detects whether the host environment is `linux`, `darwin` (macOS), `windows` (MSYS/Git Bash), or `wsl`.
2. **`linux.sh`**: Implements `systemd` user service templates (`mosy-mount.service`) and POSIX mount check routines.
3. **`darwin.sh`**: Generates and manages macOS LaunchAgent plists (`~/Library/LaunchAgents/com.mountsync.rclone.plist`) via `launchctl`.
4. **`windows.sh`**: Configures native NTFS symlinks (`MSYS=winsymlinks:nativestrict`), Windows background runners (`mount-runner.cmd` / `.vbs`), and CLI shims (`mosy.cmd`, `mosy.ps1`) in `~/.local/bin` for native Command Prompt and PowerShell usage.

---

## 5. Sequence Diagram: Data Flow During `mosy add`

```text
+------+             +------+            +-----------+         +-------------+
| User |             | mosy |            |  core.sh  |         | Cloud Vault |
+------+             +------+            +-----------+         +-------------+
   |                    |                      |                      |
   |-- mosy add PATH -->|                      |                      |
   |                    |-- load_settings ---->|                      |
   |                    |-- check_mount ------>|                      |
   |                    |                      |-- is_mounted? ------>|
   |                    |                      |<-- true -------------|
   |                    |                                             |
   |                    |-- is_ignored? (preserves local ignored) ---->|
   |                    |-- mkdir -p vault_dir ---------------------->|
   |                    |-- mv non-ignored files -> vault/ ----------->|
   |                    |-- ln -sf vault/files -> local/ ------------->|
   |                    |-- update_map (sync-map.conf) --------------->|
   |<-- Success Message-|                                             |
```

---

## 6. Sequence Diagram: Conflict Resolution During `mosy init`

```text
+------+             +------+            +-----------+         +-------------+
| User |             | mosy |            |  core.sh  |         | Cloud Vault |
+------+             +------+            +-----------+         +-------------+
   |                    |                      |                      |
   |-- mosy init ------>|                      |                      |
   |                    |-- foreach_mapping -->|                      |
   |                    |   (iterates sync-map)|                      |
   |                    |                      |                      |
   |                    |  [Local File Exists & Is Not Symlink]       |
   |                    |  ------------------------------------       |
   |                    |   | mosy_backup()                           |
   |                    |   | mv $HOME/PATH ->                        |
   |                    |   | $HOME/PATH.bak_TIMESTAMP                |
   |                    |                                             |
   |                    |-- ln -sf cloud_path $HOME/PATH ------------>|
   |<-- Output Log -----|                                             |
```

---

## Related Documentation

* [Quickstart Tutorial](../tutorials/quickstart.md)
* [CLI Reference](../reference/cli.md)
* [Configuration Reference](../reference/configuration.md)
* [Documentation Portal](../README.md)
