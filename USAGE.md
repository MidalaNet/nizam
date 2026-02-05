# Usage

This guide assumes that **Nizam** is already installed and that you are running an **X11 session**. **Nizam** is designed to run under **pekwm** and relies on it for window management and **EWMH** integration. Start your session with **pekwm**, then run `nizam-settings` once to generate and apply the **Nizam-managed pekwm configuration**. This initial step is required to deploy the theme, start script, and includes used by **Nizam**.

The core user-facing binaries provided by **Nizam** are `nizam-panel`, `nizam-dock`, `nizam-explorer`, `nizam-terminal`, `nizam-text`, and `nizam-settings`.

`nizam-settings` acts as the control center for the entire desktop environment. It is responsible for managing **GTK** appearance through **GSettings**, maintaining the **Applications** database used by both the panel menu and the dock, and generating the **pekwm** configuration and theme pipeline. On the **GTK** page, clicking `Apply` enforces a stable baseline consisting of the **Adwaita theme**, **Adwaita icons**, and a **Sans 10** font. This is intentional and ensures that all **GTK3** applications remain visually consistent. On the **Window Manager** page, clicking `Apply` deploys the **pekwm** theme, configuration includes, and start script.

Application metadata is stored in an **SQLite** database located at `$XDG_CONFIG_HOME/nizam/nizam.db`, which typically resolves to `~/.config/nizam/nizam.db`. Both the panel menu and the dock launcher list are driven entirely by this database. Changes made in `nizam-settings`, such as toggling application visibility or pinning an application to the dock, are reflected immediately without requiring a session restart. The database acts as the single source of truth for what appears in the UI.

Panel and dock behavior is intentionally conservative and largely non-configurable at runtime. Geometry, layout, and rendering behavior are fixed by design in order to keep resource usage predictable and eliminate background polling or state drift. Control over what appears in the panel menu or dock is expected to be done through the **Applications** database rather than through layout or theming tweaks.
