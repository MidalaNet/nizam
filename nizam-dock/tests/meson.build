inc = include_directories('../include')

cairo = dependency('cairo')
gdkpixbuf = dependency('gdk-pixbuf-2.0')
glib = dependency('glib-2.0')

test_icon_cache = executable(
  'test-icon-cache',
  [
    'test_icon_cache.c',
    '../src/icon_policy.c',
    '../src/icon_surface_cache.c',
  ],
  include_directories: inc,
  dependencies: [cairo, gdkpixbuf, glib],
)

test('dock-icon-cache', test_icon_cache)
