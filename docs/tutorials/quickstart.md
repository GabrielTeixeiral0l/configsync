# MountSync Quickstart Tutorial

Welcome to MountSync. This tutorial is a step-by-step guide designed for complete beginners. By following this guide, you will learn how MountSync works by setting up system requirements, installing the tool, managing your first configuration file (`~/.bashrc`), inspecting system status, and simulating how to replicate your environment on a second machine.

---

## Learning Objectives

In this tutorial, you will:

1. Install MountSync and verify its prerequisites (`rclone` and `fuse3`).
2. Add your first dotfile to the MountSync vault and learn what happens under the hood.
3. Check the health and status of your managed items.
4. Simulate setting up a second machine to replicate your environment seamlessly.

---

## Step 1: System Requirements and Installation

Before installing MountSync, ensure your Linux system has the necessary dependencies installed. MountSync relies on `rclone` to communicate with cloud storage providers and `fuse3` to mount cloud drives locally.

### Prerequisites & Installing rclone

MountSync relies on `rclone` to communicate with cloud storage providers (Google Drive, OneDrive, Dropbox, S3, etc.).

* **Linux (Ubuntu/Debian):**
  ```bash
  sudo apt update && sudo apt install -y rclone fuse3
  ```
* **macOS:**
  ```bash
  brew install rclone
  ```
* **Windows (Git Bash):**
  ```powershell
  winget install Rclone.Rclone
  ```

Configure your cloud remote (if you haven't already):
```bash
rclone config
```

### Installing MountSync

Install MountSync by running the official installation script:

```bash
curl -sL https://raw.githubusercontent.com/GabrielTeixeiral0l/MountSync/main/install.sh | bash
```

The installer automatically adapts to your operating system:
* **Linux:** Generates a `systemd` user service (`mosy-mount.service`).
* **macOS:** Generates a `launchd` agent (`~/Library/LaunchAgents/com.mountsync.rclone.plist`).
* **Windows:** Configures background runner scripts and generates `mosy.cmd` and `mosy.ps1` CLI shims in `~/.local/bin` so you can use `mosy` directly from Command Prompt or PowerShell!

The installation script performs the following tasks automatically:
- Checks for system dependencies (`rclone`, `fuse3`).
- Downloads and places the `mosy` executable into your executable path (typically `~/.local/bin` or `/usr/local/bin`).
- Sets up initial configuration files in `~/.config/mosy/`.
- Configures the background mount service (`mosy-mount.service`).

To confirm that the installation succeeded, run:

```bash
mosy version
```

You should see the installed MountSync version output in your terminal.

---

## Step 2: Adding Your First Dotfile

Now that MountSync is installed, let us manage your first configuration file: your shell environment file (`~/.bashrc`).

Run the following command to add `~/.bashrc` to MountSync under the `main` tag and `dotfiles` group:

```bash
mosy add ~/.bashrc -t main -g dotfiles
```

### What Happened Under the Hood?

When you run `mosy add ~/.bashrc -t main -g dotfiles`, MountSync performs three distinct steps automatically:

1. **Vault Transfer**: The original file (`~/.bashrc`) is moved from your local home directory into your mounted cloud vault directory (`~/.config/mosy/vault/default/bashrc`).
2. **Symlink Creation**: A symbolic link (symlink) is created at `~/.bashrc`, pointing directly to the file inside the cloud vault.
3. **Sync Registry Entry**: MountSync registers this mapping in the central registry file (`sync-map.conf`). This entry stores the relative path, assigned tags (`main`), and groups (`dotfiles`).

You can verify that `~/.bashrc` is now a symbolic link by running `ls -l`:

```bash
ls -l ~/.bashrc
```

The output will indicate that `~/.bashrc` points to the file in the vault path.

---

## Step 3: Inspecting Status and Managed Items

MountSync provides tools to inspect your environment and verify that all managed files remain intact and properly linked.

### Viewing Managed Items

To view all files and directories currently managed by MountSync under your active profile, run:

```bash
mosy list
```

To filter items by the group or tag assigned in Step 2, run:

```bash
mosy list -g dotfiles
```

This displays a table listing the path, group, and tag assigned to each item.

### Checking System Status

To check system integrity, background service status, and link validity, execute:

```bash
mosy status
```

The `status` subcommand checks:
- Whether the cloud drive mount is active.
- Whether the background Systemd service (`mosy-mount.service`) is running smoothly.
- Whether all managed symlinks point to valid targets in the vault without broken connections.

---

## Step 4: Simulating Setting Up a Second Machine

One of the main strengths of MountSync is replicating your dotfiles and system configurations on a new or second computer.

### Preparing the Second Machine

When setting up a second machine:

1. Install `rclone`, `fuse3`, and MountSync using the steps in Step 1.
2. Ensure `rclone` is configured with the same cloud remote and that the vault directory is mounted.

### Rebuilding Your Environment with `mosy init`

Once the cloud vault is mounted on the second machine, run:

```bash
mosy init
```

### What Happens During `mosy init`?

- MountSync reads the central `sync-map.conf` from the cloud vault.
- It iterates through every registered entry.
- If a regular file already exists locally, MountSync safely backs it up to `FILE.bak_TIMESTAMP`.
- It creates the corresponding symbolic links pointing to the vault files on the second machine.

You can also selectively initialize specific subsets of your configuration using tags or groups:

```bash
mosy init -t main -g dotfiles
```

Congratulations. You have completed the Quickstart Tutorial. You now know how to install MountSync, manage dotfiles using `mosy add`, inspect system status with `mosy list` and `mosy status`, and replicate your setup across machines with `mosy init`.

---

## Next Steps

To explore more advanced features of MountSync, consult the following documentation:

- [Tags and Groups Guide](../how-to/tags-and-groups.md): Learn how to organize configurations for different environments.
- [Multiple Profiles Guide](../how-to/profiles.md): Manage separate work and personal vaults.
- [Multi-Machine Sync Guide](../how-to/multi-machine-sync.md): Replicate configurations across multiple devices.
- [CLI Reference](../reference/cli.md): View detailed parameter listings for all `mosy` commands.
- [Documentation Portal](../README.md): Return to the documentation index.
