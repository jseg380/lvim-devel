#!/bin/bash
set -e

# --- Configuration ---
# The URL of the distro's git repository. Change this to your fork if needed.
DISTRO_REPO_URL="https://github.com/jseg380/LunarVim.git"

# Docker-related names
IMAGE_NAME="distro-dev-env"
CONTAINER_NAME="distro-dev-container"

# Neovim version can be passed as the first argument (e.g., ./run.sh v0.9.5)
NVIM_VERSION=${1:-stable}
TAGGED_IMAGE_NAME="${IMAGE_NAME}:${NVIM_VERSION}"

#==============================================================================
# SECTION: Manage Distro Source Code
#==============================================================================
echo "--- Syncing distro source code ---"

# Check if the distro-source directory exists and is a git repo
if [ ! -d "distro-source/.git" ]; then
    echo "'distro-source' is not a git repository or does not exist."
    echo "Cloning a fresh copy from ${DISTRO_REPO_URL}..."
    # Remove any existing non-git directory to ensure a clean start
    rm -rf distro-source
    # Clone the repo directly into the 'distro-source' directory
    git clone "$DISTRO_REPO_URL" distro-source
else
    echo "Found existing 'distro-source' repository. Checking for updates..."
    # Temporarily change into the directory to run git commands
    cd distro-source

    # SAFETY CHECK: Exit if there are uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo
        echo "ERROR: Uncommitted changes detected in 'distro-source'."
        echo "Please commit, stash, or discard your changes before running the script again."
        echo
        # Go back to the original directory before exiting
        cd ..
        exit 1
    fi

    echo "No local changes detected. Pulling the latest updates..."
    # Attempt to pull. If it fails (e.g., merge conflict), the script will exit.
    if ! git pull; then
        echo
        echo "ERROR: 'git pull' failed. This could be due to a merge conflict."
        echo "Please resolve the conflicts manually inside the 'distro-source' directory."
        echo
        cd ..
        exit 1
    fi

    # Return to the original directory
    cd ..
fi
echo "--- Source code is up to date ---"
echo

#==============================================================================
# SECTION: Build Docker Image
#==============================================================================
# --- Build the image if it doesn't exist for the specified version ---
if [[ "$(docker images -q $TAGGED_IMAGE_NAME 2> /dev/null)" == "" ]]; then
  echo "Docker image for Neovim '${NVIM_VERSION}' not found. Building..."
  docker build --build-arg NVIM_VERSION=${NVIM_VERSION} -t ${TAGGED_IMAGE_NAME} .
  echo "Build complete."
fi

#==============================================================================
# SECTION: Configure and Run Docker Container
#==============================================================================
# --- Prepare arguments for the 'docker run' command ---
DOCKER_ARGS=()
DOCKER_ARGS+=(-it --rm --name "$CONTAINER_NAME" --hostname "$CONTAINER_NAME")

# Mount the core distro source code to its "installed" location.
# IMPORTANT: The path inside the container must match LUNARVIM_RUNTIME_DIR from the launcher
DOCKER_ARGS+=(-v "$(pwd)/distro-source:/home/developer/.local/share/lunarvim/lvim")

# Mount the user's test configuration
DOCKER_ARGS+=(-v "$(pwd)/user-config:/home/developer/.config/lvim")

# Mount example files for testing LSP capabilities
DOCKER_ARGS+=(-v "$(pwd)/examples:/home/developer/examples")

# --- Display Server Detection and Configuration ---
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    echo "Wayland session detected. Configuring for Wayland."
    DOCKER_ARGS+=(-v "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/tmp/$WAYLAND_DISPLAY")
    DOCKER_ARGS+=(-e WAYLAND_DISPLAY)
    DOCKER_ARGS+=(-e XDG_RUNTIME_DIR=/tmp)
    DOCKER_ARGS+=(-e GDK_BACKEND=wayland)

elif [ "$XDG_SESSION_TYPE" = "x11" ]; then
    echo "X11 session detected. Configuring with secure .Xauthority method."
    XAUTH_FILE=$(mktemp /tmp/.docker.xauth.XXXXXX)
    trap 'rm -f "$XAUTH_FILE"' EXIT
    xauth extract - "$DISPLAY" | xauth -f "$XAUTH_FILE" merge -
    DOCKER_ARGS+=(-v /tmp/.X11-unix:/tmp/.X11-unix)
    DOCKER_ARGS+=(-v "$XAUTH_FILE:/tmp/.Xauthority")
    DOCKER_ARGS+=(-e DISPLAY)
    DOCKER_ARGS+=(-e XAUTHORITY=/tmp/.Xauthority)
else
    echo "Error: Could not determine display server type via \$XDG_SESSION_TYPE."
    exit 1
fi

echo "---"
echo "Starting container."
echo "Type 'lvim' to launch the Neovim distro or use any of the installed terminal emulators."
echo "---"

# --- Run the Container ---
docker run "${DOCKER_ARGS[@]}" "${TAGGED_IMAGE_NAME}"
