project(
	'nizam-explorer',
	['vala', 'c'],
	version: run_command('sh', '-c', 'printf %s "${NIZAM_VERSION:-0.1.0}"', check: true).stdout().strip(),
	meson_version: '>= 0.56'
)

subdir('src')

install_data(
	'../nizam-common/applications/nizam-explorer.desktop',
	install_dir: join_paths(get_option('datadir'), 'applications'),
)

install_subdir(
	'../nizam-common/icons',
	install_dir: get_option('datadir'),
)
