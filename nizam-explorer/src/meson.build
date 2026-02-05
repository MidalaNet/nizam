gtk = dependency('gtk+-3.0', version: '>= 3.22')
gio = dependency('gio-2.0')
sqlite = dependency('sqlite3')

pkgconfig = find_program('pkg-config', required: true)

webkit_pkg = ''
if run_command(pkgconfig, '--exists', 'webkit2gtk-4.1', check: false).returncode() == 0
  webkit_pkg = 'webkit2gtk-4.1'
elif run_command(pkgconfig, '--exists', 'webkit2gtk-4.0', check: false).returncode() == 0
  webkit_pkg = 'webkit2gtk-4.0'
else
  error('Required dependency not found: webkit2gtk-4.1 or webkit2gtk-4.0')
endif

webkit_dep = dependency(webkit_pkg, required: true, method: 'pkg-config')
cmark_gfm_dep = dependency('libcmark-gfm', required: true, method: 'pkg-config')

cc = meson.get_compiler('c')
cmark_gfm_link_deps = [cmark_gfm_dep]
if not cc.has_function('cmark_gfm_core_extensions_ensure_registered', dependencies: cmark_gfm_dep)
  cmark_gfm_extensions = cc.find_library('cmark-gfm-extensions', required: false)
  if not cmark_gfm_extensions.found()
    error('Required dependency not found: cmark-gfm extensions (missing cmark_gfm_core_extensions_ensure_registered)')
  endif
  cmark_gfm_link_deps += [cmark_gfm_extensions]
endif

libcmark_gfm_vapi = configure_file(
  input: '../../nizam-common/gtk3/libcmark-gfm.vapi',
  output: 'libcmark-gfm.vapi',
  copy: true,
)

version_conf = configuration_data()
version_conf.set('APP_VERSION', get_option('app_version'))
version_file = configure_file(
  input: 'version.vala.in',
  output: 'version.vala',
  configuration: version_conf,
)

nizam_app_window = configure_file(
  input: '../../nizam-common/gtk3/NizamAppWindow.vala',
  output: 'NizamAppWindow.vala',
  copy: true,
)

nizam_about = configure_file(
  input: '../../nizam-common/gtk3/NizamAbout.vala',
  output: 'NizamAbout.vala',
  copy: true,
)

a_source_files = [
  nizam_app_window,
  nizam_about,
  'app.vala',
  'window.vala',
  'model.vala',
  'history.vala',
  'config_db.vala',
  'glist_utils.c',
  version_file,
]

executable(
  'nizam-explorer',
  a_source_files,
  dependencies: [gtk, gio, sqlite, webkit_dep] + cmark_gfm_link_deps,
  vala_args: ['--vapidir', meson.current_build_dir(), '--pkg', 'posix', '--define=HAVE_GFM_DOCS', '--pkg', webkit_pkg],
  c_args: [
    # Vala-generated C can trigger benign warnings on newer GCC.
    '-Wno-cast-function-type',
    '-Wno-unused-variable',
    '-Wno-unused-but-set-variable',
    '-Wno-discarded-qualifiers',
    '-Wno-address',
    '-Wno-incompatible-pointer-types',
    '-Wno-unused-function',
  ],
  install: true,
)

install_data(
  '../../nizam-common/gtk3/nizam-gtk3.css',
  install_dir: join_paths(get_option('datadir'), 'nizam-common', 'gtk3'),
)

test_history_vala = configure_file(
  input: '../tests/test_history.vala',
  output: 'test_history.vala',
  copy: true,
)

test_history = executable(
  'test-history',
  [
    'history.vala',
    test_history_vala,
  ],
  dependencies: [gio],
  c_args: [
    '-Wno-unused-but-set-variable',
    '-Wno-unused-variable',
    '-Wno-discarded-qualifiers',
  ],
)

test('explorer-history', test_history, protocol: 'tap')
