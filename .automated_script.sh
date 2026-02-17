#!/usr/bin/env bash
set -euo pipefail

use_omarchy_helpers() {
  export OMARCHY_PATH="/root/omarchy"
  export OMARCHY_INSTALL="/root/omarchy/install"
  export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
  source /root/omarchy/install/helpers/all.sh
}

run_configurator() {
  set_tokyo_night_colors
  ./configurator
  export OMARCHY_USER="$(jq -r '.users[0].username' user_credentials.json)"
}

install_arch() {
  clear_logo
  gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Installing..."
  echo

  touch /var/log/omarchy-install.log

  start_log_output

  # Set CURRENT_SCRIPT for the trap to display better when nothing is returned for some reason
  CURRENT_SCRIPT="install_base_system"
  install_base_system > >(sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' >>/var/log/omarchy-install.log) 2>&1
  unset CURRENT_SCRIPT
  stop_log_output
}

install_omarchy() {
  # Ensure git and gum are installed in the installed system
  arch-chroot /mnt bash -c "
    pacman -Qi git >/dev/null 2>&1 || pacman -S --noconfirm git
    pacman -Qi gum >/dev/null 2>&1 || pacman -S --noconfirm gum
  "

  chroot_bash -lc "
    REPO=/home/$OMARCHY_USER/lishalinux
    URL=https://github.com/rawalrauf/lishalinux.git

    # Retry cloning until complete
    while true; do
      # Remove any partial clone from previous attempts
      rm -rf \"\$REPO\"

      # Try to clone
      git clone \"\$URL\" \"\$REPO\" && {

        # Check if install.sh exists
        if [[ -f \"\$REPO/install.sh\" ]]; then
          break  # Success, repo fully cloned
        else
          echo 'Clone incomplete (install.sh missing). Retrying in 5 seconds...'
          sleep 5
        fi
      } || {
        echo 'Git clone failed. Retrying in 5 seconds...'
        sleep 5
      }
    done

    # Ensure correct ownership
    chown -R $OMARCHY_USER:$OMARCHY_USER \"\$REPO\"

    # Run installer from user home safely
    CUR_DIR=\$(pwd)
    cd /home/$OMARCHY_USER/
    source lishalinux/install.sh || bash
    cd \"\$CUR_DIR\" || exit
  "

  # Reboot if installer signals completion
  [[ -f /mnt/var/tmp/omarchy-install-completed ]] && reboot
}

# Set Tokyo Night color scheme for the terminal
set_tokyo_night_colors() {
  if [[ $(tty) == "/dev/tty"* ]]; then
    # Tokyo Night color palette
    echo -en "\e]P01a1b26" # black (background)
    echo -en "\e]P1f7768e" # red
    echo -en "\e]P29ece6a" # green
    echo -en "\e]P3e0af68" # yellow
    echo -en "\e]P47aa2f7" # blue
    echo -en "\e]P5bb9af7" # magenta
    echo -en "\e]P67dcfff" # cyan
    echo -en "\e]P7a9b1d6" # white
    echo -en "\e]P8414868" # bright black
    echo -en "\e]P9f7768e" # bright red
    echo -en "\e]PA9ece6a" # bright green
    echo -en "\e]PBe0af68" # bright yellow
    echo -en "\e]PC7aa2f7" # bright blue
    echo -en "\e]PDbb9af7" # bright magenta
    echo -en "\e]PE7dcfff" # bright cyan
    echo -en "\e]PFc0caf5" # bright white (foreground)

    # Set default foreground and background
    echo -en "\033[0m"
    clear
  fi
}

install_base_system() {
  findmnt -R /mnt >/dev/null && umount -R /mnt

  archinstall \
    --config user_configuration.json \
    --creds user_credentials.json \
    --silent

  mkdir -p /mnt/etc/sudoers.d
  cat >/mnt/etc/sudoers.d/99-omarchy-installer <<EOF
root ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
$OMARCHY_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF

  chmod 440 /mnt/etc/sudoers.d/99-omarchy-installer
}

chroot_bash() {
  HOME=/home/$OMARCHY_USER \
    arch-chroot -u $OMARCHY_USER /mnt/ \
    env OMARCHY_CHROOT_INSTALL=1 \
    OMARCHY_USER_NAME="$(<user_full_name.txt)" \
    OMARCHY_USER_EMAIL="$(<user_email_address.txt)" \
    USER="$OMARCHY_USER" \
    HOME="/home/$OMARCHY_USER" \
    /bin/bash "$@"
}

if [[ $(tty) == "/dev/tty1" ]]; then
  use_omarchy_helpers
  run_configurator
  install_arch
  install_omarchy
fi
