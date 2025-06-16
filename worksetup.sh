#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

LOG_FILE="worksetup_log.md"
DOTFILES_REPO="https://github.com/rmadhira/dotFiles.git"
VIM_COLOR_REPO="https://github.com/gosukiwi/vim-atom-dark.git"
COLOR_FILE="atom-dark-256.vim"

log()    { echo "- $1" | tee -a "$LOG_FILE"; }
error()  { echo "❌ $1" | tee -a "$LOG_FILE"; exit 1; }
header() { echo -e "\n## $1" | tee -a "$LOG_FILE"; }

backup() {
    [[ -e ~/$1 ]] && {
        cp -a ~/$1 ~/${1}.bak || error "Failed to backup ~$1"
        log "Backed up ~$1 to ~/${1}.bak"
    }
}

detect_os() {
}

install_pkgs() {
}

# Start log
echo "# Worksetup Log - $(date)" > "$LOG_FILE"

header "🔧 System Update and Essential Tools"
echo "📦 Updating package list and installing git, vim, tmux..." | tee -a "$LOG_FILE"
sudo apt update || error_exit "Failed to update package list"
sudo apt install -y git vim tmux curl wget || error_exit "Failed to install base packages"
log "Installed: git, vim, tmux, curl, wget"

header "📘 Installing Glow Markdown Viewer"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install glow
log "Glow installed"

header "🎨 Vim Setup with Vundle and Plugins"
if [[ ! -d ~/.vim/bundle/Vundle.vim ]]; then
      git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim \
              || error_exit "Failed to clone Vundle"
        log "Vundle installed"
    else
          log "Vundle already installed"
fi

mkdir -p ~/.vim/colors
cd ~/.vim

if [[ ! -d vim-atom-dark ]]; then
      git clone "$VIM_COLOR_REPO" || error_exit "Failed to clone vim color scheme"
        log "Cloned vim-atom-dark"
fi

cp -u vim-atom-dark/colors/$COLOR_FILE ~/.vim/colors/ || error_exit "Failed to copy Vim color scheme"
log "Color scheme $COLOR_FILE copied"

if [[ ! -d dotFiles ]]; then
      git clone "$DOTFILES_REPO" || error_exit "Failed to clone dotFiles"
        log "Cloned dotFiles"
fi

cp -u dotFiles/.vimrc ~ || error_exit "Failed to copy .vimrc"
log ".vimrc copied"

log "Installing Vim plugins..."
vim +PluginInstall +qall || error_exit "Vim plugin installation failed"
log "Vim plugins installed"
cd ~

header "🖥️ Tmux Setup with Plugins"

if [[ ! -d ~/.tmux/plugins/tpm ]]; then
      git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm \
              || error_exit "Failed to install TPM"
        log "TPM (Tmux Plugin Manager) installed"
    else
          log "TPM already exists"
fi

cd ~/.vim
cp -u dotFiles/.tmux.conf ~ || error_exit "Failed to copy .tmux.conf"
log ".tmux.conf copied"
cd ~

header "✅ Final Instructions"

log "**Start tmux and press**: Ctrl + b, then Shift + I to install tmux plugins"
log "**Use**: glow README.md or any markdown file to preview"

echo -e "\n✅ Setup complete! See $LOG_FILE for a step-by-step log."
