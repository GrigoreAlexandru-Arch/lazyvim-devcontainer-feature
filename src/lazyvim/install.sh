#!/usr/bin/env bash
set -e

# Fetch options from devcontainer-feature.json
NVIM_VERSION=${VERSION:-"stable"}
CONFIG_REPO=${CONFIGREPO:-"https://github.com/LazyVim/starter"}

echo "Activating feature 'LazyVim'"

# 1. Install System Dependencies
apt-get update
apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    build-essential \
    ripgrep \
    fd-find \
    xclip \
    jq

# 2. Determine Architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

if [ "$ARCH" = "x86_64" ]; then
    ASSET_PATTERN="nvim-linux-x86_64\.tar\.gz|nvim-linux64\.tar\.gz"
elif [ "$ARCH" = "aarch64" ]; then
    ASSET_PATTERN="nvim-linux-arm64\.tar\.gz"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 3. Determine the GitHub API Endpoint
if [ "${NVIM_VERSION}" = "stable" ]; then
    API_URL="https://api.github.com/repos/neovim/neovim/releases/latest"
elif [ "${NVIM_VERSION}" = "nightly" ]; then
    API_URL="https://api.github.com/repos/neovim/neovim/releases/tags/nightly"
else
    API_URL="https://api.github.com/repos/neovim/neovim/releases/tags/${NVIM_VERSION}"
fi

# 4. Fetch and install Neovim
echo "Querying GitHub API for Neovim release: ${NVIM_VERSION}..."
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r '.assets[].browser_download_url' | grep -E "$ASSET_PATTERN" | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find a valid Neovim asset for architecture $ARCH in release ${NVIM_VERSION}."
    exit 1
fi

echo "Downloading Neovim from: $DOWNLOAD_URL"
curl -LO -f "$DOWNLOAD_URL"
FILENAME=$(basename "$DOWNLOAD_URL")

tar -C /opt -xzf "$FILENAME"
rm "$FILENAME"

EXTRACTED_DIR=$(find /opt -maxdepth 1 -name "nvim-linux*" -type d | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Failed to find extracted Neovim directory in /opt."
    exit 1
fi

ln -s "${EXTRACTED_DIR}/bin/nvim" /usr/local/bin/nvim

# 5. Generate the Post-Create Bootstrap Script
# This script will run as the remote user with full access to forwarded SSH keys/credentials
BOOTSTRAP_SCRIPT="/usr/local/share/lazyvim-bootstrap.sh"

cat <<'EOF' >${BOOTSTRAP_SCRIPT}
#!/usr/bin/env bash
set -e

# Use the remote user's home directory
USER_HOME=$HOME
CONFIG_DIR="${USER_HOME}/.config/nvim"

if [ -d "$CONFIG_DIR" ]; then
    echo "Neovim configuration already exists at $CONFIG_DIR. Skipping clone."
    exit 0
fi

echo "Cloning LazyVim configuration..."
mkdir -p "${USER_HOME}/.config"

mkdir -p "${USER_HOME}/.ssh"
chmod 700 "${USER_HOME}/.ssh"
ssh-keyscan github.com >> "${USER_HOME}/.ssh/known_hosts" 2>/dev/null
# -----------------------------------------------------------------------

# We inject the CONFIG_REPO from the build step into this script
git clone "__CONFIG_REPO__" "$CONFIG_DIR"

# Clean up .git history so the user can optionally track their own
rm -rf "${CONFIG_DIR}/.git"

echo "Bootstrapping LazyVim plugins headlessly..."
nvim --headless '+Lazy! sync' +qa

echo "LazyVim installation complete!"
EOF

# Inject the chosen repo URL into the script
sed -i "s|__CONFIG_REPO__|${CONFIG_REPO}|g" ${BOOTSTRAP_SCRIPT}

# Ensure the script is executable
chmod +x ${BOOTSTRAP_SCRIPT}

echo "Feature build step complete! Configuration will be cloned during postCreateCommand."
