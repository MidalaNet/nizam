gtk = dependency('gtk+-3.0')
gio_unix = dependency('gio-unix-2.0')
sqlite = dependency('sqlite3')
rsvg = dependency('librsvg-2.0')
cairo = dependency('cairo')

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

version_conf = configuration_data()
version_conf.set('APP_VERSION', get_option('app_version'))
version_file = configure_file(
  input: 'version.vala.in',
  output: 'version.vala',
  configuration: version_conf,
)

conf = configuration_data()
# Absolute datadir (e.g. /usr/local/share). Meson `datadir` is typically
# relative (e.g. 'share'), so join it with prefix.
conf.set_quoted('PKGDATADIR', join_paths(get_option('prefix'), get_option('datadir')))
config_vala = configure_file(
  input: 'config.vala.in',
  output: 'config.vala',
  configuration: conf,
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

libcmark_gfm_vapi = configure_file(
  input: '../../nizam-common/gtk3/libcmark-gfm.vapi',
  output: 'libcmark-gfm.vapi',
  copy: true,
)

nizam_gsettings = configure_file(
  input: '../../nizam-common/src/nizam_gsettings.vala',
  output: 'nizam_gsettings.vala',
  copy: true,
)

executable(
  'nizam-settings',
  [
    nizam_app_window,
    nizam_about,
    nizam_gsettings,
    'main.vala',
    'db/db.vala',
    'db/migrations.vala',
    'db/settings_store.vala',
    'gtk/gtk_dialog_helpers.c',
    'gtk/GtkThemeScanner.vala',
    'applications/DesktopEntryModel.vala',
    'applications/DesktopEntryIO.vala',
    'applications/DesktopEntryUtils.vala',
    'applications/DesktopEntryScanner.vala',
    'applications/DesktopEntryImporter.vala',
    'applications/DesktopEntryStore.vala',
    'pekwm/PekwmPaths.vala',
    'pekwm/PekwmRenderer.vala',
    'pekwm/PekwmApplier.vala',
    'pekwm/PekwmBackend.vala',
    'pekwm/PekwmThemeBuilder.vala',
    'pekwm/PekwmStart.vala',
    'pekwm/PekwmAutostart.vala',
    'pekwm/PekwmMenu.vala',
    'pages/GtkPage.vala',
    'applications/ApplicationsPage.vala',
    'ui/window.vala',
    'ui/page_pekwm.vala',
    config_vala,
    version_file,
  ],
  dependencies: [gtk, gio_unix, sqlite, rsvg, cairo, webkit_dep] + cmark_gfm_link_deps,
  vala_args: ['--vapidir', meson.current_build_dir(), '--define=HAVE_GFM_DOCS', '--pkg', webkit_pkg],
  c_args: [
    '-Wno-cast-function-type',
    '-Wno-deprecated-declarations',
    '-Wno-unused-variable',
    '-Wno-unused-but-set-variable',
    '-Wno-discarded-qualifiers',
    '-Wno-address',
    '-Wno-incompatible-pointer-types',
  ],
  install: true,
)

install_data(
  '../../nizam-common/gtk3/nizam-gtk3.css',
  install_dir: join_paths(get_option('datadir'), 'nizam-common', 'gtk3'),
)
