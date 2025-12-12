#!/bin/bash
set -euo pipefail

WAY_USER="waydroid"
WAY_UID=$(id -u "$WAY_USER")
RUNTIME_DIR="/run/user/${WAY_UID}"
WAYLAND_SOCKET="${RUNTIME_DIR}/wayland-1"

print_header() {
    echo "==== Waydroid Doctor ===="
}

print_header

echo "Waydroid UID: ${WAY_UID}"
echo "Runtime dir: ${RUNTIME_DIR} (exists: $([ -d "$RUNTIME_DIR" ] && echo yes || echo no))"
echo "Wayland socket: ${WAYLAND_SOCKET} (exists: $([ -S "$WAYLAND_SOCKET" ] && echo yes || echo no))"

echo "\nService status:"
for svc in waydroid-container.service waydroid-vnc.service waydroid-ui.service waydroid-api.service; do
    if systemctl is-active --quiet "$svc"; then
        echo "  - $svc: active"
    else
        echo "  - $svc: $(systemctl is-active "$svc" 2>/dev/null || echo inactive)"
    fi
done

echo "\nPorts (5900 VNC, 8080 API):"
ss -tlnp 2>/dev/null | grep -E ':(5900|8080)\b' || echo "  No listeners on 5900 or 8080"

echo "\nWaydroid status:"
if command -v waydroid >/dev/null 2>&1; then
    waydroid status || true
else
    echo "  waydroid command not found"
fi

echo "\nAPI health check (http://localhost:8080/health):"
if command -v curl >/dev/null 2>&1; then
    curl -fsS http://localhost:8080/health || echo "  curl request failed"
else
    echo "  curl not available; test manually with: curl -fsS http://localhost:8080/health"
fi
