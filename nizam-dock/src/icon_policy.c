#include "icon_policy.h"

#include <ctype.h>
#include <string.h>

static size_t trim_left(const char *s) {
  size_t i = 0;
  while (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r') {
    i++;
  }
  return i;
}

static size_t trim_right(const char *s, size_t len) {
  while (len > 0) {
    char c = s[len - 1];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      len--;
      continue;
    }
    break;
  }
  return len;
}

void nizam_dock_icon_normalize(const char *in, char *out, size_t out_len) {
  if (!out || out_len == 0) {
    return;
  }
  out[0] = '\0';
  if (!in || !*in) {
    return;
  }

  size_t len = strlen(in);
  size_t start = trim_left(in);
  len = trim_right(in, len);
  if (start >= len) {
    return;
  }

  const char *s = in + start;
  size_t n = len - start;

  const char *slash = strrchr(s, '/');
  if (slash && (size_t)(slash - s) + 1 < n) {
    s = slash + 1;
    n = len - (size_t)(s - in);
  }

  const char *dot = NULL;
  for (size_t i = 0; i < n; ++i) {
    if (s[i] == '.') {
      dot = s + i;
    }
  }
  if (dot && dot > s) {
    n = (size_t)(dot - s);
  }

  size_t w = 0;
  for (size_t i = 0; i < n && w + 1 < out_len; ++i) {
    unsigned char c = (unsigned char)s[i];
    out[w++] = (char)tolower(c);
  }
  out[w] = '\0';
}
