#!/bin/bash
# Dev mode on the device: power-off and halt become reboot (back to muOS), power key ignored.
#   tools/devmode.sh on|off|status     (runs over tools/dev.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-status}" in
  on) tools/dev.sh sh 'ln -sfn /usr/lib/systemd/system/reboot.target /etc/systemd/system/poweroff.target;
        ln -sfn /usr/lib/systemd/system/reboot.target /etc/systemd/system/halt.target;
        mkdir -p /etc/systemd/logind.conf.d; cp /usr/local/share/mdeck/devmode/10-devmode.conf /etc/systemd/logind.conf.d/;
        systemctl daemon-reload; echo devmode on' ;;
  off) tools/dev.sh sh 'rm -f /etc/systemd/system/poweroff.target /etc/systemd/system/halt.target;
        rm -f /etc/systemd/logind.conf.d/10-devmode.conf;
        systemctl daemon-reload; echo devmode off' ;;
  status) tools/dev.sh sh 'readlink /etc/systemd/system/poweroff.target || echo "poweroff is real"; ls /etc/systemd/logind.conf.d/' ;;
esac
