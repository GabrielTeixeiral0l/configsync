#!/usr/bin/env bats
# MountSync - tests/e2e_cross_platform_3os.bats
# End-to-End Multi-Machine Test across 3 Operating Systems (Linux, macOS, Windows)
# Real Apps: VSCode, Neovim, Git, and Starship

load 'test_helper.bash'

setup() {
    common_setup
    export SHARED_CLOUD="$TEST_HOME/SharedCloudVault"
    export MOSY_MOUNT_POINT="$SHARED_CLOUD"
    export MOSY_CLOUD_DIR="$SHARED_CLOUD/mosy_vault"
    mkdir -p "$MOSY_CLOUD_DIR"

    # Virtual Machines / OS Homes
    export LINUX_HOME="$TEST_HOME/machine_linux"
    export MACOS_HOME="$TEST_HOME/machine_macos"
    export WIN_HOME="$TEST_HOME/machine_windows"

    mkdir -p "$LINUX_HOME" "$MACOS_HOME" "$WIN_HOME"

    # Helper function to switch active machine environment
    set_machine_env() {
        local machine="$1"
        case "$machine" in
            linux)
                export HOME="$LINUX_HOME"
                export MOSY_OS_OVERRIDE="linux"
                ;;
            macos)
                export HOME="$MACOS_HOME"
                export MOSY_OS_OVERRIDE="darwin"
                ;;
            windows)
                export HOME="$WIN_HOME"
                export MOSY_OS_OVERRIDE="windows"
                ;;
        esac

        mkdir -p "$HOME/.config/mosy"
        cat <<EOF > "$HOME/.config/mosy/config"
MOSY_REMOTE_NAME=shared-cloud
MOSY_MOUNT_POINT=$SHARED_CLOUD
MOSY_CLOUD_DIR=$MOSY_CLOUD_DIR
EOF
    }
}

@test "Cross-Platform 3-OS: Full real-world sync for VS Code, Neovim, Git and Starship" {
    # =========================================================================
    # STEP 1: Linux Machine - Setup initial real application configurations
    # =========================================================================
    set_machine_env linux

    # 1. VS Code on Linux (~/.config/Code/User/settings.json)
    mkdir -p "$HOME/.config/Code/User"
    cat <<'EOF' > "$HOME/.config/Code/User/settings.json"
{
  "editor.fontSize": 14,
  "editor.tabSize": 2,
  "workbench.colorTheme": "Catppuccin Mocha",
  "files.autoSave": "afterDelay"
}
EOF

    # 2. Neovim on Linux (~/.config/nvim/init.lua)
    mkdir -p "$HOME/.config/nvim"
    cat <<'EOF' > "$HOME/.config/nvim/init.lua"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.shiftwidth = 2
vim.g.mapleader = " "
EOF

    # 3. Git on Linux (~/.gitconfig)
    cat <<'EOF' > "$HOME/.gitconfig"
[user]
    name = MultiPlatform Dev
    email = dev@example.com
[core]
    editor = nvim
    autocrlf = input
EOF

    # 4. Starship prompt on Linux (~/.config/starship.toml)
    mkdir -p "$HOME/.config"
    cat <<'EOF' > "$HOME/.config/starship.toml"
add_newline = false
[character]
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"
EOF

    # Add items from Linux
    run mosy add "$HOME/.config/Code/User/settings.json" -t linux -g editors
    assert_success

    run mosy add "$HOME/.config/nvim/init.lua" -t linux,macos -g editors
    assert_success

    run mosy add "$HOME/.gitconfig" -t all -g vcs
    assert_success

    run mosy add "$HOME/.config/starship.toml" -t linux,macos -g shell
    assert_success

    # Verify symlinks created on Linux
    [ -L "$HOME/.config/Code/User/settings.json" ]
    [ -L "$HOME/.config/nvim/init.lua" ]
    [ -L "$HOME/.gitconfig" ]
    [ -L "$HOME/.config/starship.toml" ]

    # =========================================================================
    # STEP 2: macOS Machine - Link VS Code via 'mosy link' & run flagless 'mosy init'
    # =========================================================================
    set_machine_env macos

    # On macOS, init without flags automatically links universal and macOS items (git, nvim, starship)
    run mosy init
    assert_success

    # Link macOS-specific VS Code location to existing vault settings
    run mosy link "$HOME/Library/Application Support/Code/User/settings.json" ".config/Code/User/settings.json"
    assert_success

    # Verify macOS specific paths were created as symlinks to the shared vault
    local mac_vscode="$HOME/Library/Application Support/Code/User/settings.json"
    local mac_nvim="$HOME/.config/nvim/init.lua"
    local mac_git="$HOME/.gitconfig"
    local mac_starship="$HOME/.config/starship.toml"

    assert_file_exists "$mac_vscode"
    assert_file_exists "$mac_nvim"
    assert_file_exists "$mac_git"
    assert_file_exists "$mac_starship"

    [ -L "$mac_vscode" ]
    [ -L "$mac_nvim" ]
    [ -L "$mac_git" ]
    [ -L "$mac_starship" ]

    # Verify VS Code config on macOS matches Linux
    run grep '"workbench.colorTheme": "Catppuccin Mocha"' "$mac_vscode"
    assert_success

    # Verify Neovim config on macOS matches Linux
    run grep 'vim.opt.number = true' "$mac_nvim"
    assert_success

    # Verify Windows-only paths were NOT created on macOS
    [ ! -e "$HOME/AppData" ]

    # =========================================================================
    # STEP 3: Windows Machine - Link AppData paths via 'mosy link' & run flagless 'mosy init'
    # =========================================================================
    set_machine_env windows

    # On Windows, init without flags automatically links universal items (.gitconfig)
    run mosy init
    assert_success

    # Link Windows AppData locations to existing vault items via 'mosy link'
    run mosy link "$HOME/AppData/Roaming/Code/User/settings.json" ".config/Code/User/settings.json"
    assert_success
    run mosy link "$HOME/AppData/Local/nvim/init.lua" ".config/nvim/init.lua"
    assert_success
    run mosy link "$HOME/AppData/Local/starship.toml" ".config/starship.toml"
    assert_success

    # Verify Windows specific AppData paths were created as symlinks
    local win_vscode="$HOME/AppData/Roaming/Code/User/settings.json"
    local win_nvim="$HOME/AppData/Local/nvim/init.lua"
    local win_git="$HOME/.gitconfig"
    local win_starship="$HOME/AppData/Local/starship.toml"

    assert_file_exists "$win_vscode"
    assert_file_exists "$win_nvim"
    assert_file_exists "$win_git"
    assert_file_exists "$win_starship"

    [ -L "$win_vscode" ]
    [ -L "$win_nvim" ]
    [ -L "$win_git" ]
    [ -L "$win_starship" ]

    # Verify VS Code config on Windows matches
    run grep '"editor.tabSize": 2' "$win_vscode"
    assert_success

    # Verify macOS-only paths were NOT created on Windows
    [ ! -e "$HOME/Library" ]

    # =========================================================================
    # STEP 4: Live 3-Way Synchronization Propagation across OSes
    # =========================================================================
    # 4.1. Windows edits VS Code theme & font size
    cat <<'EOF' > "$win_vscode"
{
  "editor.fontSize": 18,
  "editor.tabSize": 2,
  "workbench.colorTheme": "Tokyo Night Storm",
  "files.autoSave": "onFocusChange"
}
EOF

    # 4.2. macOS edits Neovim config (adds Lua LSP setup)
    set_machine_env macos
    cat <<'EOF' >> "$mac_nvim"
-- Added from macOS
vim.opt.cursorline = true
EOF

    # 4.3. Linux edits Git config (adds global pull rebase)
    set_machine_env linux
    cat <<'EOF' >> "$HOME/.gitconfig"
[pull]
    rebase = true
EOF

    # =========================================================================
    # STEP 5: Verification of Live Cross-Platform Updates
    # =========================================================================
    # Check Linux sees Windows' VS Code edit & macOS' Neovim edit
    run grep '"workbench.colorTheme": "Tokyo Night Storm"' "$HOME/.config/Code/User/settings.json"
    assert_success
    run grep 'vim.opt.cursorline = true' "$HOME/.config/nvim/init.lua"
    assert_success

    # Check macOS sees Windows' VS Code edit & Linux's Git edit
    set_machine_env macos
    run grep '"editor.fontSize": 18' "$HOME/Library/Application Support/Code/User/settings.json"
    assert_success
    run grep 'rebase = true' "$HOME/.gitconfig"
    assert_success

    # Check Windows sees macOS' Neovim edit & Linux's Git edit
    set_machine_env windows
    run grep 'vim.opt.cursorline = true' "$HOME/AppData/Local/nvim/init.lua"
    assert_success
    run grep 'rebase = true' "$HOME/.gitconfig"
    assert_success
}
