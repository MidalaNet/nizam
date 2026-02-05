project(
	'nizam-dock',
	['c'],
	version: get_option('app_version'),
	meson_version: '>= 0.56'
)

subdir('src')

install_data(
	'../nizam-common/applications/nizam-dock.desktop',
	install_dir: join_paths(get_option('datadir'), 'applications'),
)

install_subdir(
	'../nizam-common/icons',
	install_dir: get_option('datadir'),
)

subdir('tests')
