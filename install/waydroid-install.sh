#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: iceteaSA
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/iceteaSA/waydroid-proxmox

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Load environment variables set by wrapper
if [ -f /tmp/waydroid-env.sh ]; then
    source /tmp/waydroid-env.sh
fi

# Default values if not set
GPU_TYPE="${GPU_TYPE:-software}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING:-1}"
USE_GAPPS="${USE_GAPPS:-yes}"

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    sudo \
    gnupg \
    ca-certificates \
    lsb-release \
    software-properties-common \
    wget \
    unzip \
    wayland-protocols \
    weston \
    sway \
    xwayland \
    python3 \
    python3-pip \
    python3-venv \
    git \
    net-tools \
    dbus-x11
msg_ok "Installed Dependencies"

# Install GPU drivers if hardware acceleration enabled
if [ "$SOFTWARE_RENDERING" != "1" ]; then
    msg_info "Installing GPU Drivers for ${GPU_TYPE}"

    case $GPU_TYPE in
        intel)
            $STD apt-get install -y \
                intel-media-va-driver \
                i965-va-driver \
                mesa-va-drivers \
                mesa-vulkan-drivers \
                libgl1-mesa-dri \
                vainfo
            ;;
        amd)
            $STD apt-get install -y \
                mesa-va-drivers \
                mesa-vulkan-drivers \
                libgl1-mesa-dri \
                firmware-amd-graphics \
                vainfo
            ;;
        *)
            msg_info "No specific GPU drivers needed for ${GPU_TYPE}"
            ;;
    esac

    msg_ok "Installed GPU Drivers"
fi

msg_info "Adding Waydroid Repository"
# Download and install Waydroid GPG key
wget -q -O /tmp/waydroid.gpg https://repo.waydro.id/waydroid.gpg
gpg --dearmor < /tmp/waydroid.gpg > /usr/share/keyrings/waydroid-archive-keyring.gpg
rm -f /tmp/waydroid.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/waydroid-archive-keyring.gpg] https://repo.waydro.id/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/waydroid.list
$STD apt-get update
msg_ok "Added Waydroid Repository"

msg_info "Installing Waydroid"
$STD apt-get install -y waydroid
msg_ok "Installed Waydroid"

msg_info "Installing VNC Server"
$STD apt-get install -y wayvnc tigervnc-viewer tigervnc-common
msg_ok "Installed VNC Server"

# Configure GPU access
if [ "$SOFTWARE_RENDERING" != "1" ]; then
    msg_info "Configuring GPU Access"

    groupadd -f render
    usermod -aG render root
    usermod -aG video root

    mkdir -p /var/lib/waydroid/lxc/waydroid/

    case $GPU_TYPE in
        intel|amd)
            cat > /etc/udev/rules.d/99-waydroid-gpu.rules <<'EOF'
# GPU devices for Waydroid
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG+="waydroid", GROUP="render", MODE="0660"
SUBSYSTEM=="drm", KERNEL=="renderD*", TAG+="waydroid", GROUP="render", MODE="0660"
EOF
            ;;
    esac

    msg_ok "Configured GPU Access"
fi

msg_info "Creating waydroid user"
# Create system user for running compositor and waydroid (Sway won't run as root)
if ! id -u waydroid >/dev/null 2>&1; then
    useradd -r -s /bin/bash -d /home/waydroid -m waydroid
fi
# Add to video/render groups for GPU access
usermod -aG video,render waydroid

# Give waydroid user access to /var/lib/waydroid
mkdir -p /var/lib/waydroid
chown -R waydroid:waydroid /var/lib/waydroid
msg_ok "Created waydroid user"

msg_info "Setting up VNC"
# Create VNC config for waydroid user
mkdir -p /home/waydroid/.config/wayvnc
chown -R waydroid:waydroid /home/waydroid/.config

# Generate VNC password using openssl (more reliable in LXC)
VNC_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
echo "$VNC_PASSWORD" > /home/waydroid/.config/wayvnc/password
chmod 600 /home/waydroid/.config/wayvnc/password
chown waydroid:waydroid /home/waydroid/.config/wayvnc/password

cat > /home/waydroid/.config/wayvnc/config <<EOF
address=0.0.0.0
port=5900
enable_auth=true
username=waydroid
password_file=/home/waydroid/.config/wayvnc/password
max_rate=60
EOF
chown waydroid:waydroid /home/waydroid/.config/wayvnc/config

# Save password for user reference (keep in root for easy access)
echo "$VNC_PASSWORD" > /root/vnc-password.txt
chmod 600 /root/vnc-password.txt
msg_ok "VNC Configured (password saved to /root/vnc-password.txt)"

msg_info "Creating compositor and VNC launcher"
cat > /usr/local/bin/waydroid-compositor.sh <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

DISPLAY_USER="waydroid"
DISPLAY_UID=$(id -u "$DISPLAY_USER")
DISPLAY_GID=$(id -g "$DISPLAY_USER")
DISPLAY_XDG_RUNTIME_DIR="/run/user/${DISPLAY_UID}"

mkdir -p "$DISPLAY_XDG_RUNTIME_DIR"
chown "$DISPLAY_UID:$DISPLAY_GID" "$DISPLAY_XDG_RUNTIME_DIR"
chmod 700 "$DISPLAY_XDG_RUNTIME_DIR"

SOFTWARE_RENDERING=${SOFTWARE_RENDERING:-}
if [ -z "$SOFTWARE_RENDERING" ]; then
    if compgen -G "/dev/dri/renderD*" > /dev/null; then
        SOFTWARE_RENDERING=0
    else
        SOFTWARE_RENDERING=1
    fi
fi

SWAY_ENV=(
    "XDG_RUNTIME_DIR=${DISPLAY_XDG_RUNTIME_DIR}"
    "WLR_BACKENDS=headless"
    "WLR_LIBINPUT_NO_DEVICES=1"
    "WLR_RENDERER_ALLOW_SOFTWARE=1"
)

if [ "$SOFTWARE_RENDERING" = "1" ]; then
    SWAY_ENV+=("LIBGL_ALWAYS_SOFTWARE=1")
fi

runuser -u "$DISPLAY_USER" -- env "${SWAY_ENV[@]}" sway \
    > /var/log/waydroid-sway.log 2>&1 &
SWAY_PID=$!

WAYLAND_DISPLAY=""
for _ in {1..30}; do
    sleep 1
    for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$socket" ]; then
            WAYLAND_DISPLAY=$(basename "$socket")
            break
        fi
    done
    [ -n "$WAYLAND_DISPLAY" ] && break
done

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "Wayland socket not found after 30s" >&2
    kill "$SWAY_PID" 2>/dev/null || true
    exit 1
fi

mkdir -p /run/user/0
chown root:root /run/user/0
chmod 700 /run/user/0

ln -sf "${DISPLAY_XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" "/run/user/0/${WAYLAND_DISPLAY}"
chmod 660 "${DISPLAY_XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

WAYVNC_ENV=(
    "XDG_RUNTIME_DIR=${DISPLAY_XDG_RUNTIME_DIR}"
    "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
)

runuser -u "$DISPLAY_USER" -- env "${WAYVNC_ENV[@]}" \
    wayvnc 0.0.0.0 5900 > /var/log/waydroid-wayvnc.log 2>&1 &
WAYVNC_PID=$!

for i in {1..20}; do
    sleep 1
    if ss -tlnp | grep -q ':5900'; then
        echo "WayVNC listening on :5900 (display ${WAYLAND_DISPLAY})"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "WayVNC failed to bind port 5900" >&2
        kill "$WAYVNC_PID" "$SWAY_PID" 2>/dev/null || true
        exit 1
    fi
done

wait "$SWAY_PID"
EOFSCRIPT

cat > /usr/local/bin/waydroid-ui.sh <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

DISPLAY_USER="waydroid"
DISPLAY_UID=$(id -u "$DISPLAY_USER")
DISPLAY_XDG_RUNTIME_DIR="/run/user/${DISPLAY_UID}"

if [ ! -d "/var/lib/waydroid/overlay" ]; then
    INIT_ARGS=("-f")
    if [ "${USE_GAPPS:-yes}" = "yes" ]; then
        INIT_ARGS=("-s" "GAPPS" "-f")
    fi

    waydroid init "${INIT_ARGS[@]}"
fi

systemctl start waydroid-container.service

for _ in {1..30}; do
    if systemctl is-active --quiet waydroid-container.service; then
        break
    fi
    sleep 1
done

WAYLAND_DISPLAY=""
for _ in {1..30}; do
    for socket in "$DISPLAY_XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$socket" ]; then
            WAYLAND_DISPLAY=$(basename "$socket")
            break
        fi
    done
    [ -n "$WAYLAND_DISPLAY" ] && break
    sleep 1
done

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "Wayland socket not available for UI launch" >&2
    exit 1
fi

UI_ENV=(
    "XDG_RUNTIME_DIR=${DISPLAY_XDG_RUNTIME_DIR}"
    "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
)

runuser -u "$DISPLAY_USER" -- env "${UI_ENV[@]}" waydroid session start || true
exec runuser -u "$DISPLAY_USER" -- env "${UI_ENV[@]}" waydroid show-full-ui
EOFSCRIPT
chmod +x /usr/local/bin/waydroid-compositor.sh /usr/local/bin/waydroid-ui.sh
msg_ok "Created compositor and UI launch scripts"

msg_info "Creating Systemd Services for Waydroid"
cat > /etc/systemd/system/waydroid-compositor.service <<EOF
[Unit]
Description=Waydroid headless compositor and WayVNC
After=waydroid-container.service
Wants=waydroid-container.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/waydroid-compositor.sh
Restart=on-failure
RestartSec=10
TimeoutStartSec=120
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/waydroid-ui.service <<EOF
[Unit]
Description=Waydroid full UI launcher
After=waydroid-container.service waydroid-compositor.service
Wants=waydroid-container.service waydroid-compositor.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/waydroid-ui.sh
Restart=on-failure
RestartSec=10
TimeoutStartSec=180
TimeoutStopSec=30
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable waydroid-compositor.service waydroid-ui.service
msg_ok "Created Waydroid services"

msg_info "Installing Home Assistant API"
cat > /usr/local/bin/waydroid-api.py <<'EOFAPI'
#!/usr/bin/env python3
"""Waydroid API for Home Assistant Integration"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import logging
import os
import secrets
import sys

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

API_TOKEN_FILE = '/etc/waydroid-api/token'

class WaydroidAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        logger.info("%s - %s" % (self.client_address[0], format % args))

    def _check_auth(self):
        """Check API token authentication"""
        if not os.path.exists(API_TOKEN_FILE):
            return True

        with open(API_TOKEN_FILE, 'r') as f:
            valid_token = f.read().strip()

        auth_header = self.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            return secrets.compare_digest(auth_header[7:], valid_token)
        return False

    def _send_json_response(self, status_code, data):
        """Send JSON response"""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _run_command(self, cmd):
        """Run shell command and return result"""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            return {
                'success': result.returncode == 0,
                'output': result.stdout,
                'error': result.stderr,
                'returncode': result.returncode
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'error': 'Command timed out',
                'returncode': -1
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'returncode': -1
            }

    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/health':
            self._send_json_response(200, {'status': 'healthy'})

        elif self.path == '/status':
            if not self._check_auth():
                self._send_json_response(401, {'error': 'Unauthorized'})
                return

            result = self._run_command(['waydroid', 'status'])
            status = 'running' if result['success'] else 'stopped'
            self._send_json_response(200, {
                'status': status,
                'output': result['output']
            })

        else:
            self._send_json_response(404, {'error': 'Not found'})

    def do_POST(self):
        """Handle POST requests"""
        if not self._check_auth():
            self._send_json_response(401, {'error': 'Unauthorized'})
            return

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode() if content_length > 0 else '{}'

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._send_json_response(400, {'error': 'Invalid JSON'})
            return

        if self.path == '/app/launch':
            package = data.get('package')
            if not package:
                self._send_json_response(400, {'error': 'Missing package parameter'})
                return

            result = self._run_command(['waydroid', 'app', 'launch', package])
            self._send_json_response(
                200 if result['success'] else 500,
                result
            )

        elif self.path == '/app/list':
            result = self._run_command(['waydroid', 'app', 'list'])
            self._send_json_response(
                200 if result['success'] else 500,
                result
            )

        else:
            self._send_json_response(404, {'error': 'Not found'})

def run_server(port=8080):
    """Start the API server"""
    # Create token if it doesn't exist
    os.makedirs(os.path.dirname(API_TOKEN_FILE), exist_ok=True)
    if not os.path.exists(API_TOKEN_FILE):
        token = secrets.token_urlsafe(32)
        with open(API_TOKEN_FILE, 'w') as f:
            f.write(token)
        os.chmod(API_TOKEN_FILE, 0o600)
        logger.info(f"Generated API token: {token}")
        print(f"API Token: {token}")
        print(f"Token saved to: {API_TOKEN_FILE}")

    httpd = HTTPServer(('0.0.0.0', port), WaydroidAPIHandler)
    logger.info(f'Waydroid API server starting on port {port}')
    print(f'API server listening on http://0.0.0.0:{port}')

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info('Shutting down API server')
        httpd.shutdown()

if __name__ == '__main__':
    run_server()
EOFAPI

chmod +x /usr/local/bin/waydroid-api.py
msg_ok "Installed API Script"

msg_info "Creating API Service"
cat > /etc/systemd/system/waydroid-api.service <<EOF
[Unit]
Description=Waydroid Home Assistant API
After=network-online.target waydroid-compositor.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/waydroid-api.py
Restart=always
RestartSec=10
TimeoutStartSec=30
User=root
WatchdogSec=30
MemoryHigh=256M
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable waydroid-api.service
msg_ok "Created API Service"

msg_info "Starting Services"
systemctl start waydroid-compositor.service
systemctl start waydroid-ui.service
systemctl start waydroid-api.service
msg_ok "Services Started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
