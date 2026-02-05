# Install

All **Nizam** components are built from this repository using a single root `Makefile`, with **Meson** and **Ninja** used internally as the build system. The instructions below assume a typical **UNIX**-like environment with an existing **X11 session**. **Nizam** is developed and tested primarily on **Debian**-based systems, but the build process is largely portable.

Before building, ensure a working **C toolchain** is installed together with **Vala** (`vala` and `valac`), **Meson**, **Ninja**, and **pkg-config**. An operational **X11** environment is required at runtime.

The core build depends on **GTK3** and **GLib**. At minimum, the following pkg-config modules must be available: `gtk+-3.0`, `gio-2.0`, `glib-2.0`, `gobject-2.0`, and `cairo`. Additional dependencies are required depending on which components are built. These include `sqlite3`, `gio-unix-2.0`, `librsvg-2.0`, `x11`, `xrandr`, `pangocairo`, `xcb`, `xcb-randr`, `dbus-1`, `gdk-pixbuf-2.0`, and `vte-2.91`. For the built-in documentation viewer, `webkit2gtk-4.1` (or `webkit2gtk-4.0`) and `libcmark-gfm` are also required.

From the repository root, you can perform a quick dependency check using `pkg-config`:

```sh
pkg-config --exists gtk+-3.0 gio-2.0 glib-2.0 || echo "Missing GTK/GLib"
pkg-config --exists sqlite3 || echo "Missing sqlite3"
pkg-config --exists x11 xrandr pangocairo || echo "Missing X11/pango (panel)"
pkg-config --exists xcb xcb-randr dbus-1 || echo "Missing XCB/DBus (dock)"
pkg-config --exists vte-2.91 || echo "Missing VTE (terminal)"
```

To build all components, run `make` from the repository root. The build output is generated in per-component build directories and does not modify the system.

Functional tests can be run with `make test`. Performance and stability regression checks are available via `make perf`, which performs a steady-state **RSS and CPU analysis** together with **Valgrind** runs. This target is intentionally slower and is meant for development and **CI** usage rather than routine builds.

Installation is performed with `sudo make install`. The installation prefix can be overridden using `make PREFIX=/usr install`, and staged installs are supported via `make DESTDIR=/tmp/pkgroot install`. Installed files are tracked using manifest files stored under `${PREFIX}/share/nizam/manifest/*.installlog`, which are also used to support clean removal with `sudo make uninstall`.

To run **Nizam**, a window manager must be present. **Nizam** is designed to operate with **pekwm** and relies on its **EWMH support** and theming model. After installation, launch `nizam-settings`, open the **Window Manager** page, and click `Apply`. This action sets up `~/.xinitrc` and generates a **Nizam**-managed **pekwm** configuration and theme using includes and assets provided by **Nizam**, without overwriting unrelated user files. Once this step is complete, restart your **X11 session**; the desktop environment should then start and function correctly out of the box.
