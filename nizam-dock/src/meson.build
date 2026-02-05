inc = include_directories('../include')

xcb = dependency('xcb')
xcb_randr = dependency('xcb-randr')
cairo = dependency('cairo')
gdkpixbuf = dependency('gdk-pixbuf-2.0')
dbus = dependency('dbus-1')
sqlite = dependency('sqlite3')
threads = dependency('threads')

executable(
  'nizam-dock',
  [
    'main.c',
    'config.c',
    'xcb_app.c',
    'cairo_draw.c',
    'sni.c',
    'icon_policy.c',
    'icon_surface_cache.c',
  ],
  include_directories: inc,
  dependencies: [xcb, xcb_randr, cairo, gdkpixbuf, dbus, sqlite, threads],
  install: true,
)
