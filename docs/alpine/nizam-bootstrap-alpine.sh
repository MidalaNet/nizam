#!/bin/sh
set -eu

# nizam-bootstrap-alpine.sh
# Alpine 3.23.x — modular bootstrap: from zero → X11 (Xorg + startx) → pekwm
#
# Examples:
#   doas sh nizam-bootstrap-alpine.sh all
#   doas sh nizam-bootstrap-alpine.sh base x11 pekwm
#   doas NIZAM_USER=nizam sh nizam-bootstrap-alpine.sh base x11 pekwm
#   doas INSTALL_VESA=1 sh nizam-bootstrap-alpine.sh x11
#
# Available modules:
#   base        : apk update + minimal tooling + doas + git + base services (eudev/dbus/elogind)
#   build       : build toolchain (build-base, meson, ninja, pkgconf, cmake, python3)
#   vala        : Vala compiler
#   gtk         : GTK3 dev/runtime (useful for Nizam GTK apps)
#   x11         : Xorg + xinit + libinput + mesa + basic utilities
#   pekwm       : pekwm window manager + xterm + xrandr
#   user        : video/input groups + minimal .xinitrc (starts pekwm)
#   all         : base build vala gtk x11 pekwm user
#
# Variables:
#   NIZAM_USER=<user>          (default: nizam)
#   INSTALL_VESA=1             adds xf86-video-vesa/fbdev (useful for VM/driver fallback)

NIZAM_USER="${NIZAM_USER:-nizam}"
INSTALL_VESA="${INSTALL_VESA:-0}"

say() { printf '%s\n' "$*"; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    say "ERROR: run as root (doas/sudo)."
    exit 1
  fi
}

apk_add() {
  # apk add is idempotent; if a package is missing, it will be installed.
  apk add "$@"
}

enable_service() {
  svc="$1"
  rc-update add "$svc" default >/dev/null 2>&1 || true
  rc-service "$svc" start >/dev/null 2>&1 || true
}

user_home() {
  getent passwd "$1" | cut -d: -f6 2>/dev/null || true
}

ensure_groups_and_user_files() {
  # Typical groups for DRI/input on Xorg
  addgroup -S video >/dev/null 2>&1 || true
  addgroup -S input >/dev/null 2>&1 || true

  if id "$NIZAM_USER" >/dev/null 2>&1; then
    adduser "$NIZAM_USER" video >/dev/null 2>&1 || true
    adduser "$NIZAM_USER" input >/dev/null 2>&1 || true
  else
    say "WARN: user '$NIZAM_USER' not found; skipping group setup and .xinitrc."
    return 0
  fi

  home="$(user_home "$NIZAM_USER")"
  [ -n "$home" ] || return 0

  xinitrc="$home/.xinitrc"
  if [ ! -f "$xinitrc" ]; then
    cat >"$xinitrc" <<EOX
#!/bin/sh
# Alpine + OpenRC: minimal X session for pekwm

# D-Bus for the X session (many GTK apps use it)
if command -v dbus-launch >/dev/null 2>&1; then
  eval "\$(dbus-launch --sh-syntax --exit-with-session)"
fi

# Basic cursor
command -v xsetroot >/dev/null 2>&1 && xsetroot -cursor_name left_ptr

# WM
if command -v pekwm >/dev/null 2>&1; then
  exec pekwm
fi

# Fallback
exec xterm
EOX
    chown "$NIZAM_USER":"$NIZAM_USER" "$xinitrc"
    chmod 0755 "$xinitrc"
  fi
}

mod_base() {
  say "[base] apk update + minimal tools + base services (eudev/dbus/elogind)"
  apk update
  apk_add ca-certificates tzdata doas git
  # Essential services for input/seat/session
  apk_add eudev dbus dbus-x11 elogind
  enable_service udev
  enable_service dbus
  enable_service elogind
}

mod_build() {
  say "[build] build toolchain"
  apk_add build-base meson ninja pkgconf cmake python3
}

mod_vala() {
  say "[vala] Vala compiler"
  apk_add vala
}

mod_gtk() {
  say "[gtk] GTK3 dev/runtime"
  apk_add gtk+3.0 gtk+3.0-dev glib-dev gobject-introspection-dev
}

mod_x11() {
  say "[x11] Xorg + startx + libinput + mesa + tools"
  apk_add \
    xorg-server \
    xinit \
    xf86-input-libinput \
    mesa-dri-gallium \
    mesa-gl \
    xrandr \
    xsetroot

  if [ "$INSTALL_VESA" = "1" ]; then
    say "[x11] INSTALL_VESA=1 → installing fallback vesa/fbdev drivers"
    apk_add xf86-video-vesa xf86-video-fbdev || true
  fi
}

mod_pekwm() {
  say "[pekwm] window manager + terminal + utilities"
  # Note: on Alpine the package is typically "pekwm" (community repo).
  apk_add pekwm xterm
}

mod_user() {
  say "[user] groups + .xinitrc"
  ensure_groups_and_user_files
}

usage() {
  cat <<EOF
Usage:
  doas sh $0 <module> [module...]

Modules:
  base build vala gtk x11 pekwm user all

Variables:
  NIZAM_USER=<user>   (default: nizam)
  INSTALL_VESA=1      video fallback drivers

Examples:
  doas sh $0 all
  doas NIZAM_USER=nizam sh $0 base x11 pekwm user
EOF
}

need_root

[ "${1:-}" ] || { usage; exit 2; }

# Expand "all"
mods=""
for m in "$@"; do
  if [ "$m" = "all" ]; then
    mods="$mods base build vala gtk x11 pekwm user"
  else
    mods="$mods $m"
  fi
done

for m in $mods; do
  case "$m" in
    base)  mod_base ;;
    build) mod_build ;;
    vala)  mod_vala ;;
    gtk)   mod_gtk ;;
    x11)   mod_x11 ;;
    pekwm) mod_pekwm ;;
    user)  mod_user ;;
    *) say "ERROR: unknown module: $m"; usage; exit 2 ;;
  esac
done

cat <<EOF

OK.

Test (as user $NIZAM_USER):
  su - $NIZAM_USER
  startx

Quick debug:
  - If startx fails, check: ~/.local/share/xorg/Xorg.0.log or /var/log/Xorg.0.log
  - Verify services are active:
      rc-service udev status
      rc-service dbus status
      rc-service elogind status
EOF
