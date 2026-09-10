# MountSync

![Tests](https://github.com/GabrielTeixeiral0l/MountSync/actions/workflows/tests.yml/badge.svg)
![License](https://img.shields.io/github/license/GabrielTeixeiral0l/MountSync?color=blue)
![Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)

MountSync (`mosy`) is a minimalist, cloud-agnostic orchestrator for dotfiles and directory synchronization. It leverages [`rclone`](https://rclone.org/) to keep your development environment and system configurations synchronized across multiple machines (**Linux**, **macOS**, and **Windows**) using symbolic links (`symlinks`).

Original files are moved to a centralized Cloud Vault and replaced locally with symbolic links. A central registry (`sync-map.conf`) maps these items, enabling instant and safe replication on any machine.

---

## Supported Platforms

* 🐧 **Linux:** Native `systemd` user service & POSIX mount support.
* 🍏 **macOS:** Native `launchd` LaunchAgent (`~/Library/LaunchAgents/com.mountsync.rclone.plist`).
* 🪟 **Windows (Native / Git Bash + WSL):** Native NTFS symlinks, background runners, and CLI shims (`mosy.cmd` & `mosy.ps1`) for transparent execution from Command Prompt and PowerShell.

---

## Quick Start

### Installation

* **🐧 Linux / 🍏 macOS:**
  ```bash
  curl -sL https://raw.githubusercontent.com/GabrielTeixeiral0l/MountSync/main/install.sh | bash
  ```

* **🪟 Windows (PowerShell):**
  ```powershell
  irm https://raw.githubusercontent.com/GabrielTeixeiral0l/MountSync/main/install.ps1 | iex
  ```

### 30-Second Example

Add your local `.bashrc` file to MountSync with a group and tag, then check the system status:

```bash
# Add ~/.bashrc to MountSync vault under the 'dotfiles' group and 'shell' tag
mosy add ~/.bashrc -g dotfiles -t shell

# Verify the status of managed items and background mount service
mosy status
```

### Cross-Platform Sync Example (e.g. Linux $\leftrightarrow$ macOS $\leftrightarrow$ Windows)

On a second machine with divergent file paths (like VS Code or Neovim):

```bash
# On macOS:
mosy link ~/Library/Application\ Support/Code/User/settings.json .config/Code/User/settings.json

# On Windows (PowerShell / CMD):
mosy link ~/AppData/Roaming/Code/User/settings.json .config/Code/User/settings.json
```

---

## Documentation

Explore the detailed guides, tutorials, and technical references available in the [MountSync Documentation Portal](docs/README.md):

| Category | Purpose | Document Links |
| :--- | :--- | :--- |
| **Tutorial** | Step-by-step introduction for beginners | [Quickstart Tutorial](docs/tutorials/quickstart.md) |
| **How-to Guides** | Task-oriented recipes solving practical real-world problems | [Cross-Platform Sync Guide](docs/how-to/cross-platform-sync.md)<br>[Multiple Profiles Guide](docs/how-to/profiles.md)<br>[Tags & Groups Guide](docs/how-to/tags-and-groups.md)<br>[Ignore Patterns Guide](docs/how-to/mosyignore.md)<br>[Diagnostics & Auto-Remediation Guide](docs/how-to/doctor-and-diagnostics.md)<br>[Diff & Backups Inspection Guide](docs/how-to/diff-and-backups.md)<br>[Secret Leak Prevention Guide](docs/how-to/secrets-prevention.md)<br>[Snapshots & Recovery Guide](docs/how-to/snapshots-and-recovery.md)<br>[Multi-Machine Sync Guide](docs/how-to/multi-machine-sync.md) |
| **Reference** | Exhaustive technical descriptions of CLI commands and configuration | [CLI Reference](docs/reference/cli.md)<br>[Configuration Reference](docs/reference/configuration.md) |
| **Architecture** | System design, mental model, and data flow specifications | [Architecture & Design](docs/explanation/architecture.md) |

---

## Command Summary Table

| Command | Example Syntax | Description | Reference Link |
| :--- | :--- | :--- | :--- |
| **`add`** | `mosy add ~/.bashrc -g dotfiles -t main` | Adds an item to the vault and replaces the local file with a symlink. | [Details](docs/reference/cli.md#1-add) |
| **`link`** | `mosy link ~/AppData/... .config/...` | Maps local divergent OS paths to existing cloud vault files. | [Details](docs/reference/cli.md#1b-link) |
| **`init`** | `mosy init --tag work` | Rebuilds local symlinks based on the synchronization map. | [Details](docs/reference/cli.md#2-init) |
| **`pull`** | `mosy pull -g config` | Non-destructively pulls missing items from the cloud vault. | [Details](docs/reference/cli.md#3-pull) |
| **`list`** | `mosy list --tag dev` | Lists all managed files along with their tags and groups. | [Details](docs/reference/cli.md#4-list) |
| **`status`** | `mosy status --json` | Inspects cloud mount state, Systemd service status, and link validity. | [Details](docs/reference/cli.md#5-status) |
| **`doctor`** | `mosy doctor --fix` | Deep system diagnostics and automatic remediation of setup issues. | [Details](docs/reference/cli.md#6-doctor) |
| **`info`** | `mosy info --json` | Environment overview dashboard and managed dotfile metrics. | [Details](docs/reference/cli.md#7-info) |
| **`diff`** | `mosy diff ~/.bashrc -b` | Inspects differences against safety backups, vault copies, or profiles. | [Details](docs/reference/cli.md#8-diff) |
| **`history`** | `mosy history ~/.bashrc` | Lists timestamped backup snapshots in reverse chronological order. | [Details](docs/reference/cli.md#9-history) |
| **`rollback`**| `mosy rollback ~/.bashrc`| Restores a previous snapshot with automatic safety backup. | [Details](docs/reference/cli.md#10-rollback) |
| **`backup`**  | `mosy backup ~/.bashrc`  | Manually creates a timestamped safety backup snapshot. | [Details](docs/reference/cli.md#11-backup) |
| **`edit`**    | `mosy edit bashrc`       | Opens managed dotfile in `$EDITOR` with automated safety backup. | [Details](docs/reference/cli.md#12-edit) |
| **`which`**   | `mosy which ~/.bashrc`   | Inspects if a local path is managed and verifies symlink health. | [Details](docs/reference/cli.md#13-which) |
| **`clean`**   | `mosy clean --older-than 30d` | Purges obsolete backup snapshots safely with dry-run support. | [Details](docs/reference/cli.md#14-clean) |
| **`tree`**    | `mosy tree --by-group`   | Renders an ASCII tree of managed dotfiles with symlink health badges. | [Details](docs/reference/cli.md#15-tree) |
| **`remove`**  | `mosy remove ~/.bashrc`  | Reverts symlink to a regular file and removes it from the sync map. | [Details](docs/reference/cli.md#16-remove) |
| **`config`**  | `mosy config set MOSY_LOG_LEVEL DEBUG` | Views or updates MountSync configuration settings. | [Details](docs/reference/cli.md#17-config) |
| **`version`** | `mosy version`           | Displays the installed version and checks for updates. | [Details](docs/reference/cli.md#18-version) |
| **`update`**  | `mosy update`            | Updates MountSync to the latest released version. | [Details](docs/reference/cli.md#19-update) |
| **`uninstall`**| `mosy uninstall`        | Removes MountSync and optionally restores original files. | [Details](docs/reference/cli.md#20-uninstall) |

---

## Architecture Overview

MountSync follows a clean core-and-command architecture designed for simplicity and reliability:

1. **Single Entry Point (`mosy`)**: A lightweight script that parses global flags (such as profile selection) and dispatches commands.
2. **Core Engine (`src/core.sh`)**: Manages configuration parsing, logging, mount status verification, and `sync-map.conf` processing.
3. **Modular Subcommands (`src/commands/*.sh`)**: Independent subcommands containing isolated execution logic for maintainability.

---

## Troubleshooting

### Cloud Drive Not Mounted
If MountSync reports that the cloud drive is not mounted:
1. Run system diagnostics: `mosy doctor --fix`
2. Verify service status: `systemctl --user status mosy-mount.service`
3. Check mount point directly: `mountpoint /path/to/mount`
4. Verify that your remote configuration in `~/.config/mosy/config` matches `rclone config`.

### Symlink Conflicts
MountSync does not overwrite existing local files during `pull` operations. If a conflict occurs, the file is skipped with a warning. Use `mosy init` (which generates timestamped backups) or resolve the local file manually.

---

## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more details.
