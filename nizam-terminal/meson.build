project(
  'nizam-terminal',
  'c',
  'vala',
  version: run_command('sh', '-c', 'printf %s "${NIZAM_VERSION:-0.1.0}"', check: true).stdout().strip(),
  default_options: ['warning_level=2', 'c_std=c11']
)

add_project_arguments(
  [
    '-Wno-incompatible-pointer-types',
    '-Wno-unused-parameter',
    '-Wno-unused-variable',
    '-Wno-unused-but-set-variable',
    '-Wno-discarded-qualifiers',
  ],
  language: 'c'
)

gtk_dep = dependency('gtk+-3.0', version: '>=3.24')
vte_pkg = 'vte-2.91'
vte_dep = dependency(vte_pkg, required: false)
if not vte_dep.found()
  vte_pkg = 'vte-2.91-gtk3'
  vte_dep = dependency(vte_pkg)
endif
x11_dep = dependency('x11')
gdkpix_dep = dependency('gdk-pixbuf-2.0')
cairo_dep = dependency('cairo')

subdir('src')

install_data(
  '../nizam-common/applications/nizam-terminal.desktop',
  install_dir: join_paths(get_option('datadir'), 'applications'),
)

install_subdir(
  '../nizam-common/icons',
  install_dir: get_option('datadir'),
)
