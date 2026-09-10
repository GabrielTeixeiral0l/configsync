#!/bin/bash

# MountSync - install.sh
# Installation script for MountSync

set -e # Exit on error

IS_UPDATE=false
if [[ "$1" == "--update" ]]; then
    IS_UPDATE=true
fi

# Auto-download if piped from curl
if [ ! -f "mosy" ] || [ ! -d "src" ]; then
    echo "--- Downloading MountSync ---"
    REPO_DIR="$HOME/.mountsync"
    if [ -d "$REPO_DIR" ]; then
        echo "Updating existing repository at $REPO_DIR..."
        cd "$REPO_DIR"
        git pull origin main
    else
        echo "Cloning repository to $REPO_DIR..."
        git clone https://github.com/GabrielTeixeiral0l/MountSync.git "$REPO_DIR"
        cd "$REPO_DIR"
    fi
    
    if (exec </dev/tty) 2>/dev/null; then
        exec bash install.sh < /dev/tty
    else
        exec bash install.sh
    fi
fi

# Default values
DEFAULT_REMOTE="GoogleDrive"
DEFAULT_MOUNT="${HOME}/GoogleDrive"

if [ "$IS_UPDATE" = true ]; then
    CONFIG_FILE="${HOME}/.config/mosy/config"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        DEFAULT_REMOTE="${MOSY_REMOTE_NAME:-$DEFAULT_REMOTE}"
        DEFAULT_MOUNT="${MOSY_MOUNT_POINT:-$DEFAULT_MOUNT}"
    fi
fi

# Load platform helpers if available
if [ -f "src/platform/init.sh" ]; then
    . "src/platform/init.sh"
fi

# 1. Dependency Check: rclone
if ! command -v rclone &> /dev/null; then
    if [ "$IS_UPDATE" = true ]; then
        echo "Error: rclone not found. Cannot update without rclone."
        exit 1
    fi
    echo "rclone not found."
    read -p "Install rclone now? (y/n): " install_rclone
    if [[ $install_rclone =~ ^[Yy]$ ]]; then
        echo "Installing rclone..."
        if [[ "${MOSY_OS:-linux}" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
            brew install rclone
        elif [[ "${MOSY_OS:-linux}" == "windows" ]]; then
            if command -v winget >/dev/null 2>&1; then
                winget install Rclone.Rclone
            elif command -v scoop >/dev/null 2>&1; then
                scoop install rclone
            else
                echo "Please install rclone using winget, scoop, or from https://rclone.org/downloads/"
                exit 1
            fi
        else
            sudo -v
            curl https://rclone.org/install.sh | sudo bash
        fi
    else
        echo "Error: rclone is required for MountSync."
        exit 1
    fi
fi

# 1.5. Remote Configuration Check
if ! rclone listremotes | grep -q .; then
    if [ "$IS_UPDATE" = true ]; then
        echo "Warning: No cloud remotes detected in rclone. Update might fail."
    else
        echo "--- rclone Configuration ---"
        echo "No cloud remotes detected in rclone."
        read -p "Would you like to configure one now? (y/n): " run_config
        if [[ $run_config =~ ^[Yy]$ ]]; then
            rclone config
        else
            echo "Warning: You need at least one configured rclone remote for MountSync to work."
        fi
    fi
fi

# 2. Configuration Wizard
echo "--- MountSync Setup ---"

if [ "$IS_UPDATE" = true ]; then
    REMOTE_NAME="$DEFAULT_REMOTE"
    MOUNT_POINT="$DEFAULT_MOUNT"
    MOUNT_POINT="${MOUNT_POINT/#\~/$HOME}"
    echo "Using remote: $REMOTE_NAME"
    echo "Using mount point: $MOUNT_POINT"
else
    REMOTES=($(rclone listremotes 2>/dev/null | sed 's/://'))
    DEFAULT_REMOTE="GoogleDrive"
    if [ ${#REMOTES[@]} -gt 0 ]; then
        DEFAULT_REMOTE="${REMOTES[0]}"
        echo "Detected rclone remotes:"
        for i in "${!REMOTES[@]}"; do
            echo "  $((i+1))) ${REMOTES[$i]}"
        done
    fi

    VALID_REMOTE=false
    while [ "$VALID_REMOTE" = false ]; do
        read -p "Enter your rclone remote name or number [$DEFAULT_REMOTE]: " REMOTE_INPUT
        if [[ "$REMOTE_INPUT" =~ ^[0-9]+$ ]] && [ "$REMOTE_INPUT" -le "${#REMOTES[@]}" ] && [ "$REMOTE_INPUT" -gt 0 ]; then
            REMOTE_NAME="${REMOTES[$((REMOTE_INPUT-1))]}"
        else
            REMOTE_NAME="${REMOTE_INPUT:-$DEFAULT_REMOTE}"
        fi
        
        # Validation check
        FOUND=false
        for r in "${REMOTES[@]}"; do
            if [ "$r" == "$REMOTE_NAME" ]; then FOUND=true; break; fi
        done
        
        if [ "$FOUND" = true ] || [ ${#REMOTES[@]} -eq 0 ]; then
            VALID_REMOTE=true
        else
            echo "Warning: Remote '$REMOTE_NAME' not found in rclone configuration."
            read -p "Do you want to proceed anyway? (y/N): " PROCEED
            if [[ $PROCEED =~ ^[Yy]$ ]]; then
                VALID_REMOTE=true
            fi
        fi
    done

    VALID_PATH=false
    while [ "$VALID_PATH" = false ]; do
        read -p "Enter your cloud mount point [$DEFAULT_MOUNT]: " MOUNT_INPUT
        MOUNT_POINT="${MOUNT_INPUT:-$DEFAULT_MOUNT}"
        MOUNT_POINT="${MOUNT_POINT/#\~/$HOME}"
        
        if [ -d "$MOUNT_POINT" ]; then
            VALID_PATH=true
        else
            read -p "Directory '$MOUNT_POINT' does not exist. Create it now? (Y/n): " CREATE_DIR
            if [[ ! $CREATE_DIR =~ ^[Nn]$ ]]; then
                if mkdir -p "$MOUNT_POINT" 2>/dev/null; then
                    VALID_PATH=true
                else
                    echo "Error: Could not create directory $MOUNT_POINT. Please check permissions."
                fi
            fi
        fi
    done
fi

# 2.5. Mount Awareness Check
SHOULD_SETUP_SERVICE=true
is_already_mounted=false
if declare -F platform_is_mounted >/dev/null 2>&1; then
    platform_is_mounted "$MOUNT_POINT" && is_already_mounted=true
elif mountpoint -q "$MOUNT_POINT" 2>/dev/null || mount | grep -qE "[[:space:]]on[[:space:]]${MOUNT_POINT%/}/?[[:space:]]"; then
    is_already_mounted=true
fi

if [ "$is_already_mounted" = true ]; then
    echo "Notice: $MOUNT_POINT is already a mountpoint."
    if [ "$IS_UPDATE" = true ]; then
        SHOULD_SETUP_SERVICE=false
        echo "Skipping Systemd service setup (Update Mode)."
    else
        read -p "Do you still want to install the MountSync auto-mount service? (y/N): " setup_service
        if [[ ! $setup_service =~ ^[Yy]$ ]]; then
            SHOULD_SETUP_SERVICE=false
            echo "Skipping Systemd service setup. MountSync will use your existing mount."
        fi
    fi
fi

# 3. Generation of Configuration
CONFIG_DIR="${HOME}/.config/mosy"
mkdir -p "$CONFIG_DIR" || { echo "Error: Could not create config directory $CONFIG_DIR"; exit 1; }
CONFIG_FILE="$CONFIG_DIR/config"

cat <<EOF > "$CONFIG_FILE" || { echo "Error: Could not write to $CONFIG_FILE"; exit 1; }
MOSY_REMOTE_NAME="$REMOTE_NAME"
MOSY_MOUNT_POINT="$MOUNT_POINT"
MOSY_CLOUD_DIR="$MOUNT_POINT/mosy_vault"
EOF

# 4. Persistence with Service Manager
if [ "$SHOULD_SETUP_SERVICE" = true ]; then
    if declare -F platform_create_service >/dev/null 2>&1; then
        echo "Setting up background mount service (${MOSY_OS_NAME:-Linux})..."
        platform_create_service "$REMOTE_NAME" "$MOUNT_POINT"
        platform_service_enable || echo "Warning: Could not enable mount service."
        platform_service_start || echo "Warning: Could not start mount service. You may need to start it manually."
    else
        SERVICE_DIR="${HOME}/.config/systemd/user"
        mkdir -p "$SERVICE_DIR" || { echo "Error: Could not create systemd directory $SERVICE_DIR"; exit 1; }
        SERVICE_FILE="$SERVICE_DIR/mosy-mount.service"
        RCLONE_PATH=$(command -v rclone)

        cat <<EOF > "$SERVICE_FILE" || { echo "Error: Could not write to $SERVICE_FILE"; exit 1; }
[Unit]
Description=Rclone Mount for MountSync
After=network-online.target

[Service]
Type=simple
ExecStart=$RCLONE_PATH mount ${REMOTE_NAME}: ${MOUNT_POINT} --vfs-cache-mode writes
ExecStop=/bin/fusermount -u ${MOUNT_POINT}
Restart=on-failure

[Install]
WantedBy=default.target
EOF

        echo "Setting up Systemd service..."
        systemctl --user daemon-reload || true
        systemctl --user enable mosy-mount.service || echo "Warning: Could not enable systemd service (might be in a container/non-systemd system)."
        systemctl --user start mosy-mount.service || echo "Warning: Could not start systemd service. You may need to start it manually."
    fi
fi

# 5. Integration in PATH & CLI Shims
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR" || { echo "Error: Could not create $BIN_DIR"; exit 1; }
ln -sf "$(pwd)/mosy" "$BIN_DIR/mosy"

if declare -F platform_create_shims >/dev/null 2>&1; then
    platform_create_shims "$BIN_DIR" "$(pwd)/mosy"
fi

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Warning: $BIN_DIR is not in your PATH."
    echo "Add the following line to your ~/.bashrc (or ~/.zshrc):"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# 6. Shell Autocomplete Completions
echo "Installing shell completions..."
COMPLETIONS_DIR="${HOME}/.config/mosy/completions"
mkdir -p "$COMPLETIONS_DIR"
cp completions/mosy.bash "$COMPLETIONS_DIR/mosy.bash"
cp completions/_mosy "$COMPLETIONS_DIR/_mosy"

# Register in ~/.bashrc
BASHRC="${HOME}/.bashrc"
if [ -f "$BASHRC" ]; then
    if ! grep -q "mosy.bash" "$BASHRC"; then
        echo -e "\n# MountSync Bash Completion\nif [ -f \"$COMPLETIONS_DIR/mosy.bash\" ]; then\n    source \"$COMPLETIONS_DIR/mosy.bash\"\nfi" >> "$BASHRC"
    fi
fi

# Register in ~/.zshrc
ZSHRC="${HOME}/.zshrc"
if [ -f "$ZSHRC" ]; then
    if ! grep -q "completions/_mosy" "$ZSHRC"; then
        echo -e "\n# MountSync Zsh Completion\nif [ -d \"$COMPLETIONS_DIR\" ]; then\n    fpath=(\"$COMPLETIONS_DIR\" \$fpath)\n    autoload -Uz compinit && compinit\nfi" >> "$ZSHRC"
    fi
fi

echo "Installation complete! 'mosy' is now linked to $BIN_DIR/mosy"
