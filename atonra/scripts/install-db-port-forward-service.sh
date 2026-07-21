#!/usr/bin/env bash
# One-shot installer: sets up the db-port-forwards systemd user service.
# After this runs once, the DB tunnels (5434/5435/5436) stay open permanently,
# restart on their own, and survive reboots and closed sessions.
set -euo pipefail

FORGE_SCRIPT="$HOME/dev/claude-forge/atonra/scripts/db-port-forward-keepalive.sh"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
cp "$FORGE_SCRIPT" "$HOME/.local/bin/db-port-forward-keepalive.sh"
chmod +x "$HOME/.local/bin/db-port-forward-keepalive.sh"

cat > "$HOME/.config/systemd/user/db-port-forwards.service" <<'EOF'
[Unit]
Description=Keep kubectl port-forwards to AWS databases alive
After=network-online.target

[Service]
ExecStart=%h/.local/bin/db-port-forward-keepalive.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now db-port-forwards
loginctl enable-linger "$USER"

echo ""
echo "OK — service 'db-port-forwards' installed and running."
echo "Check anytime with: systemctl --user status db-port-forwards"
