#!/bin/bash
# system76-typing-backlight — install/uninstall/status helper.
#
# Usage:
#   ./kbd-backlight-typing-setup.sh                # interactive menu
#   ./kbd-backlight-typing-setup.sh install        # install non-interactively
#   ./kbd-backlight-typing-setup.sh uninstall      # uninstall (KEEP_CONFIG=1 to keep config)
#   ./kbd-backlight-typing-setup.sh status         # print status and exit
#   ./kbd-backlight-typing-setup.sh restart        # restart the systemd service
#   ./kbd-backlight-typing-setup.sh -h | --help

set -uo pipefail

VERSION="1.0.0"

SRC="$(cd "$(dirname "$0")" && pwd)"

BIN_DAEMON=/usr/local/bin/kbd-backlight-typing
BIN_APPLY=/usr/local/bin/kbd-backlight-typing-apply
BIN_GUI=/usr/local/bin/kbd-backlight-typing-gui
SVC=/etc/systemd/system/kbd-backlight-typing.service
POL=/usr/share/polkit-1/actions/com.system76.kbdbacklight.policy
DESK=/usr/share/applications/kbd-backlight-typing.desktop
CONF=/etc/kbd-backlight-typing.conf

usage() {
    cat <<'EOF'
system76-typing-backlight — install/uninstall/status helper.

Usage:
  ./kbd-backlight-typing-setup.sh                # interactive menu
  ./kbd-backlight-typing-setup.sh install        # install non-interactively
  ./kbd-backlight-typing-setup.sh uninstall      # uninstall (KEEP_CONFIG=1 to keep config)
  ./kbd-backlight-typing-setup.sh status         # print status and exit
  ./kbd-backlight-typing-setup.sh restart        # restart the systemd service
  ./kbd-backlight-typing-setup.sh -h | --help
  ./kbd-backlight-typing-setup.sh --version
EOF
    exit 0
}

is_installed() { [ -f "$BIN_DAEMON" ] && [ -f "$SVC" ]; }

require_sources() {
    local missing=0
    for f in kbd-backlight-typing kbd-backlight-typing-apply kbd-backlight-typing-gui \
             kbd-backlight-typing.service kbd-backlight-typing.policy kbd-backlight-typing.desktop; do
        if [ ! -f "$SRC/$f" ]; then
            echo "  missing: $SRC/$f"
            missing=1
        fi
    done
    if [ "$missing" = "1" ]; then
        echo "Source files missing. Run this script from the cloned repository." >&2
        exit 1
    fi
}

check_deps() {
    local warn=0
    if ! command -v python3 >/dev/null 2>&1; then
        echo "WARN: python3 not found (required by daemon and GUI)" >&2
        warn=1
    fi
    if ! command -v pkexec >/dev/null 2>&1; then
        echo "WARN: pkexec not found (required by GUI; install 'policykit-1' or 'polkit')" >&2
        warn=1
    fi
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" \
                >/dev/null 2>&1; then
            echo "WARN: PyGObject GTK 3 bindings missing (apt: python3-gi gir1.2-gtk-3.0 / dnf: python3-gobject gtk3)" >&2
            echo "      The daemon will still work; the GUI will fail to launch until this is installed." >&2
            warn=1
        fi
    fi
    if ! ls /sys/class/leds/*kbd_backlight* >/dev/null 2>&1; then
        echo "WARN: no *kbd_backlight* LED found under /sys/class/leds/ -- the daemon will not start" >&2
        warn=1
    fi
    return $warn
}

do_install() {
    require_sources
    check_deps || true
    install -m 755 "$SRC/kbd-backlight-typing"         "$BIN_DAEMON"
    install -m 755 "$SRC/kbd-backlight-typing-apply"   "$BIN_APPLY"
    install -m 755 "$SRC/kbd-backlight-typing-gui"     "$BIN_GUI"
    install -m 644 "$SRC/kbd-backlight-typing.service" "$SVC"
    install -m 644 "$SRC/kbd-backlight-typing.policy"  "$POL"
    install -m 644 "$SRC/kbd-backlight-typing.desktop" "$DESK"
    if [ ! -f "$CONF" ]; then
        cat > "$CONF" <<EOF
[settings]
enabled = true
active_brightness = 128
inactive_brightness = 0
idle_seconds = 60
always_on_enabled = false
always_on_from = 21:00
always_on_to = 06:00
EOF
        echo "  wrote default config: $CONF"
    else
        echo "  kept existing config: $CONF"
    fi
    systemctl daemon-reload
    systemctl enable --now kbd-backlight-typing.service
    echo "Installed. Search 'Keyboard Backlight' in the app launcher."
}

do_uninstall() {
    local keep_config="$1"
    systemctl disable --now kbd-backlight-typing.service 2>/dev/null || true
    rm -f "$BIN_DAEMON" "$BIN_APPLY" "$BIN_GUI" "$SVC" "$POL" "$DESK"
    case "$keep_config" in
        y|yes|1|true)
            echo "  kept config: $CONF" ;;
        *)
            rm -f "$CONF"
            echo "  removed config: $CONF" ;;
    esac
    systemctl daemon-reload
    echo "Uninstalled."
}

show_status() {
    echo "system76-typing-backlight setup ($VERSION)"
    if is_installed; then
        echo "Status: installed"
        systemctl is-enabled kbd-backlight-typing.service 2>/dev/null | sed 's/^/  service enabled: /'
        systemctl is-active  kbd-backlight-typing.service 2>/dev/null | sed 's/^/  service active:  /'
        if [ -f "$CONF" ]; then
            echo "  config:"
            sed 's/^/    /' "$CONF"
        fi
    else
        echo "Status: not installed"
    fi
}

prompt() {
    local q="$1" default="${2:-}" ans
    if [ -n "$default" ]; then
        read -r -p "$q [$default]: " ans
        echo "${ans:-$default}"
    else
        read -r -p "$q: " ans
        echo "$ans"
    fi
}

menu() {
    echo
    show_status
    echo
    if is_installed; then
        echo "  1) Reinstall (overwrite files, keep config)"
        echo "  2) Uninstall"
        echo "  3) Restart service"
        echo "  q) Quit"
        echo
        echo "  (To open the settings GUI: search 'Keyboard Backlight' in the"
        echo "   application launcher, or run 'kbd-backlight-typing-gui' from a"
        echo "   normal user terminal.)"
        local choice
        choice="$(prompt "Choose" "q")"
        case "$choice" in
            1) do_install ;;
            2)
                local keep
                keep="$(prompt "Keep config file? (y/N)" "n")"
                do_uninstall "${keep,,}"
                ;;
            3) systemctl restart kbd-backlight-typing.service && echo "Restarted." ;;
            q|Q) exit 0 ;;
            *) echo "Unknown choice." ;;
        esac
    else
        echo "  1) Install"
        echo "  q) Quit"
        local choice
        choice="$(prompt "Choose" "1")"
        case "$choice" in
            1) do_install ;;
            q|Q) exit 0 ;;
            *) echo "Unknown choice." ;;
        esac
    fi
}

# Parse subcommand (if any) before sudo-elevating, so we can show --help without root.
SUBCMD="${1:-}"
case "$SUBCMD" in
    -h|--help|help) usage ;;
    --version) echo "$VERSION"; exit 0 ;;
esac

if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

case "$SUBCMD" in
    "")        menu ;;
    install)   do_install ;;
    uninstall)
        if [ "${KEEP_CONFIG:-0}" = "1" ]; then
            do_uninstall "y"
        else
            do_uninstall "n"
        fi
        ;;
    status)    show_status ;;
    restart)   systemctl restart kbd-backlight-typing.service && echo "Restarted." ;;
    *) echo "Unknown subcommand: $SUBCMD" >&2; echo "Try --help" >&2; exit 2 ;;
esac
