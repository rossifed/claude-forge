# Claude Code development container with claude-forge support
# Based on Anthropic's official reference: https://code.claude.com/docs/en/devcontainer

FROM node:20

ARG TZ=UTC
ARG CLAUDE_CODE_VERSION=latest
ARG ZSH_IN_DOCKER_VERSION=1.2.0

ENV TZ=${TZ}

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    git \
    vim \
    nano \
    curl \
    wget \
    jq \
    iptables \
    ipset \
    dnsutils \
    net-tools \
    zsh \
    fzf \
    locales \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8

# ZSH setup with powerlevel10k
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -t https://github.com/romkatv/powerlevel10k \
    -p git \
    -p fzf

# Node user setup (non-root)
RUN mkdir -p /commandhistory /home/node/.claude /workspace \
    && chown -R node:node /commandhistory /home/node/.claude /workspace

# Command history persistence
RUN echo "export HISTFILE=/commandhistory/.bash_history" >> /home/node/.bashrc \
    && echo "export HISTFILE=/commandhistory/.zsh_history" >> /home/node/.zshrc \
    && echo "SAVEHIST=10000" >> /home/node/.zshrc \
    && echo "HISTSIZE=10000" >> /home/node/.zshrc \
    && echo "setopt SHARE_HISTORY" >> /home/node/.zshrc

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Default editor
ENV EDITOR=nano
ENV VISUAL=nano

# Firewall script
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh \
    && echo "node ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" >> /etc/sudoers.d/node-firewall

USER node
WORKDIR /workspace

SHELL ["/bin/zsh", "-c"]
