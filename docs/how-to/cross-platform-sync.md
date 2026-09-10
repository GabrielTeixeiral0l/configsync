# How to Synchronize Dotfiles Across Linux, macOS, and Windows

This guide explains how to synchronize your configuration files across multiple different operating systems (Linux, macOS, and Windows) using MountSync's **Platform Adapter Layer** and **`mosy link`** command.

---

## The Challenge: Divergent OS Configuration Paths

Different operating systems store application settings in different directory hierarchies:

| Application | Linux Path | macOS Path | Windows Path |
| :--- | :--- | :--- | :--- |
| **VS Code** | `~/.config/Code/User/settings.json` | `~/Library/Application Support/Code/User/settings.json` | `AppData/Roaming/Code/User/settings.json` |
| **Neovim** | `~/.config/nvim/init.lua` | `~/.config/nvim/init.lua` | `AppData/Local/nvim/init.lua` |
| **Starship** | `~/.config/starship.toml` | `~/.config/starship.toml` | `AppData/Local/starship.toml` |
| **Git** | `~/.gitconfig` | `~/.gitconfig` | `~/.gitconfig` *(Universal)* |
| **Alacritty** | `~/.config/alacritty/alacritty.toml` | `~/.config/alacritty/alacritty.toml` | `AppData/Roaming/alacritty/alacritty.toml` |

MountSync solves this using **1-to-N Cloud Mapping** in `sync-map.conf`: divergent local paths across machines all point to the **same single cloud vault item**, while `mosy init` automatically filters and creates only the paths appropriate for the current host OS.

---

## Workflow Overview

```text
 🐧 Linux Workstation             🍏 macOS Laptop                  🪟 Windows PC
 ~/.config/Code/...               ~/Library/App Support/Code/...   %APPDATA%/Code/...
        │                                 │                               │
        ▼ (mosy add)                      ▼ (mosy link)                   ▼ (mosy link)
        └────────────────────────► ☁️ Cloud Vault ◄────────────────────────┘
                               (.config/Code/User/settings.json)
```

---

## Recipe 1: Initial Setup on Machine 1 (Linux)

1. Add your configurations to MountSync with appropriate platform tags:
   ```bash
   # Add VS Code settings tagged for Linux
   mosy add ~/.config/Code/User/settings.json -t linux -g editors

   # Add Neovim config (shared between Linux & macOS)
   mosy add ~/.config/nvim/init.lua -t linux,macos -g editors

   # Add Git config (universal for all OSes)
   mosy add ~/.gitconfig -t all -g vcs
   ```

2. Confirm that items are safely moved to the vault and symlinked:
   ```bash
   mosy status
   ```

---

## Recipe 2: Adding a Second Machine (macOS)

1. Install MountSync on your Mac and connect to the same cloud remote:
   ```bash
   curl -sL https://raw.githubusercontent.com/GabrielTeixeiral0l/MountSync/main/install.sh | bash
   ```

2. Run `mosy init` without flags:
   ```bash
   mosy init
   ```
   > [!NOTE]
   > `mosy init` automatically links universal (`all`) and macOS-compatible items (`.gitconfig`, `nvim/init.lua`). It automatically skips Linux-only and Windows-only paths!

3. Link macOS-specific paths (like VS Code) to the existing cloud vault item using `mosy link`:
   ```bash
   mosy link ~/Library/Application\ Support/Code/User/settings.json .config/Code/User/settings.json
   ```
   * MountSync validates the cloud target exists.
   * Auto-assigns the `macos` tag.
   * Inherits the `editors` group.
   * Creates the local symlink in `~/Library/Application Support/...`.

---

## Recipe 3: Adding a Third Machine (Windows Native / Git Bash)

1. Run the MountSync installer inside Git Bash:
   ```bash
   curl -sL https://raw.githubusercontent.com/GabrielTeixeiral0l/MountSync/main/install.sh | bash
   ```

2. Run `mosy init` in your terminal (Command Prompt, PowerShell, or Git Bash):
   ```powershell
   mosy init
   ```
   * Links universal items like `~/.gitconfig`.

3. Map Windows AppData paths to existing cloud files using `mosy link`:
   ```powershell
   # Link VS Code settings
   mosy link ~/AppData/Roaming/Code/User/settings.json .config/Code/User/settings.json

   # Link Neovim settings
   mosy link ~/AppData/Local/nvim/init.lua .config/nvim/init.lua
   ```

---

## Recipe 4: Rebuilding Any Machine in the Future

Once the mapping is established, you never need to remember or specify tags again. On **any** computer (Linux, macOS, or Windows), simply run:

```bash
mosy init
```

* **On Linux:** Links `.config/Code/User/settings.json`, `.config/nvim/init.lua`, and `.gitconfig`.
* **On macOS:** Links `Library/Application Support/Code/User/settings.json`, `.config/nvim/init.lua`, and `.gitconfig`.
* **On Windows:** Links `AppData/Roaming/Code/User/settings.json`, `AppData/Local/nvim/init.lua`, and `.gitconfig`.

---

## Recipe 5: Live Cross-Platform Updates

Because MountSync uses direct symbolic links into the mounted Cloud Vault:
* When you change a setting in **VS Code on Windows**, the change is instantly visible in **VS Code on Linux and macOS**.
* When you edit `init.lua` on **macOS**, **Windows and Linux** receive the update immediately.
* No manual `push` or `pull` is required for live configuration edits.
