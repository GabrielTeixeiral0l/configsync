#!/usr/bin/env bats
# MountSync - tests/e2e_cross_platform_matrix.bats
# Comprehensive 100% Coverage Multi-OS Matrix Test Suite
# Topologies:
#   1. Homo-OS: Linux <-> Linux
#   2. Homo-OS: Windows <-> Windows
#   3. Homo-OS: macOS <-> macOS
#   4. Hetero-OS: Linux <-> Windows
#   5. Hetero-OS: Linux <-> macOS
#   6. Hetero-OS: macOS <-> Windows
#   7. Tri-OS Mesh: Linux + macOS + Windows (Real Apps: VSCode, Neovim, Git, Starship)
#   8. Selective Tag & Group Filtering across 3 Nodes
#   9. Multi-Profile Isolation across 3 Nodes (-p work vs -p personal)
#  10. Node Independence & Zero Data Loss on Unlink/Remove

load 'test_helper.bash'

setup() {
    common_setup
    export SHARED_CLOUD="$TEST_HOME/SharedCloudVault"
    export MOSY_MOUNT_POINT="$SHARED_CLOUD"
    export MOSY_CLOUD_DIR="$SHARED_CLOUD/mosy_vault"
    mkdir -p "$MOSY_CLOUD_DIR"

    # Virtual machine homes for 6 distinct nodes
    export LNX1_HOME="$TEST_HOME/node_linux1"
    export LNX2_HOME="$TEST_HOME/node_linux2"
    export WIN1_HOME="$TEST_HOME/node_win1"
    export WIN2_HOME="$TEST_HOME/node_win2"
    export MAC1_HOME="$TEST_HOME/node_mac1"
    export MAC2_HOME="$TEST_HOME/node_mac2"

    mkdir -p "$LNX1_HOME" "$LNX2_HOME" "$WIN1_HOME" "$WIN2_HOME" "$MAC1_HOME" "$MAC2_HOME"

    # Helper function to switch active node environment
    switch_node() {
        local node_type="$1"
        case "$node_type" in
            linux1)
                export HOME="$LNX1_HOME"
                export MOSY_OS_OVERRIDE="linux"
                ;;
            linux2)
                export HOME="$LNX2_HOME"
                export MOSY_OS_OVERRIDE="linux"
                ;;
            win1)
                export HOME="$WIN1_HOME"
                export MOSY_OS_OVERRIDE="windows"
                ;;
            win2)
                export HOME="$WIN2_HOME"
                export MOSY_OS_OVERRIDE="windows"
                ;;
            mac1)
                export HOME="$MAC1_HOME"
                export MOSY_OS_OVERRIDE="darwin"
                ;;
            mac2)
                export HOME="$MAC2_HOME"
                export MOSY_OS_OVERRIDE="darwin"
                ;;
        esac

        mkdir -p "$HOME/.config/mosy"
        cat <<EOF > "$HOME/.config/mosy/config"
MOSY_REMOTE_NAME=shared-cloud
MOSY_MOUNT_POINT=$SHARED_CLOUD
MOSY_CLOUD_DIR=$MOSY_CLOUD_DIR
EOF
        export MOSY_MAP_FILE="$MOSY_CLOUD_DIR/sync-map.conf"
    }
}

# =============================================================================
# CATEGORY A: HOMO-OS TOPOLOGIES (Same OS <-> Same OS)
# =============================================================================

@test "Matrix Scenario 1: Linux1 <-> Linux2 (Zero-tag default, Bi-directional sync, Pull)" {
    # 1. Linux1 adds bashrc and gitconfig with zero flags
    switch_node linux1
    echo 'export EDITOR=nvim' > "$HOME/.bashrc"
    echo '[user] name = LinuxDev' > "$HOME/.gitconfig"

    run mosy add "$HOME/.bashrc"
    assert_success
    run mosy add "$HOME/.gitconfig"
    assert_success

    [ -L "$HOME/.bashrc" ]
    [ -L "$HOME/.gitconfig" ]

    # 2. Linux2 joins and runs flagless init
    switch_node linux2
    run mosy init
    assert_success

    [ -L "$HOME/.bashrc" ]
    [ -L "$HOME/.gitconfig" ]
    run grep 'export EDITOR=nvim' "$HOME/.bashrc"
    assert_success

    # 3. Linux2 edits bashrc (adds alias)
    echo 'alias ll="ls -la"' >> "$HOME/.bashrc"

    # 4. Linux1 verifies live update
    switch_node linux1
    run grep 'alias ll="ls -la"' "$HOME/.bashrc"
    assert_success

    # 5. Linux1 adds a new file (.tmux.conf) and Linux2 uses mosy pull
    echo 'set -g mouse on' > "$HOME/.tmux.conf"
    run mosy add "$HOME/.tmux.conf"
    assert_success

    switch_node linux2
    [ ! -e "$HOME/.tmux.conf" ]
    run mosy pull
    assert_success
    [ -L "$HOME/.tmux.conf" ]
    run grep 'set -g mouse on' "$HOME/.tmux.conf"
    assert_success
}

@test "Matrix Scenario 2: Windows1 <-> Windows2 (AppData paths, shims, bi-directional sync)" {
    # 1. Windows1 adds AppData VSCode settings and nvim init.lua
    switch_node win1
    mkdir -p "$HOME/AppData/Roaming/Code/User"
    mkdir -p "$HOME/AppData/Local/nvim"
    echo '{"editor.fontSize": 15}' > "$HOME/AppData/Roaming/Code/User/settings.json"
    echo 'vim.opt.number = true' > "$HOME/AppData/Local/nvim/init.lua"

    run mosy add "$HOME/AppData/Roaming/Code/User/settings.json" -t windows -g editors
    assert_success
    run mosy add "$HOME/AppData/Local/nvim/init.lua" -t windows -g editors
    assert_success

    [ -L "$HOME/AppData/Roaming/Code/User/settings.json" ]
    [ -L "$HOME/AppData/Local/nvim/init.lua" ]

    # 2. Windows2 has pre-existing factory default settings
    switch_node win2
    mkdir -p "$HOME/AppData/Roaming/Code/User"
    echo '{"editor.fontSize": 12, "factory": true}' > "$HOME/AppData/Roaming/Code/User/settings.json"

    # Windows2 runs flagless init (should back up factory config and link cloud config)
    run mosy init
    assert_success

    [ -L "$HOME/AppData/Roaming/Code/User/settings.json" ]
    [ -L "$HOME/AppData/Local/nvim/init.lua" ]

    # Verify backed up factory config exists
    local bak_file
    bak_file=$(find "$HOME/AppData/Roaming/Code/User" -name "settings.json.bak_*" | head -n 1)
    [ -n "$bak_file" ]
    run grep 'factory' "$bak_file"
    assert_success

    # Verify active symlink has Windows1 content
    run grep '"editor.fontSize": 15' "$HOME/AppData/Roaming/Code/User/settings.json"
    assert_success

    # 3. Windows2 modifies font size to 18
    cat <<'EOF' > "$HOME/AppData/Roaming/Code/User/settings.json"
{"editor.fontSize": 18, "workbench.colorTheme": "Nord"}
EOF

    # 4. Windows1 immediately sees the change live
    switch_node win1
    run grep '"workbench.colorTheme": "Nord"' "$HOME/AppData/Roaming/Code/User/settings.json"
    assert_success
}

@test "Matrix Scenario 3: macOS1 <-> macOS2 (Library paths, zshrc, group filtering)" {
    # 1. macOS1 adds Library VS Code and zshrc
    switch_node mac1
    mkdir -p "$HOME/Library/Application Support/Code/User"
    echo '{"editor.fontSize": 14, "theme": "MacDark"}' > "$HOME/Library/Application Support/Code/User/settings.json"
    echo 'export ZSH_THEME="robbyrussell"' > "$HOME/.zshrc"

    run mosy add "$HOME/Library/Application Support/Code/User/settings.json" -t macos -g editors
    assert_success
    run mosy add "$HOME/.zshrc" -t macos,unix -g shell
    assert_success

    [ -L "$HOME/Library/Application Support/Code/User/settings.json" ]
    [ -L "$HOME/.zshrc" ]

    # 2. macOS2 joins and inits only 'editors' group
    switch_node mac2
    run mosy init -g editors
    assert_success

    # VS Code should be linked, but zshrc should NOT be linked yet
    [ -L "$HOME/Library/Application Support/Code/User/settings.json" ]
    [ ! -e "$HOME/.zshrc" ]

    # 3. macOS2 pulls remaining items
    run mosy pull
    assert_success
    [ -L "$HOME/.zshrc" ]

    # 4. macOS2 edits zshrc
    echo 'plugins=(git zsh-autosuggestions)' >> "$HOME/.zshrc"

    # 5. macOS1 receives update live
    switch_node mac1
    run grep 'zsh-autosuggestions' "$HOME/.zshrc"
    assert_success
}

# =============================================================================
# CATEGORY B: HETERO-OS PAIR TOPOLOGIES (Cross-OS 2-Machine)
# =============================================================================

@test "Matrix Scenario 4: Linux <-> Windows (Divergent paths, mosy link, live cross-platform sync)" {
    # 1. Linux adds VS Code settings
    switch_node linux1
    mkdir -p "$HOME/.config/Code/User"
    echo '{"editor.fontSize": 14, "theme": "Monokai"}' > "$HOME/.config/Code/User/settings.json"

    run mosy add "$HOME/.config/Code/User/settings.json" -t linux -g editors
    assert_success

    # 2. Windows links to Linux settings via 'mosy link'
    switch_node win1
    run mosy link "$HOME/AppData/Roaming/Code/User/settings.json" ".config/Code/User/settings.json"
    assert_success

    [ -L "$HOME/AppData/Roaming/Code/User/settings.json" ]
    run grep 'Monokai' "$HOME/AppData/Roaming/Code/User/settings.json"
    assert_success

    # 3. Windows updates theme to "Catppuccin Frappe"
    cat <<'EOF' > "$HOME/AppData/Roaming/Code/User/settings.json"
{"editor.fontSize": 16, "theme": "Catppuccin Frappe"}
EOF

    # 4. Linux receives update live
    switch_node linux1
    run grep 'Catppuccin Frappe' "$HOME/.config/Code/User/settings.json"
    assert_success
    run grep '16' "$HOME/.config/Code/User/settings.json"
    assert_success
}

@test "Matrix Scenario 5: Linux <-> macOS (Divergent VS Code + Shared Unix CLI tools)" {
    # 1. Linux adds VS Code (~/.config) and Git/Starship
    switch_node linux1
    mkdir -p "$HOME/.config/Code/User"
    mkdir -p "$HOME/.config"
    echo '{"theme": "Solarized Dark"}' > "$HOME/.config/Code/User/settings.json"
    echo '[user] name = UnixDev' > "$HOME/.gitconfig"
    echo 'add_newline = false' > "$HOME/.config/starship.toml"

    run mosy add "$HOME/.config/Code/User/settings.json" -t linux -g editors
    assert_success
    run mosy add "$HOME/.gitconfig" -t all -g vcs
    assert_success
    run mosy add "$HOME/.config/starship.toml" -t unix -g shell
    assert_success

    # 2. macOS runs flagless init (links git and starship)
    switch_node mac1
    run mosy init
    assert_success

    [ -L "$HOME/.gitconfig" ]
    [ -L "$HOME/.config/starship.toml" ]
    [ ! -e "$HOME/.config/Code" ] # Linux VS Code path was NOT created on Mac

    # 3. macOS links its Library path to VS Code
    run mosy link "$HOME/Library/Application Support/Code/User/settings.json" ".config/Code/User/settings.json"
    assert_success

    [ -L "$HOME/Library/Application Support/Code/User/settings.json" ]
    run grep 'Solarized Dark' "$HOME/Library/Application Support/Code/User/settings.json"
    assert_success
}

@test "Matrix Scenario 6: macOS <-> Windows (Library <-> AppData cross-sync)" {
    # 1. macOS adds Library VS Code settings and Alacritty config
    switch_node mac1
    mkdir -p "$HOME/Library/Application Support/Code/User"
    mkdir -p "$HOME/.config/alacritty"
    echo '{"editor.fontFamily": "JetBrains Mono"}' > "$HOME/Library/Application Support/Code/User/settings.json"
    echo '[font] size = 12.0' > "$HOME/.config/alacritty/alacritty.toml"

    run mosy add "$HOME/Library/Application Support/Code/User/settings.json" -t macos -g editors
    assert_success
    run mosy add "$HOME/.config/alacritty/alacritty.toml" -t macos,unix -g terminal
    assert_success

    # 2. Windows links both items to its native locations via 'mosy link'
    switch_node win1
    run mosy link "$HOME/AppData/Roaming/Code/User/settings.json" "Library/Application Support/Code/User/settings.json"
    assert_success
    run mosy link "$HOME/AppData/Roaming/alacritty/alacritty.toml" ".config/alacritty/alacritty.toml"
    assert_success

    [ -L "$HOME/AppData/Roaming/Code/User/settings.json" ]
    [ -L "$HOME/AppData/Roaming/alacritty/alacritty.toml" ]
    run grep 'JetBrains Mono' "$HOME/AppData/Roaming/Code/User/settings.json"
    assert_success
    run grep 'size = 12.0' "$HOME/AppData/Roaming/alacritty/alacritty.toml"
    assert_success

    # 3. Windows modifies font size in Alacritty to 14.0
    echo '[font] size = 14.0' > "$HOME/AppData/Roaming/alacritty/alacritty.toml"

    # 4. macOS receives update live
    switch_node mac1
    run grep 'size = 14.0' "$HOME/.config/alacritty/alacritty.toml"
    assert_success
}

# =============================================================================
# CATEGORY C: MULTI-NODE TRI-OS MESH TOPOLOGIES (3+ Machines Concurrent)
# =============================================================================

@test "Matrix Scenario 7: Tri-OS Mesh (Linux + macOS + Windows live real-app synchronization)" {
    # 1. Linux1 sets up base suite: VS Code, Neovim, Git, Starship
    switch_node linux1
    mkdir -p "$HOME/.config/Code/User" "$HOME/.config/nvim" "$HOME/.config"
    echo '{"editor.fontSize": 14, "workbench.colorTheme": "Tokyo Night"}' > "$HOME/.config/Code/User/settings.json"
    echo 'vim.opt.relativenumber = true' > "$HOME/.config/nvim/init.lua"
    echo '[user] name = TriOSDev' > "$HOME/.gitconfig"
    echo 'add_newline = false' > "$HOME/.config/starship.toml"

    run mosy add "$HOME/.config/Code/User/settings.json" -t linux -g editors
    assert_success
    run mosy add "$HOME/.config/nvim/init.lua" -t linux,macos -g editors
    assert_success
    run mosy add "$HOME/.gitconfig" -t all -g vcs
    assert_success
    run mosy add "$HOME/.config/starship.toml" -t unix -g shell
    assert_success

    # 2. macOS1 joins: runs flagless init and links VS Code
    switch_node mac1
    run mosy init
    assert_success
    run mosy link "$HOME/Library/Application Support/Code/User/settings.json" ".config/Code/User/settings.json"
    assert_success

    [ -L "$HOME/Library/Application Support/Code/User/settings.json" ]
    [ -L "$HOME/.config/nvim/init.lua" ]
    [ -L "$HOME/.gitconfig" ]
    [ -L "$HOME/.config/starship.toml" ]

    # 3. Windows1 joins: runs flagless init and links VS Code + Neovim + Starship
    switch_node win1
    run mosy init
    assert_success
    run mosy link "$HOME/AppData/Roaming/Code/User/settings.json" ".config/Code/User/settings.json"
    assert_success
    run mosy link "$HOME/AppData/Local/nvim/init.lua" ".config/nvim/init.lua"
    assert_success
    run mosy link "$HOME/AppData/Local/starship.toml" ".config/starship.toml"
    assert_success

    [ -L "$HOME/AppData/Roaming/Code/User/settings.json" ]
    [ -L "$HOME/AppData/Local/nvim/init.lua" ]
    [ -L "$HOME/.gitconfig" ]
    [ -L "$HOME/AppData/Local/starship.toml" ]

    # 4. Multi-Node Concurrent Editing:
    # 4a. Windows modifies VS Code Theme to "Gruvbox Dark"
    echo '{"editor.fontSize": 16, "workbench.colorTheme": "Gruvbox Dark"}' > "$HOME/AppData/Roaming/Code/User/settings.json"

    # 4b. macOS modifies Neovim (adds leader key)
    switch_node mac1
    echo 'vim.g.mapleader = " "' >> "$HOME/.config/nvim/init.lua"

    # 4c. Linux modifies Git (adds pull rebase)
    switch_node linux1
    echo '[pull] rebase = true' >> "$HOME/.gitconfig"

    # 5. Verify all 3 nodes received every modification live
    # Linux verifies:
    run grep 'Gruvbox Dark' "$HOME/.config/Code/User/settings.json"
    assert_success
    run grep 'mapleader' "$HOME/.config/nvim/init.lua"
    assert_success

    # macOS verifies:
    switch_node mac1
    run grep 'Gruvbox Dark' "$HOME/Library/Application Support/Code/User/settings.json"
    assert_success
    run grep 'rebase = true' "$HOME/.gitconfig"
    assert_success

    # Windows verifies:
    switch_node win1
    run grep 'mapleader' "$HOME/AppData/Local/nvim/init.lua"
    assert_success
    run grep 'rebase = true' "$HOME/.gitconfig"
    assert_success
}

@test "Matrix Scenario 8: Selective Tag and Group Filtering across 3 Nodes" {
    # 1. Linux node adds items with various tags and groups
    switch_node linux1
    mkdir -p "$HOME/.config/Code/User" "$HOME/.config/nvim" "$HOME/.config/htop"
    echo '{"code": true}' > "$HOME/.config/Code/User/settings.json"
    echo 'vim.cmd("syntax on")' > "$HOME/.config/nvim/init.lua"
    echo 'htop_config = true' > "$HOME/.config/htop/htoprc"

    run mosy add "$HOME/.config/Code/User/settings.json" -t linux -g editors
    assert_success
    run mosy add "$HOME/.config/nvim/init.lua" -t all -g editors
    assert_success
    run mosy add "$HOME/.config/htop/htoprc" -t unix -g monitors
    assert_success

    # 2. macOS node inits ONLY group 'monitors'
    switch_node mac1
    run mosy init -g monitors
    assert_success

    [ -L "$HOME/.config/htop/htoprc" ]
    [ ! -e "$HOME/.config/nvim" ]

    # 3. Windows node inits ONLY group 'editors'
    switch_node win1
    run mosy init -g editors
    assert_success

    [ -L "$HOME/.config/nvim/init.lua" ]
    [ ! -e "$HOME/.config/htop" ]
}

@test "Matrix Scenario 9: Multi-Profile Isolation across 3 Nodes (-p work vs -p personal)" {
    # 1. Linux configures personal and work profiles
    switch_node linux1
    echo 'git.email = personal@example.com' > "$HOME/.gitconfig"
    run mosy -p personal add "$HOME/.gitconfig"
    assert_success

    echo 'git.email = work@enterprise.com' > "$HOME/.gitconfig_work"
    run mosy -p work add "$HOME/.gitconfig_work"
    assert_success

    # 2. Windows initializes ONLY the work profile
    switch_node win1
    run mosy -p work init
    assert_success

    [ -L "$HOME/.gitconfig_work" ]
    run grep 'work@enterprise.com' "$HOME/.gitconfig_work"
    assert_success
    [ ! -e "$HOME/.gitconfig" ]

    # 3. macOS initializes ONLY the personal profile
    switch_node mac1
    run mosy -p personal init
    assert_success

    [ -L "$HOME/.gitconfig" ]
    run grep 'personal@example.com' "$HOME/.gitconfig"
    assert_success
    [ ! -e "$HOME/.gitconfig_work" ]
}

@test "Matrix Scenario 10: Node Independence & Zero Data Loss on Unlink/Remove" {
    # 1. Linux node creates and syncs shared file
    switch_node linux1
    echo 'shared data 1.0' > "$HOME/.shared_tool.conf"
    run mosy add "$HOME/.shared_tool.conf" -t all
    assert_success

    # 2. macOS and Windows nodes link to the shared file
    switch_node mac1
    run mosy init
    assert_success
    [ -L "$HOME/.shared_tool.conf" ]

    switch_node win1
    run mosy init
    assert_success
    [ -L "$HOME/.shared_tool.conf" ]

    # 3. Linux removes the file from MountSync via 'mosy remove' (makes it local to Linux)
    switch_node linux1
    run mosy remove "$HOME/.shared_tool.conf"
    assert_success

    # Linux file is now a regular physical file, NOT a symlink
    [ ! -L "$HOME/.shared_tool.conf" ]
    [ -f "$HOME/.shared_tool.conf" ]
    run cat "$HOME/.shared_tool.conf"
    assert_output 'shared data 1.0'

    # 4. macOS and Windows nodes still maintain intact files with zero data loss
    switch_node mac1
    [ -e "$HOME/.shared_tool.conf" ]
    run cat "$HOME/.shared_tool.conf"
    assert_output 'shared data 1.0'

    switch_node win1
    [ -e "$HOME/.shared_tool.conf" ]
    run cat "$HOME/.shared_tool.conf"
    assert_output 'shared data 1.0'
}
