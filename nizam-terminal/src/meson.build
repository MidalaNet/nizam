vala_args = [
  '--target-glib=2.56',
  '--vapidir', meson.current_source_dir(),
  '--vapidir', meson.current_build_dir(),
  '--pkg', 'gtk+-3.0',
  '--pkg', vte_pkg,
  '--pkg', 'gdk-pixbuf-2.0',
  '--pkg', 'gio-2.0',
  '--pkg', 'glib-2.0'
]

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
vala_args += ['--define=HAVE_GFM_DOCS', '--pkg', webkit_pkg]

version_conf = configuration_data()
version_conf.set('APP_VERSION', get_option('app_version'))
version_file = configure_file(
  input: 'version.vala.in',
  output: 'version.vala',
  configuration: version_conf,
)

c_sources = [
  'x11_rootpixmap.c'
]

vala_sources = [
  configure_file(
    input: '../../nizam-common/gtk3/NizamAppWindow.vala',
    output: 'NizamAppWindow.vala',
    copy: true,
  ),
  configure_file(
    input: '../../nizam-common/gtk3/NizamAbout.vala',
    output: 'NizamAbout.vala',
    copy: true,
  ),
  'main.vala',
  'terminal_window.vala',
  'terminal_tab.vala',
  version_file,
  'x11_rootpixmap.vapi'
]

executable('nizam-terminal',
  vala_sources + c_sources,
  dependencies: [gtk_dep, vte_dep, x11_dep, gdkpix_dep, cairo_dep, webkit_dep] + cmark_gfm_link_deps,
  vala_args: vala_args,
  c_args: [
    '-Wno-cast-function-type',
    '-Wno-incompatible-pointer-types',
    '-Wno-unused-parameter',
    '-Wno-unused-variable',
    '-Wno-unused-but-set-variable',
    '-Wno-discarded-qualifiers',
  ],
  install: true
)

install_data(
  '../../nizam-common/gtk3/nizam-gtk3.css',
  install_dir: join_paths(get_option('datadir'), 'nizam-common', 'gtk3'),
)
