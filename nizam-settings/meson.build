project(
	'nizam-settings',
	['vala', 'c'],
	version: run_command('sh', '-c', 'printf %s "${NIZAM_VERSION:-0.1.0}"', check: true).stdout().strip(),
	meson_version: '>= 0.57'
)

gnome = import('gnome')

subdir('src')

subdir('tests')

install_data(
	'../nizam-common/applications/nizam-settings.desktop',
	install_dir: join_paths(get_option('datadir'), 'applications'),
)

ui_install_dir = join_paths(get_option('datadir'), 'nizam-settings', 'ui', 'ui')

# Install only UI assets that are actually used by the GTK3 app.
# NOTE: panel.ui / dock.ui are GTK4-era builder files and are not referenced by current code.
install_data(
	'data/ui/gtk-logo.png',
	'data/ui/pekwm-logo.png',
	install_dir: ui_install_dir,
)

install_data(
	'data/desktop/default.svg',
	install_dir: join_paths(get_option('datadir'), 'nizam-settings', 'desktop'),
)
install_subdir('data/ui/pekwm/theme', install_dir: join_paths(ui_install_dir, 'pekwm'))
# App icon (hicolor theme)
install_subdir(
	'../nizam-common/icons',
	install_dir: get_option('datadir'),
)

# Nizam settings schema (separate from GTK global settings).
install_data(
	'../nizam-common/data/schemas/com.nizam.desktop.gschema.xml',
	install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas'),
)

gnome.post_install(
	glib_compile_schemas: true,
)
