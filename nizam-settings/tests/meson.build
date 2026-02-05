gio = dependency('gio-2.0')
gtk = dependency('gtk+-3.0')
sqlite = dependency('sqlite3')
rsvg = dependency('librsvg-2.0')
cairo = dependency('cairo')

nizam_gsettings_test_src = configure_file(
  input: '../../nizam-common/src/nizam_gsettings.vala',
  output: 'nizam_gsettings.vala',
  copy: true,
)

test_gsettings = executable(
  'test-gsettings',
  [nizam_gsettings_test_src, 'test_gsettings.vala'],
  dependencies: [gio],
  c_args: [
    '-Wno-discarded-qualifiers',
    '-Wno-unused-variable',
    '-Wno-unused-but-set-variable',
  ],
  install: false,
)

test('gsettings-schema', test_gsettings)

conf = configuration_data()
conf.set_quoted('PKGDATADIR', join_paths(get_option('datadir'), 'nizam-common'))
config_vala = configure_file(
  input: '../src/config.vala.in',
  output: 'config.vala',
  configuration: conf,
)

# Vala sources outside this subdir must be copied into the builddir,
# otherwise valac will try to emit C files into non-existent paths.
db_vala = configure_file(
  input: '../src/db/db.vala',
  output: 'db.vala',
  copy: true,
)
pekwm_paths = configure_file(
  input: '../src/pekwm/PekwmPaths.vala',
  output: 'PekwmPaths.vala',
  copy: true,
)
pekwm_renderer = configure_file(
  input: '../src/pekwm/PekwmRenderer.vala',
  output: 'PekwmRenderer.vala',
  copy: true,
)
pekwm_menu = configure_file(
  input: '../src/pekwm/PekwmMenu.vala',
  output: 'PekwmMenu.vala',
  copy: true,
)
pekwm_autostart = configure_file(
  input: '../src/pekwm/PekwmAutostart.vala',
  output: 'PekwmAutostart.vala',
  copy: true,
)
pekwm_start = configure_file(
  input: '../src/pekwm/PekwmStart.vala',
  output: 'PekwmStart.vala',
  copy: true,
)
pekwm_theme_builder = configure_file(
  input: '../src/pekwm/PekwmThemeBuilder.vala',
  output: 'PekwmThemeBuilder.vala',
  copy: true,
)
pekwm_backend = configure_file(
  input: '../src/pekwm/PekwmBackend.vala',
  output: 'PekwmBackend.vala',
  copy: true,
)

test_pekwm_apply = executable(
  'test-pekwm-apply',
  [
    config_vala,
    db_vala,
    pekwm_paths,
    pekwm_renderer,
    pekwm_menu,
    pekwm_autostart,
    pekwm_start,
    pekwm_theme_builder,
    pekwm_backend,
    'test_pekwm_apply.vala',
  ],
  dependencies: [gtk, gio, sqlite, rsvg, cairo],
  c_args: [
    '-Wno-cast-function-type',
    '-Wno-deprecated-declarations',
    '-Wno-unused-variable',
    '-Wno-unused-but-set-variable',
    '-Wno-discarded-qualifiers',
    '-Wno-address',
    '-Wno-incompatible-pointer-types',
  ],
  install: false,
)

test('pekwm-apply-overlay', test_pekwm_apply)
