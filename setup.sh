#!/usr/bin/env bash
# Template from https://betterdev.blog/minimal-safe-bash-script-template/
set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

function usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -p param_value arg1 [arg2...]

Script description here.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
EOF
  exit
}

function cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

function setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    # shellcheck disable=SC2034
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

function msg() {
  echo >&2 -e "${1-}"
}

function info() {
  msg "${GREEN}${1-}${NOFORMAT}"
}

function warning() {
  msg "${YELLOW}${1-}${NOFORMAT}"
}

function die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "${RED}${msg}${NOFORMAT}"
  exit "$code"
}

function parse_params() {
  # default values of variables set from params
  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  return 0
}

parse_params "$@"
setup_colors

# The script will need sudo, get authorization now.
sudo -k
if ! sudo -v; then
  die "sudo authentication required." 1
fi

# Keep the sudo timestamp fresh until this script exits.
# shellcheck disable=SC2064
trap 'kill "${SUDO_KEEPALIVE_PID:-}" 2>/dev/null || true; sudo -k || true' EXIT
( while true; do sudo -n true; sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!

function needroot() { sudo -n "$@"; }

# script logic here

function install_dotfiles {
  local repo="$1"
  local dotfiles_dir="$2"
  local dotfiles
  dotfiles=$(cat ./dotfiles)

  if [ -d "${dotfiles}" ]; then
    warning "${dotfiles} already installed"
    return
  fi

  info "Installing ${repo} to ${dotfiles_dir}"
  git clone "${repo}" "${dotfiles_dir}"
  pushd "${dotfiles_dir}"
  for dotfile in ${dotfiles}; do
    rcup -v "${dotfile}"
  done
  popd

  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/zsh-syntax-highlighting
  git clone https://github.com/zsh-users/zsh-completions.git ~/.zsh/zsh-completions
}

function install_deb {
  local url="$1"
  local name
  name=$(basename "${url}")

  info "Installing ${name} from ${url}"
  curl --silent --show-error --location --remote-name "${url}"
  needroot dpkg --install "${name}"
  rm "${name}"
}

function install_tar {
  local executable="$1"
  local url="$2"
  local tarfile
  tarfile=$(basename "${url}")

  info "Installing ${executable} from ${url}"
  curl --silent --show-error --location --remote-name "${url}"
  tar -xf "${tarfile}" "${executable}"
  mv "${executable}" ~/.local/bin
  rm "${tarfile}"
}

function install_yazi {
  local url="$1"
  local zipfile
  local zipdir
  zipfile=$(basename "${url}")
  zipdir=${zipfile%.*}

  info "Installing yazi from ${url}"
  curl --silent --show-error --location --remote-name "${url}"
  unzip -qq "${zipfile}"
  mv "${zipdir}"/ya{,zi} ~/.local/bin/
  mv "${zipdir}"/completions/{_ya,_yazi} ~/.zsh/
  rm -rf "${zipdir}" "${zipfile}"
}

function install_nf_symbols {
  local url=https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.zip
  local zipfile
  local fontdir=/usr/local/share/fonts/symbol-nf
  zipfile=$(basename "${url}")

  info "Installing Symbols Nerd Fonts"

  curl --silent --show-error --location --remote-name "${url}"
  unzip "${zipfile}" SymbolsNerdFontMono-Regular.ttf SymbolsNerdFont-Regular.ttf
  needroot mkdir -p "${fontdir}"
  needroot mv SymbolsNerdFontMono-Regular.ttf SymbolsNerdFont-Regular.ttf "${fontdir}"
  needroot fc-cache
  rm "${zipfile}"
}

function install_kitty {
  info "Installing kitty"
  curl -LO https://sw.kovidgoyal.net/kitty/installer.sh
  sh ./installer.sh launch=n

  mkdir -p ~/.local/share/applications
  ln -sf ~/.local/kitty.app/bin/kitty ~/.local/kitty.app/bin/kitten ~/.local/bin/
  cp ~/.local/kitty.app/share/applications/kitty.desktop ~/.local/share/applications/
  cp ~/.local/kitty.app/share/applications/kitty-open.desktop ~/.local/share/applications/
  sed -i "s|Icon=kitty|Icon=$(readlink -f ~)/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" ~/.local/share/applications/kitty*.desktop
  sed -i "s|Exec=kitty|Exec=$(readlink -f ~)/.local/kitty.app/bin/kitty|g" ~/.local/share/applications/kitty*.desktop
  echo 'kitty.desktop' > ~/.config/xdg-terminals.list

  mkdir -p ~/.terminfo/x
  cp ~/.local/kitty.app/share/terminfo/x/xterm-kitty ~/.terminfo/x/
  install_nf_symbols
}

function install_atuin {
  info "Installing atuin"
  bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
}

function install_mise {
  local mise="${HOME}/.local/bin/mise"
  local core_plugins="erlang elixir node rust"
  local runtimes
  runtimes=$(cat ./runtimes)

  info "${GREEN}Installing mise${NOFORMAT}"

  curl https://mise.run | sh
  # shellcheck source=/dev/null
  source <(${mise} activate)

  for runtime in ${runtimes}; do
    plugin=${runtime//@[0-9\.]*/}
    # shellcheck disable=SC2076
    if [[ ! " ${core_plugins} " =~ " ${plugin} " ]]; then
      ${mise} plugin install "${plugin}"
    fi
    ${mise} use --global "${runtime}"
  done
}

function install_gzip {
  local executable="$1"
  local url="$2"
  local gzipfile
  local unzipped_file

  echo "${GREEN}Installing ${executable} from ${url}${NOFORMAT}"
  curl --silent --show-error --location --remote-name "${url}"
  gzipfile=$(basename "${url}")
  unzipped_file="${gzipfile%.*}"
  gunzip -q "${gzipfile}"
  if [[ "${unzipped_file}" != "${executable}" ]]; then
    mv "${unzipped_file}" "${executable}"
  fi
  chmod +x "${executable}"
  mv "${executable}" "${HOME}/.local/bin"
}

function install_lsps {
  local lsp
  local type

  while read -r line; do
    read -r -a fields <<< "$line"
    lsp="${fields[0]}"
    type="${fields[1]}"
    # shellcheck disable=SC2076
    if [[ ! " tar gzip " =~ " ${type} " ]]; then
      info "Installing ${lsp} from ${type}"
    fi
    case "${type}" in
      tar)
        install_tar "${lsp}" "${fields[2]}"
        ;;
      npm)
        npm install --global "${lsp}"
        ;;
      apt)
        needroot apt install --yes "${lsp}"
        ;;
      cargo)
        cargo install "${lsp}"
        ;;
      mise)
        mise use --global "${lsp}@latest'"
        ;;
      binary)
        curl --silent --show-error --location --remote-name "${fields[2]}"
        if [[ "${lsp}" != "${fields[3]}" ]]; then
          mv "${fields[3]}" "${lsp}"
        fi
        chmod +x "${lsp}"
        mv "${lsp}" "${HOME}/.local/bin"
        ;;
      pip)
        pip3 install --user "${lsp}"
        ;;
      raco)
        raco pkg install "${lsp}"
        ;;
      gzip)
        install_gzip "${lsp}" "${fields[2]}"
        ;;
      *)
        warning "Unknown type ${type}, not installing ${lsp}"
        ;;
    esac
  done < language-servers
}

function install_packages {
  msg "${GREEN}Installing Ubuntu packages${NOFORMAT}"

  needroot DEBIAN_FRONTEND=noninteractive apt update
  needroot DEBIAN_FRONTEND=noninteractive apt upgrade
  needroot debconf-set-selections <<< "wireshark-common wireshark-common/install-setuid boolean true"
  needroot DEBIAN_FRONTEND=noninteractive xargs apt install --yes < ./packages

  # Docker
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    needroot apt remove $pkg
  done

  needroot install -m 0755 -d /etc/apt/keyrings
  needroot curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  needroot chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    needroot tee /etc/apt/sources.list.d/docker.list > /dev/null
  needroot apt-get update

  needroot apt install --yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Kicad
  needroot add-apt-repository --yes ppa:kicad/kicad-9.0-releases
  needroot apt update
  # needroot apt install --yes kicad
}

function configure_user {
  local user="$1"

  msg "${GREEN}Configuring user ${user}${NOFORMAT}"
  needroot usermod --append --groups kvm,tcpdump,wireshark,libvirt,docker "${user}"
  chsh -s /usr/bin/zsh "${user}"
}

# Main entry point
install_packages

mkdir "${HOME}/.local/bin"

install_dotfiles git@github.com:jbromley/dotfiles.git ~/.dotfiles
install_deb https://github.com/sharkdp/bat/releases/download/v0.25.0/bat_0.25.0_amd64.deb
bat cache --build
install_deb https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.8/zoxide_0.9.8-1_amd64.deb
install_deb https://github.com/helix-editor/helix/releases/download/25.07.1/helix_25.7.1-1_amd64.deb
install_tar starship https://github.com/starship/starship/releases/download/v1.23.0/starship-x86_64-unknown-linux-gnu.tar.gz
install_tar lazygit https://github.com/jesseduffield/lazygit/releases/download/v0.54.2/lazygit_0.54.2_linux_x86_64.tar.gz
install_tar fzf https://github.com/junegunn/fzf/releases/download/v0.65.1/fzf-0.65.1-linux_amd64.tar.gz
install_yazi https://github.com/sxyazi/yazi/releases/download/v25.5.31/yazi-x86_64-unknown-linux-gnu.zip
install_kitty
install_atuin
install_mise
install_lsps
configure_user jay
