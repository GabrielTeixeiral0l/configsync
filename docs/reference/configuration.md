# Configuration Reference

This reference document specifies the configuration system for MountSync, detailing evaluation precedence, configuration variables, and command-line configuration management tools.

---

## Precedence Order

MountSync resolves configuration settings using a strict priority order. Values set at higher precedence levels override values set at lower levels:

1. **Environment Variables**: Variables set in the environment or passed inline (for example, `MOSY_DRY_RUN=true`).
2. **Configuration File**: Settings stored in `~/.config/mosy/config` (or profile-specific configuration files).
3. **Default Values**: Internal fallbacks applied when a key is omitted from both environment variables and the configuration file.

---

## Configuration Variables

The following reference table documents all supported MountSync configuration variables.

| Environment Variable | Description | Default Value | Valid Values |
| :--- | :--- | :--- | :--- |
| `MOSY_REMOTE_NAME` | Name of the configured `rclone` remote | None (Required) | String matching an `rclone` remote name (e.g., `gdrive:`, `dropbox:`) |
| `MOSY_MOUNT_POINT` | Absolute path to the local mount point for cloud storage | `${HOME}/GoogleDrive` | Valid absolute filesystem path |
| `MOSY_VFS_CACHE` | VFS cache mode passed to `rclone mount` | `writes` | `off`, `minimal`, `writes`, `full` |
| `MOSY_CLOUD_DIR` | Root directory inside the cloud drive for MountSync storage | `${MOSY_MOUNT_POINT}/mosy_vault` | Valid absolute filesystem path |
| `MOSY_BACKUP_EXT` | File extension appended to conflicting files during sync operations | `.bak` | File extension string (e.g., `.bak`, `.old`) |
| `MOSY_LOG_LEVEL` | Verbosity level for CLI execution output | `INFO` | `INFO`, `DEBUG`, `SILENT` |
| `MOSY_DRY_RUN` | Simulates file sync operations without executing changes | `false` | `true`, `false` |
| `MOSY_SCAN_SECRETS` | Scans for unencrypted credentials before adding files | `false` | `true`, `false` |
| `MOSY_SAFETY_GUARD` | Safety guard for DBs, locks & churn on add/doctor | `true` | `true`, `false` |
| `MOSY_PROFILE` | Active MountSync profile profile identifier | `default` | Valid profile name string |

---

## Configuration File Format

The configuration file is located at `~/.config/mosy/config`. It uses POSIX shell key-value assignment syntax.

### Example `~/.config/mosy/config`

```bash
MOSY_REMOTE_NAME="gdrive:"
MOSY_MOUNT_POINT="/home/user/GoogleDrive"
MOSY_CLOUD_DIR="/home/user/GoogleDrive/mosy_vault"
MOSY_VFS_CACHE="writes"
MOSY_BACKUP_EXT=".bak"
MOSY_LOG_LEVEL="INFO"
MOSY_DRY_RUN="false"
MOSY_SCAN_SECRETS="false"
MOSY_SAFETY_GUARD="true"
```

---

- Other non-empty lines define regular expressions matched against file contents (e.g. `MY_COMPANY_API_KEY_[0-9]+`).
- Lines starting with `#` are treated as comments.

---

## Sync Map Manifest (`sync-map.conf`)

The sync map manifest is stored in the Cloud Vault (`$MOSY_CLOUD_DIR/sync-map.conf`) and uses a pipe-delimited (`|`) 4-column format:

```text
LOCAL_REL_PATH | CLOUD_REL_PATH | TAGS | GROUPS
```

* **`LOCAL_REL_PATH`**: Path relative to the local user's `$HOME` (e.g., `.config/Code/User/settings.json`, `Library/Application Support/Code/User/settings.json`, or `AppData/Roaming/Code/User/settings.json`).
* **`CLOUD_REL_PATH`**: Path relative to the Cloud Vault directory (`$MOSY_CLOUD_DIR`).
* **`TAGS`**: Comma-separated tags (e.g., `linux`, `macos`, `windows`, `unix`, `all`, `work`, `laptop`).
* **`GROUPS`**: Comma-separated groups (e.g., `editors`, `shell`, `vcs`).

### Platform Tag Resolution Rules

When running `mosy init`, `mosy pull`, or `mosy status` without an explicit `--tag` filter:
* **Untagged entries** (empty tag) are considered universal and match on **all platforms**.
* **Entries with tag `all`** match on **all platforms**.
* **Entries with tag `unix`** match on **Linux**, **macOS**, and **WSL**.
* **Platform-specific tags** (`linux`, `macos`/`darwin`, `windows`, `wsl`) match **only** when running on that specific operating system. Foreign OS paths are cleanly skipped.

---

## Configuration Management (`mosy config`)

The `mosy config` subcommand provides utility tools to inspect and modify MountSync configuration settings directly.

### View Current Configuration (`mosy config`)

Running `mosy config` without arguments prints the current configuration state evaluated against precedence rules:

```bash
mosy config
```

Example output:

```text
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
```

### Modify Configuration (`mosy config set`)

The `mosy config set` command writes configuration settings directly to `~/.config/mosy/config`:

```bash
mosy config set KEY VALUE
```

#### Parameters

* `KEY`: The configuration key to modify (e.g., `MOSY_REMOTE_NAME`, `MOSY_LOG_LEVEL`, `MOSY_SCAN_SECRETS`).
* `VALUE`: The value to assign to the key.

#### Examples

Set the remote drive name:

```bash
mosy config set MOSY_REMOTE_NAME "mygdrive:"
```

Set verbosity level to debug:

```bash
mosy config set MOSY_LOG_LEVEL "DEBUG"
```

Enable dry-run mode by default:

```bash
mosy config set MOSY_DRY_RUN "true"
```

Enable secret scanning by default:

```bash
mosy config set MOSY_SCAN_SECRETS "true"
```

---

## Related Documents

* [CLI Reference](cli.md)
* [Profiles Guide](../how-to/profiles.md)
* [Ignore Patterns Guide](../how-to/mosyignore.md)
* [Secret Leak Prevention Guide](../how-to/secrets-prevention.md)
* [Architecture & Design](../explanation/architecture.md)
* [Documentation Portal](../README.md)
