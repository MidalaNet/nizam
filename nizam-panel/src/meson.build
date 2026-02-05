x11 = dependency('x11')
xrandr = dependency('xrandr')
cairo = dependency('cairo')
pango = dependency('pango')
pangocairo = dependency('pangocairo')
sqlite = dependency('sqlite3')

add_project_arguments('-DNIZAM_PANEL_VERSION="' + get_option('app_version') + '"', language: 'c')

librsvg = dependency('librsvg-2.0', required: false)
if librsvg.found()
  add_project_arguments('-DNIZAM_HAVE_LIBRSVG=1', language: 'c')
endif

gdkpixbuf = dependency('gdk-pixbuf-2.0', required: false)
if gdkpixbuf.found()
  add_project_arguments('-DNIZAM_HAVE_GDKPIXBUF=1', language: 'c')
endif

executable(
  'nizam-panel',
  [
    'main.c',
    'menu.c',
    'tasklist.c',
    'clock.c',
  ],
  dependencies: [x11, xrandr, cairo, pango, pangocairo, sqlite, librsvg, gdkpixbuf],
  install: true,
)
