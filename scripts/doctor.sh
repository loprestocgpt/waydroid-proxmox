#!/usr/bin/env bash

# Waydroid container doctor
# Performs quick validation of binder/ashmem, LXC device permissions,
# required packages, Wayland/VNC availability, Waydroid status,
# and API health checks with actionable guidance.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/helper-functions.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/helper-functions.sh"
else
    BL="\033[36m"; RD="\033[01;31m"; GN="\033[1;92m"; YW="\033[1;93m"; CL="\033[m"
    CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"
    msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
    msg_ok() { echo -e "${CM} $1"; }
    msg_error() { echo -e "${CROSS} $1"; }
    msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }
fi

set -o pipefail
FAILURES=0
WARNINGS=0

add_failure() { FAILURES=$((FAILURES + 1)); }
add_warning() { WARNINGS=$((WARNINGS + 1)); }

print_header() {
    echo -e "${GN}=== Waydroid Doctor ===${CL}"
    echo "Checks binder/ashmem, permissions, services, and API health."
    echo ""
}

check_binder_stack() {
    msg_info "Checking binder/ashmem/binderfs"

    local has_binder_device=false
    local has_ashmem_device=false
    local has_binderfs=false

    [ -e /dev/binder ] || [ -e /dev/binderfs/binder ] && has_binder_device=true
    [ -e /dev/ashmem ] && has_ashmem_device=true
    mount | grep -q "binderfs" && has_binderfs=true

    if lsmod 2>/dev/null | grep -q "^binder_linux"; then
        msg_ok "binder_linux module loaded"
    else
        msg_error "binder_linux module missing — load it on the host and expose /dev/binder to the container"
        add_failure
    fi

    if lsmod 2>/dev/null | grep -q "^ashmem_linux"; then
        msg_ok "ashmem_linux module loaded"
    else
        msg_error "ashmem_linux module missing — enable the module on the host and pass /dev/ashmem into LXC"
        add_failure
    fi

    if $has_binderfs; then
        msg_ok "binderfs mounted"
    else
        msg_warn "binderfs not mounted — mount binderfs (e.g., lxc.mount.entry = binder none binder rw 0 0) for modern binder setups"
        add_warning
    fi

    if $has_binder_device; then
        msg_ok "Binder device node present"
    else
        msg_error "Binder device missing — add /dev/binder or binderfs nodes to the container config"
        add_failure
    fi

    if $has_ashmem_device; then
        msg_ok "Ashmem device node present"
    else
        msg_error "Ashmem device missing — add /dev/ashmem to the container config"
        add_failure
    fi

    echo ""
}

check_lxc_permissions() {
    msg_info "Checking LXC device permissions"

    local devices=(/dev/binder /dev/ashmem)
    local issues=0

    for dev in "${devices[@]}"; do
        [ -e "$dev" ] || continue
        local perm owner group
        perm=$(stat -c "%a" "$dev")
        owner=$(stat -c "%U:%G" "$dev")

        if [ "$perm" -ge 660 ]; then
            msg_ok "$dev permissions OK ($owner $perm)"
        else
            msg_error "$dev permissions too restrictive ($owner $perm) — update LXC cgroup rules to allow rw access"
            issues=1
        fi

        if id waydroid &>/dev/null; then
            if sudo -u waydroid test -r "$dev" && sudo -u waydroid test -w "$dev"; then
                msg_ok "waydroid user can access $dev"
            else
                msg_error "waydroid user lacks access to $dev — ensure lxc.idmap/lxc.cgroup2.devices.allow covers binder/ashmem"
                issues=1
            fi
        fi
    done

    if [ $issues -ne 0 ]; then
        add_failure
    fi

    echo ""
}

check_packages() {
    msg_info "Checking required packages"

    local -a requirements=(
        "waydroid:waydroid"
        "wayvnc:wayvnc"
        "sway:sway"
        "curl:curl"
        "python3:python3"
        "netstat:net-tools"
    )

    local missing=()
    for entry in "${requirements[@]}"; do
        local cmd pkg
        cmd=${entry%%:*}
        pkg=${entry##*:}
        if command -v "$cmd" &>/dev/null; then
            msg_ok "$pkg installed"
        else
            msg_error "$pkg missing — install with: apt-get install -y $pkg"
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        add_failure
    fi

    echo ""
}

check_wayland() {
    msg_info "Checking Wayland socket"

    local socket="${WAYLAND_DISPLAY:-wayland-0}"
    local socket_paths=("/run/user/0/${socket}" "/run/${socket}")
    local found=false

    for path in "${socket_paths[@]}"; do
        if [ -S "$path" ]; then
            msg_ok "Wayland socket available at $path"
            found=true
            break
        fi
    done

    if ! $found; then
        msg_error "Wayland socket not found — ensure sway/wayvnc is running (systemctl restart waydroid-vnc.service)"
        add_failure
    fi

    echo ""
}

check_vnc_port() {
    msg_info "Checking VNC port"

    local port=5900
    if ss -ltnp 2>/dev/null | grep -q ":${port} "; then
        local listener
        listener=$(ss -ltnp 2>/dev/null | grep ":${port} " | awk '{print $NF}' | head -n1)
        msg_ok "Port ${port} listening (${listener})"
    elif netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        msg_ok "Port ${port} listening"
    else
        msg_error "Port ${port} closed — start WayVNC: systemctl restart waydroid-vnc.service"
        add_failure
    fi

    echo ""
}

check_waydroid_status() {
    msg_info "Checking Waydroid status"

    if ! command -v waydroid &>/dev/null; then
        msg_error "Waydroid not installed"
        add_failure
        echo ""
        return
    fi

    if waydroid status 2>/dev/null | grep -q "RUNNING"; then
        msg_ok "Waydroid container running"
    else
        msg_error "Waydroid not running — start with: systemctl restart waydroid-container.service && waydroid session start"
        add_failure
    fi

    echo ""
}

check_api_health() {
    msg_info "Checking API /health"

    local response
    response=$(curl -fsS --max-time 5 http://localhost:8080/health 2>/dev/null || true)

    if [ -n "$response" ] && echo "$response" | grep -qi "healthy"; then
        msg_ok "API responded with healthy"
    else
        msg_error "API not responding — verify waydroid-api.service is active and port 8080 reachable"
        add_failure
    fi

    echo ""
}

main() {
    print_header
    check_binder_stack
    check_lxc_permissions
    check_packages
    check_wayland
    check_vnc_port
    check_waydroid_status
    check_api_health

    if [ $FAILURES -eq 0 ]; then
        msg_ok "All critical checks passed"
    else
        msg_error "$FAILURES critical check(s) failed"
    fi

    if [ $WARNINGS -gt 0 ]; then
        msg_warn "$WARNINGS warning(s) detected"
    fi

    exit $FAILURES
}

main "$@"
