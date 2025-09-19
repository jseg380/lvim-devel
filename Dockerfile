FROM ubuntu:22.04
ARG NVIM_VERSION="stable"
ENV DEBIAN_FRONTEND=noninteractive

#==============================================================================
# STAGE 1: Install System & Build Dependencies
#==============================================================================
RUN apt-get update && \
    # We need software-properties-common to manage repositories like PPAs
    apt-get install -y software-properties-common && \
    # Add the official PPA for Alacritty
    add-apt-repository ppa:aslatter/ppa -y && \
    # Now we can update apt again to fetch the package list from the new PPA
    apt-get update && \
    # Now the main install command can find 'alacritty'
    apt-get install -y \
    # Build tools for Neovim
    git cmake ninja-build gettext libtool libtool-bin autoconf automake pkg-config \
    unzip doxygen build-essential \
    # Utilities & GUI libs
    curl fontconfig libegl1 libgbm1 ripgrep fd-find \
    # Terminal Emulators
    alacritty \
    kitty \
    konsole \
    gnome-terminal

#==============================================================================
# STAGE 2: Install Distro Runtime Dependencies (Node, Python, etc.)
# These are common for LSP servers and plugins.
#==============================================================================
RUN apt-get install -y npm python3-pip && \
    # We might need this for some tools
    ln -s /usr/bin/fdfind /usr/bin/fd && \
    rm -rf /var/lib/apt/lists/*

#==============================================================================
# STAGE 3: Build and Install Neovim from Source
#==============================================================================
RUN echo "Building Neovim version: ${NVIM_VERSION}" && \
    cd /tmp && git clone https://github.com/neovim/neovim.git && cd neovim && \
    git checkout "${NVIM_VERSION}" && make CMAKE_BUILD_TYPE=Release && make install && \
    cd /tmp && rm -rf neovim

#==============================================================================
# STAGE 4: Install Nerd Fonts
#==============================================================================
RUN mkdir -p /usr/local/share/fonts/truetype/nerd-fonts && \
    cd /usr/local/share/fonts/truetype/nerd-fonts && \
    curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip && \
    unzip JetBrainsMono.zip && rm JetBrainsMono.zip && fc-cache -fv

#==============================================================================
# STAGE 5: Create User and Distro Environment
# This is the key new stage.
#==============================================================================
RUN useradd -m -s /bin/bash developer
USER developer
WORKDIR /home/developer

# 1. Create the entire directory structure the distro expects.
# These will serve as mount points for our live development.
RUN mkdir -p /home/developer/.local/bin
RUN mkdir -p /home/developer/.local/share/lunarvim/lvim
RUN mkdir -p /home/developer/.config/lvim
RUN mkdir -p /home/developer/examples

# 2. Copy the launcher script into the container and make it executable.
COPY --chown=developer:developer ./assets/lvim-launcher.sh /home/developer/.local/bin/lvim

# 3. Add the local bin directory to the user's PATH.
ENV PATH="/home/developer/.local/bin:${PATH}"

CMD ["/bin/bash"]
