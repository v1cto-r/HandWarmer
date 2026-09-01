#!/usr/bin/env bash
# One-time setup for a fresh Amazon Linux 2023 EC2 host (tested on t4g.micro,
# ARM64). Idempotent — safe to re-run. Does NOT authenticate Tailscale or
# start any services — see the top-level README for what comes after this.
set -euo pipefail

items=(
  "System package update (dnf update -y)"
  "2GB swap file"
  "Docker"
  "Docker Compose plugin"
  "Tailscale"
)
# All start checked.
selected=(1 1 1 1 1)
cursor=0

draw_menu() {
  local i
  echo "hand_warmer host bootstrap — space to toggle, enter to confirm, q to abort"
  echo
  for i in "${!items[@]}"; do
    local box="[ ]"
    [ "${selected[$i]}" = "1" ] && box="[x]"
    if [ "$i" = "$cursor" ]; then
      printf " > %s %s\n" "$box" "${items[$i]}"
    else
      printf "   %s %s\n" "$box" "${items[$i]}"
    fi
  done
}

checkbox_menu() {
  local key
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' EXIT
  while true; do
    clear
    draw_menu
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.01 key || true
        case "$key" in
          '[A') cursor=$(( (cursor - 1 + ${#items[@]}) % ${#items[@]} )) ;;
          '[B') cursor=$(( (cursor + 1) % ${#items[@]} )) ;;
        esac
        ;;
      ' ')
        if [ "${selected[$cursor]}" = "1" ]; then selected[$cursor]=0; else selected[$cursor]=1; fi
        ;;
      q|Q)
        clear
        echo "Aborted, nothing installed."
        tput cnorm 2>/dev/null || true
        exit 0
        ;;
      '')
        break
        ;;
    esac
  done
  tput cnorm 2>/dev/null || true
  clear
}

if [ -t 0 ]; then
  checkbox_menu
else
  echo "Non-interactive shell — installing everything by default."
fi

want() {
  local label="$1" i
  for i in "${!items[@]}"; do
    if [ "${items[$i]}" = "$label" ]; then
      [ "${selected[$i]}" = "1" ]
      return
    fi
  done
  return 1
}

if want "System package update (dnf update -y)"; then
  echo "### Updating system packages ..."
  sudo dnf update -y
fi

if want "2GB swap file"; then
  echo "### Setting up swap (2GB) ..."
  if sudo swapon --show | grep -q '/swapfile'; then
    echo "Swap already active, skipping."
  elif [ -f /swapfile ]; then
    echo "/swapfile exists but isn't active — enabling it."
    sudo chmod 600 /swapfile
    sudo swapon /swapfile
  else
    sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
  fi
fi

if want "Docker"; then
  echo "### Installing Docker ..."
  if ! command -v docker &>/dev/null; then
    sudo dnf install -y docker
  fi
  sudo systemctl enable --now docker
  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    echo ">>> Added $USER to the docker group — log out/in (or run \`newgrp docker\`) before using docker without sudo."
  fi
fi

if want "Docker Compose plugin"; then
  echo "### Installing Docker Compose plugin ..."
  mkdir -p ~/.docker/cli-plugins
  if [ ! -x ~/.docker/cli-plugins/docker-compose ]; then
    ARCH="$(uname -m)"
    case "$ARCH" in
      aarch64) COMPOSE_ARCH="aarch64" ;;
      x86_64)  COMPOSE_ARCH="x86_64" ;;
      *) echo "Unrecognized arch $ARCH, install docker-compose manually." >&2; exit 1 ;;
    esac
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${COMPOSE_ARCH}" \
      -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
  fi
  docker compose version
fi

if want "Tailscale"; then
  echo "### Installing Tailscale ..."
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  echo ">>> Run 'sudo tailscale up' next, open the printed auth URL, and approve"
  echo ">>> the new device in your tailnet admin console."
fi

echo "### Done. Next: 'sudo tailscale up' (if Tailscale was installed), then follow the top-level README."
