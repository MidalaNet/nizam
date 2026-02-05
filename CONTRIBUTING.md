# Contributing

**Nizam** accepts focused, well-scoped contributions that improve correctness, performance, or user experience without expanding the project’s scope or increasing long-term maintenance cost. Changes should be intentional, minimal, and easy to reason about. If a change alters behavior that users can observe, the corresponding documentation must be updated in the same change set.

The repository is organized by component. **X11 components** live under `nizam-panel/` and `nizam-dock/`. **GTK3 applications** live under `nizam-explorer/`, `nizam-terminal/`, `nizam-text/`, and `nizam-settings/`. Shared code, themes, and assets are kept in `nizam-common/`. Each component is expected to remain independently buildable and to have a clearly defined runtime role.

All **GTK3 applications** must use the shared application shell provided by `nizam-common/gtk3/NizamAppWindow.vala`. The shared stylesheet is `nizam-common/gtk3/nizam-gtk3.css` and must remain theme-driven. Hard-coded colors, widget-specific styling, or ad-hoc CSS overrides are not accepted. Application windows are expected to provide a menubar, a flat toolbar, and a status bar through the shell’s API, and to prefer fixed, predictable layouts over dynamic or auto-sizing constructs in order to keep rendering consistent across applications.

**X11 components** follow an **Adwaita Dark**–aligned palette and rendering model. Gradients, compositing effects, and compositor dependencies are explicitly out of scope. Colors must be referenced through semantic roles rather than literals. The goal is visual coherence with **GTK3** applications.

Performance is treated as a first-class design constraint. Caches must always be bounded. **Cairo** surfaces must have single, explicit ownership and a clearly defined destruction point. Redraws must be event-driven, coalesced, and never triggered by polling or periodic timers at idle. Event loops must block correctly and must not spin. Any change that affects rendering, caching, or event handling is expected to preserve these properties.

The project includes performance guardrails that are enforced through `make perf`. This target performs steady-state RSS and CPU measurements and runs Valgrind checks to detect leaks, invalid memory access, and regressions in resource usage. Functional correctness is covered separately by `make test`. Contributors modifying performance-sensitive code must validate their changes with `make perf` before submitting them.

Development builds should be done locally using `make`, with tests run via `make test`. Performance-sensitive changes should always be validated with `make perf`. Contributions should be kept small and verifiable, defaults should remain stable, and new configuration surfaces should be avoided unless they are strictly necessary and can be supported without compromising determinism.

**Nizam** deliberately favors restraint over flexibility. Contributions are evaluated not only on what they add, but on what they preserve: predictable behavior, bounded resource usage, and a desktop environment that remains understandable over long-running sessions.
