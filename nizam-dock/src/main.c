#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include "cairo_draw.h"
#include "config.h"
#include "sni.h"
#include "xcb_app.h"

static void handle_sighup(int signo) {
  (void)signo;
  nizam_dock_request_config_reload();
}

static void build_dock_ipc_socket_path(char *out, size_t out_len) {
  if (!out || out_len == 0) {
    return;
  }
  out[0] = '\0';

  const char *runtime = getenv("XDG_RUNTIME_DIR");
  if (runtime && *runtime) {
    snprintf(out, out_len, "%s/%s", runtime, "nizam-dock.sock");
    return;
  }

  const char *user = getenv("USER");
  if (!user || !*user) {
    user = "user";
  }
  snprintf(out, out_len, "/tmp/nizam-dock-%s.sock", user);
}

static int socket_set_cloexec(int fd) {
  if (fd < 0) {
    return 0;
  }
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) {
    return 0;
  }
  if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) != 0) {
    return 0;
  }
  return 1;
}

static int is_peer_nizam_dock(int fd) {
  struct ucred cred;
  socklen_t len = sizeof(cred);
  if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) != 0) {
    return 0;
  }
  if (cred.pid <= 1) {
    return 0;
  }

  char path[64];
  snprintf(path, sizeof(path), "/proc/%d/comm", cred.pid);
  FILE *fp = fopen(path, "r");
  if (!fp) {
    return 0;
  }
  char comm[64];
  comm[0] = '\0';
  if (!fgets(comm, sizeof(comm), fp)) {
    fclose(fp);
    return 0;
  }
  fclose(fp);
  size_t n = strlen(comm);
  while (n > 0 && (comm[n - 1] == '\n' || comm[n - 1] == '\r')) {
    comm[n - 1] = '\0';
    n--;
  }
  return strcmp(comm, "nizam-dock") == 0;
}

static int dock_ipc_try_send_reload(void) {
  char path[256];
  build_dock_ipc_socket_path(path, sizeof(path));
  if (!path[0]) {
    return 0;
  }

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return 0;
  }
  socket_set_cloexec(fd);

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;

  size_t path_len = strnlen(path, sizeof(path));
  if (path_len == 0 || path_len >= sizeof(addr.sun_path)) {
    close(fd);
    return 0;
  }
  memcpy(addr.sun_path, path, path_len + 1);

  socklen_t addr_len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_len + 1);
  if (connect(fd, (struct sockaddr *)&addr, addr_len) != 0) {
    close(fd);
    return 0;
  }

  if (!is_peer_nizam_dock(fd)) {
    close(fd);
    return 0;
  }

  const char *msg = "reload\n";
  (void)write(fd, msg, strlen(msg));
  close(fd);
  return 1;
}

static void *dock_ipc_thread_main(void *arg) {
  (void)arg;

  char path[256];
  build_dock_ipc_socket_path(path, sizeof(path));
  if (!path[0]) {
    return NULL;
  }

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return NULL;
  }
  socket_set_cloexec(fd);

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;

  size_t path_len = strnlen(path, sizeof(path));
  if (path_len == 0 || path_len >= sizeof(addr.sun_path)) {
    close(fd);
    return NULL;
  }
  memcpy(addr.sun_path, path, path_len + 1);

  
  unlink(path);

  socklen_t addr_len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_len + 1);
  if (bind(fd, (struct sockaddr *)&addr, addr_len) != 0) {
    close(fd);
    return NULL;
  }

  if (listen(fd, 4) != 0) {
    close(fd);
    return NULL;
  }

  for (;;) {
    int cfd = accept(fd, NULL, NULL);
    if (cfd < 0) {
      if (errno == EINTR) {
        continue;
      }
      
      continue;
    }
    socket_set_cloexec(cfd);

    char buf[64];
    ssize_t n = read(cfd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      if (strncmp(buf, "reload", 6) == 0) {
        nizam_dock_request_config_reload();
      }
    }
    close(cfd);
  }

  
  
  
  
}

static void dock_ipc_start(void) {
  pthread_t thr;
  if (pthread_create(&thr, NULL, dock_ipc_thread_main, NULL) == 0) {
    pthread_detach(thr);
  }
}

static int nizam_dock_debug_enabled(void) {
  const char *env = getenv("NIZAM_DOCK_DEBUG");
  return env && *env && strcmp(env, "0") != 0;
}

static void debug_dump_cfg(const struct nizam_dock_config *cfg) {
  if (!cfg || !nizam_dock_debug_enabled()) {
    return;
  }
  fprintf(stderr,
          "nizam-dock: cfg icon_size=%d padding=%d spacing=%d bottom_margin=%d hide_delay_ms=%d handle_px=%d bg_dim=%.2f\n",
          cfg->icon_size, cfg->padding, cfg->spacing, cfg->bottom_margin, cfg->hide_delay_ms, cfg->handle_px, cfg->bg_dim);
}

int main(int argc, char **argv) {
  
  
  if (dock_ipc_try_send_reload()) {
    return 0;
  }

  dock_ipc_start();

  
  
  (void)argc;
  (void)argv;

  struct nizam_dock_config cfg;
  nizam_dock_config_init_defaults(&cfg);

  
  (void)nizam_dock_config_load_launchers(&cfg);
  debug_dump_cfg(&cfg);

  if (!cfg.enabled) {
    if (nizam_dock_debug_enabled()) {
      fprintf(stderr, "nizam-dock: disabled via config, exiting\n");
    }
    nizam_dock_config_free(&cfg);
    return 0;
  }

  struct nizam_dock_app app;
  if (nizam_dock_xcb_init(&app, &cfg) != 0) {
    fprintf(stderr, "nizam-dock: failed to init XCB\n");
    nizam_dock_config_free(&cfg);
    return 1;
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: xcb init ok\n");
  }

  if (nizam_dock_sni_init(&app) != 0) {
    fprintf(stderr, "nizam-dock: sni init failed (no systray)\n");
  }

  if (nizam_dock_icons_init(&app, &cfg) != 0) {
    fprintf(stderr, "nizam-dock: icon cache init failed, using placeholders\n");
  }
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: icons init ok\n");
  }
  nizam_dock_sysinfo_init(&app);
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: sysinfo init ok\n");
  }
  nizam_dock_xcb_apply_geometry(&app, &cfg);

  signal(SIGHUP, handle_sighup);

  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: entering event loop\n");
  }
  nizam_dock_xcb_event_loop(&app, &cfg);
  if (nizam_dock_debug_enabled()) {
    fprintf(stderr, "nizam-dock: event loop exit\n");
  }

  nizam_dock_icons_free(&app);
  nizam_dock_sni_cleanup(&app);
  nizam_dock_xcb_cleanup(&app);
  nizam_dock_config_free(&cfg);
  return 0;
}
