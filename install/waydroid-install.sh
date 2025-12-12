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

msg_info "Creating Waydroid Startup Script"
MESA_DRIVER=""
LIBVA_DRIVER=""
SOFTWARE_GL=""
SOFTWARE_WLR=""

if [ "$SOFTWARE_RENDERING" != "1" ]; then
    case $GPU_TYPE in
        intel)
            MESA_DRIVER="iris"
            LIBVA_DRIVER="iHD"
            ;;
        amd)
            MESA_DRIVER="radeonsi"
            LIBVA_DRIVER="radeonsi"
            ;;
    esac
else
    SOFTWARE_GL="1"
    SOFTWARE_WLR="1"
fi

cat > /usr/local/bin/waydroid-sway-launch.sh <<'EOFSWAY'
#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/run/waydroid}"
export XDG_RUNTIME_DIR="${STATE_DIR}/xdg"
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
[ -n "${MESA_DRIVER:-}" ] && export MESA_LOADER_DRIVER_OVERRIDE="$MESA_DRIVER"
[ -n "${LIBVA_DRIVER:-}" ] && export LIBVA_DRIVER_NAME="$LIBVA_DRIVER"
[ -n "${SOFTWARE_GL:-}" ] && export LIBGL_ALWAYS_SOFTWARE="$SOFTWARE_GL"
[ -n "${SOFTWARE_WLR:-}" ] && export WLR_RENDERER_ALLOW_SOFTWARE="$SOFTWARE_WLR"

mkdir -p "$XDG_RUNTIME_DIR"

systemd-notify --status="Starting sway compositor" || true
sway &
SWAY_PID=$!

WAYLAND_DISPLAY=""
for _ in {1..30}; do
    sleep 1
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$socket" ]; then
            WAYLAND_DISPLAY=$(basename "$socket")
            break
        fi
    done
    [ -n "$WAYLAND_DISPLAY" ] && break
done

if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "ERROR: No Wayland socket created by sway" >&2
    exit 1
fi

cat > "$STATE_DIR/wayland.env" <<EOF
XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
WAYLAND_DISPLAY=$WAYLAND_DISPLAY
EOF

systemd-notify --ready --status="Wayland ready: $WAYLAND_DISPLAY" || true
wait "$SWAY_PID"
EOFSWAY

chmod +x /usr/local/bin/waydroid-sway-launch.sh

cat > /usr/local/bin/waydroid-wayvnc-launch.sh <<'EOFWAYVNC'
#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/run/waydroid}"
WAYLAND_ENV="$STATE_DIR/wayland.env"

if [ ! -f "$WAYLAND_ENV" ]; then
    echo "ERROR: Wayland environment not found" >&2
    exit 1
fi

source "$WAYLAND_ENV"
export XDG_RUNTIME_DIR
export WAYLAND_DISPLAY

systemd-notify --status="Starting wayvnc against $WAYLAND_DISPLAY" || true
wayvnc 0.0.0.0 5900 &
WAYVNC_PID=$!

for _ in {1..30}; do
    if ss -tln | grep -q ':5900'; then
        systemd-notify --ready --status="WayVNC ready on 5900" || true
        wait "$WAYVNC_PID"
        exit 0
    fi
    sleep 1
done

echo "ERROR: WayVNC failed to listen on 5900" >&2
exit 1
EOFWAYVNC

chmod +x /usr/local/bin/waydroid-wayvnc-launch.sh

cat > /usr/local/bin/start-waydroid.sh <<'EOFSCRIPT'
#!/bin/bash
# Start Waydroid with VNC access

set -euo pipefail

STATE_DIR="${STATE_DIR:-/run/waydroid}"
WAYLAND_ENV="$STATE_DIR/wayland.env"
DISPLAY_USER="waydroid"

if [ ! -f "$WAYLAND_ENV" ]; then
    echo "ERROR: waydroid-sway.service did not publish a Wayland socket" >&2
    exit 1
fi

source "$WAYLAND_ENV"
export XDG_RUNTIME_DIR
export WAYLAND_DISPLAY

GPU_TYPE="${GPU_TYPE}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING}"
GPU_DEVICE="${GPU_DEVICE}"
RENDER_NODE="${RENDER_NODE}"

if [ "$SOFTWARE_RENDERING" = "0" ]; then
    case "$GPU_TYPE" in
        intel)
            export MESA_LOADER_DRIVER_OVERRIDE=iris
            export LIBVA_DRIVER_NAME=iHD
            ;;
        amd)
            export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
            export LIBVA_DRIVER_NAME=radeonsi
            ;;
    esac

    if [ -n "$GPU_DEVICE" ] && [[ "$GPU_DEVICE" =~ ^/dev/(dri/)?card[0-9]+$ ]]; then
        export DRI_PRIME=$(basename "$GPU_DEVICE" | sed 's/card//')
    fi
else
    export LIBGL_ALWAYS_SOFTWARE=1
fi

for _ in {1..15}; do
    if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && ss -tln | grep -q ':5900'; then
        break
    fi
    sleep 1
done

if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    echo "ERROR: Wayland socket not ready" >&2
    exit 1
fi

if ! ss -tln | grep -q ':5900'; then
    echo "ERROR: WayVNC not listening on port 5900" >&2
    exit 1
fi

if [ ! -d "/var/lib/waydroid/overlay" ]; then
    echo "Initializing Waydroid (this may take several minutes)..."
    INIT_ENV="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    if [ "${USE_GAPPS}" = "yes" ]; then
        su -c "$INIT_ENV waydroid init -s GAPPS -f" ${DISPLAY_USER}
    else
        su -c "$INIT_ENV waydroid init -f" ${DISPLAY_USER}
    fi
fi

WAYDROID_ENV="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

echo "Starting Waydroid container as ${DISPLAY_USER}..."
su -c "$WAYDROID_ENV waydroid container start" ${DISPLAY_USER}

echo "Starting Waydroid session as ${DISPLAY_USER}..."
su -c "$WAYDROID_ENV waydroid session start" ${DISPLAY_USER} &
SESSION_PID=$!

systemd-notify --ready --status="Waydroid session started on $WAYLAND_DISPLAY" || true

wait "$SESSION_PID"
EOFSCRIPT

chmod +x /usr/local/bin/start-waydroid.sh
msg_ok "Startup Scripts Created"

msg_info "Creating Systemd Service for Auto-start"

cat > /etc/systemd/system/waydroid-sway.service <<EOF
[Unit]
Description=Waydroid headless sway compositor
After=systemd-user-sessions.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=notify
User=waydroid
Group=waydroid
Environment="STATE_DIR=/run/waydroid"
Environment="MESA_DRIVER=$MESA_DRIVER"
Environment="LIBVA_DRIVER=$LIBVA_DRIVER"
Environment="SOFTWARE_GL=$SOFTWARE_GL"
Environment="SOFTWARE_WLR=$SOFTWARE_WLR"
ExecStart=/usr/local/bin/waydroid-sway-launch.sh
NotifyAccess=all
Restart=on-failure
RestartSec=10
RuntimeDirectory=waydroid

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/waydroid-vnc.service <<EOF
[Unit]
Description=WayVNC server for Waydroid
After=network.target waydroid-sway.service
Requires=waydroid-sway.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=notify
User=waydroid
Group=waydroid
Environment="STATE_DIR=/run/waydroid"
ExecStart=/usr/local/bin/waydroid-wayvnc-launch.sh
NotifyAccess=all
Restart=on-failure
RestartSec=15
TimeoutStartSec=120
TimeoutStopSec=30
RuntimeDirectory=waydroid

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/waydroid.service <<EOF
[Unit]
Description=Waydroid session stack
After=waydroid-vnc.service waydroid-sway.service waydroid-container.service
Requires=waydroid-vnc.service waydroid-sway.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=notify
User=root
Environment="STATE_DIR=/run/waydroid"
Environment="GPU_TYPE=$GPU_TYPE"
Environment="SOFTWARE_RENDERING=$SOFTWARE_RENDERING"
Environment="GPU_DEVICE=$GPU_DEVICE"
Environment="RENDER_NODE=$RENDER_NODE"
ExecStart=/usr/local/bin/start-waydroid.sh
NotifyAccess=all
Restart=on-failure
RestartSec=20
TimeoutStartSec=600
TimeoutStopSec=60
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable waydroid.service
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
After=waydroid.service network-online.target
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
systemctl start waydroid-vnc.service
sleep 5
systemctl start waydroid-api.service
msg_ok "Services Started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
