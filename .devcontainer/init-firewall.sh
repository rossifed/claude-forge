#!/usr/bin/env bash
# Firewall initialization for Claude Code devcontainer
# Restricts outbound network to only necessary services.
# Based on Anthropic's official reference: https://code.claude.com/docs/en/devcontainer
set -euo pipefail

# Only run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: init-firewall.sh must run as root (use sudo)"
    exit 1
fi

echo "Initializing firewall rules..."

# Save existing Docker DNS rules before flushing
DOCKER_DNS_RULES=$(iptables-save | grep -i docker 2>/dev/null || true)

# Flush existing rules
iptables -F OUTPUT
iptables -F INPUT
iptables -F FORWARD

# Create ipset for allowed IPs
ipset destroy allowed_ips 2>/dev/null || true
ipset create allowed_ips hash:net

# --- Allowed domains ---
ALLOWED_DOMAINS=(
    "api.anthropic.com"
    "statsig.anthropic.com"
    "sentry.io"
    "registry.npmjs.org"
    "github.com"
    "api.github.com"
    "objects.githubusercontent.com"
    "update.code.visualstudio.com"
    "marketplace.visualstudio.com"
)

# Resolve domains and add to ipset
for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
    for ip in $ips; do
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ipset add allowed_ips "$ip/32" 2>/dev/null || true
        fi
    done
done

# Add GitHub IP ranges (from their meta API)
GH_META=$(curl -sf https://api.github.com/meta 2>/dev/null || true)
if [ -n "$GH_META" ]; then
    for cidr in $(echo "$GH_META" | jq -r '(.git // [])[], (.web // [])[], (.api // [])[]' 2>/dev/null | grep -E '^[0-9]'); do
        ipset add allowed_ips "$cidr" 2>/dev/null || true
    done
fi

# --- Baseline rules ---
# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (UDP + TCP port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Allow host network (for Docker bridge, VS Code server, etc.)
HOST_NET=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$HOST_NET" ]; then
    HOST_SUBNET=$(echo "$HOST_NET" | sed 's/\.[0-9]*$/.0\/16/')
    iptables -A OUTPUT -d "$HOST_SUBNET" -j ACCEPT
fi

# Allow ipset destinations (HTTPS)
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed_ips dst -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -m set --match-set allowed_ips dst -j ACCEPT

# --- Default deny ---
iptables -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p udp -j REJECT --reject-with icmp-port-unreachable

echo "Firewall initialized. Allowed domains: ${ALLOWED_DOMAINS[*]}"

# --- Verification ---
echo -n "Verifying firewall... "
if curl -sf --max-time 3 https://example.com >/dev/null 2>&1; then
    echo "WARNING: example.com is reachable (firewall may not be effective)"
else
    echo "OK (unauthorized domains blocked)"
fi
