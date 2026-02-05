.DEFAULT_GOAL := all
PREFIX ?= /usr/local
DESTDIR ?=

# Documentation (installed so Help -> docs works in GTK apps)
DOC_INSTALL_DIR_REAL := $(PREFIX)/share/doc/nizam
DOC_INSTALL_DIR := $(DESTDIR)$(DOC_INSTALL_DIR_REAL)
DOC_FILES := README.md INSTALL.md USAGE.md CONTRIBUTING.md AUTHORS.md LICENSE.md

# Install manifest (written at install time, used by uninstall).
MANIFEST_BASE := $(DESTDIR)$(PREFIX)/share/nizam
MANIFEST_DIR := $(MANIFEST_BASE)/manifest

# Versioning: SemVer-like (MAJOR.MINOR.PATCH)
#
# Requirements (repo policy):
# - MAJOR and MINOR are Makefile constants
# - PATCH is a UNIX timestamp without seconds/ms (epoch minutes)
#
# Notes:
# - PATCH is computed as floor(epoch_seconds / 60)
# - VERSION can still be overridden explicitly:
#     make VERSION=1.2.3

MAJOR := 0
MINOR := 1

ifeq ($(origin VERSION), undefined)
PATCH := $(shell echo $$(( $$(date +%s) / 60 )) )
VERSION := $(MAJOR).$(MINOR).$(PATCH)
endif

PANEL_DIR := nizam-panel
EXPLORER_DIR := nizam-explorer
SETTINGS_DIR := nizam-settings
DOCK_DIR := nizam-dock
TERMINAL_DIR := nizam-terminal
TEXT_DIR := nizam-text

PANEL_BUILD := $(PANEL_DIR)/build
EXPLORER_BUILD := $(EXPLORER_DIR)/builddir
SETTINGS_BUILD := $(SETTINGS_DIR)/build
DOCK_BUILD := $(DOCK_DIR)/builddir
TERMINAL_BUILD := $(TERMINAL_DIR)/build
TEXT_BUILD := $(TEXT_DIR)/build

PANEL_BIN := $(PANEL_BUILD)/src/nizam-panel
DOCK_BIN := $(DOCK_BUILD)/src/nizam-dock
TERMINAL_BIN := $(TERMINAL_BUILD)/src/nizam-terminal
EXPLORER_BIN := $(EXPLORER_BUILD)/src/nizam-explorer
TEXT_BIN := $(TEXT_BUILD)/src/nizam-text
SETTINGS_BIN := $(SETTINGS_BUILD)/src/nizam-settings


.PHONY: all all-raw panel explorer settings dock terminal text clean install uninstall install-docs uninstall-docs \
	install-panel install-explorer install-settings install-dock install-terminal install-text \
	uninstall-panel uninstall-explorer uninstall-settings uninstall-dock uninstall-terminal uninstall-text \
	test test-panel test-explorer test-settings test-dock test-terminal test-text \
strip-comments perf perf-panel perf-dock perf-terminal perf-explorer perf-text perf-settings

strip-comments:
	@tools/strip_comments.sh

all: strip-comments all-raw

all-raw: panel explorer settings dock terminal text

panel: strip-comments
	@if [ ! -d "$(PANEL_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(PANEL_BUILD)" "$(PANEL_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(PANEL_BUILD)" "$(PANEL_DIR)"; fi
	meson compile -C "$(PANEL_BUILD)"

explorer: strip-comments
	@if [ ! -d "$(EXPLORER_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(EXPLORER_BUILD)" "$(EXPLORER_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(EXPLORER_BUILD)" "$(EXPLORER_DIR)"; fi
	meson compile -C "$(EXPLORER_BUILD)"

settings: strip-comments
	@if [ ! -d "$(SETTINGS_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(SETTINGS_BUILD)" "$(SETTINGS_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(SETTINGS_BUILD)" "$(SETTINGS_DIR)"; fi
	meson compile -C "$(SETTINGS_BUILD)"

dock: strip-comments
	@if [ ! -d "$(DOCK_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(DOCK_BUILD)" "$(DOCK_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(DOCK_BUILD)" "$(DOCK_DIR)"; fi
	meson compile -C "$(DOCK_BUILD)"

terminal: strip-comments
	@if [ ! -d "$(TERMINAL_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(TERMINAL_BUILD)" "$(TERMINAL_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(TERMINAL_BUILD)" "$(TERMINAL_DIR)"; fi
	meson compile -C "$(TERMINAL_BUILD)"

text: strip-comments
	@if [ ! -d "$(TEXT_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(TEXT_BUILD)" "$(TEXT_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(TEXT_BUILD)" "$(TEXT_DIR)"; fi
	meson compile -C "$(TEXT_BUILD)"

test: strip-comments test-panel test-explorer test-settings test-dock test-terminal test-text

test-panel: panel
	meson test -C "$(PANEL_BUILD)" --print-errorlogs

test-explorer: explorer
	meson test -C "$(EXPLORER_BUILD)" --print-errorlogs

test-settings: settings
	meson test -C "$(SETTINGS_BUILD)" --print-errorlogs

test-dock: dock
	meson test -C "$(DOCK_BUILD)" --print-errorlogs

test-terminal: terminal
	meson test -C "$(TERMINAL_BUILD)" --print-errorlogs

test-text: text
	meson test -C "$(TEXT_BUILD)" --print-errorlogs

perf: perf-check perf-panel perf-dock perf-terminal perf-explorer perf-text perf-settings

perf-check:
	@if [ -z "$$DISPLAY$$WAYLAND_DISPLAY" ]; then \
		if ! command -v xvfb-run >/dev/null 2>&1; then \
			echo "perf: no DISPLAY/WAYLAND_DISPLAY. Install xvfb (xvfb-run) or run in a GUI session."; \
			exit 1; \
		fi; \
	fi

perf-panel: perf-check
	@tools/perf/perf.sh nizam-panel

perf-dock: perf-check
	@tools/perf/perf.sh nizam-dock

perf-terminal: perf-check
	@tools/perf/perf.sh nizam-terminal

perf-explorer: perf-check
	@tools/perf/perf.sh nizam-explorer

perf-text: perf-check
	@tools/perf/perf.sh nizam-text

perf-settings: perf-check
	@tools/perf/perf.sh nizam-settings


install: install-panel install-explorer install-settings install-dock install-terminal install-text install-docs

install-docs:
	@mkdir -p "$(DOC_INSTALL_DIR)"
	@for f in $(DOC_FILES); do \
		if [ -f "$$f" ]; then install -m 0644 "$$f" "$(DOC_INSTALL_DIR)/$$f"; fi; \
	done
	@mkdir -p "$(MANIFEST_DIR)"
	@: > "$(MANIFEST_DIR)/docs.installlog"
	@for f in $(DOC_FILES); do \
		if [ -f "$$f" ]; then \
			if [ -n "$(DESTDIR)" ]; then echo "$(DOC_INSTALL_DIR)/$$f" >> "$(MANIFEST_DIR)/docs.installlog"; \
			else echo "$(DOC_INSTALL_DIR_REAL)/$$f" >> "$(MANIFEST_DIR)/docs.installlog"; fi; \
		fi; \
	done

install-panel: panel
	@if [ -n "$(DESTDIR)" ]; then meson install -C "$(PANEL_BUILD)" --destdir "$(DESTDIR)"; else meson install -C "$(PANEL_BUILD)"; fi
	@mkdir -p "$(MANIFEST_DIR)"
	@cp "$(PANEL_BUILD)/meson-logs/install-log.txt" "$(MANIFEST_DIR)/panel.installlog"

install-explorer: explorer
	@if [ -n "$(DESTDIR)" ]; then meson install -C "$(EXPLORER_BUILD)" --destdir "$(DESTDIR)"; else meson install -C "$(EXPLORER_BUILD)"; fi
	@mkdir -p "$(MANIFEST_DIR)"
	@cp "$(EXPLORER_BUILD)/meson-logs/install-log.txt" "$(MANIFEST_DIR)/explorer.installlog"

install-settings: settings
	@if [ -n "$(DESTDIR)" ]; then meson install -C "$(SETTINGS_BUILD)" --destdir "$(DESTDIR)"; else meson install -C "$(SETTINGS_BUILD)"; fi
	@mkdir -p "$(MANIFEST_DIR)"
	@cp "$(SETTINGS_BUILD)/meson-logs/install-log.txt" "$(MANIFEST_DIR)/settings.installlog"

install-dock: dock
	@if [ -n "$(DESTDIR)" ]; then meson install -C "$(DOCK_BUILD)" --destdir "$(DESTDIR)"; else meson install -C "$(DOCK_BUILD)"; fi
	@mkdir -p "$(MANIFEST_DIR)"
	@cp "$(DOCK_BUILD)/meson-logs/install-log.txt" "$(MANIFEST_DIR)/dock.installlog"

install-terminal: terminal
	@if [ -n "$(DESTDIR)" ]; then meson install -C "$(TERMINAL_BUILD)" --destdir "$(DESTDIR)"; else meson install -C "$(TERMINAL_BUILD)"; fi
	@mkdir -p "$(MANIFEST_DIR)"
	@cp "$(TERMINAL_BUILD)/meson-logs/install-log.txt" "$(MANIFEST_DIR)/terminal.installlog"

install-text:
	@if [ -d "$(TEXT_DIR)" ]; then \
		if [ ! -d "$(TEXT_BUILD)" ]; then NIZAM_VERSION="$(VERSION)" meson setup --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(TEXT_BUILD)" "$(TEXT_DIR)"; else NIZAM_VERSION="$(VERSION)" meson setup --reconfigure --prefix "$(PREFIX)" -Dapp_version="$(VERSION)" "$(TEXT_BUILD)" "$(TEXT_DIR)"; fi; \
		meson compile -C "$(TEXT_BUILD)"; \
		if [ -n "$(DESTDIR)" ]; then meson install -C "$(TEXT_BUILD)" --destdir "$(DESTDIR)"; else meson install -C "$(TEXT_BUILD)"; fi; \
		mkdir -p "$(MANIFEST_DIR)"; \
		cp "$(TEXT_BUILD)/meson-logs/install-log.txt" "$(MANIFEST_DIR)/text.installlog"; \
	else \
		echo "Skipping text: $(TEXT_DIR) not present"; \
	fi

uninstall:
	@python3 -c 'import glob,os,sys; code="destdir,md,mb=sys.argv[1:4]\n" \
	"if not os.path.isdir(md):\n  raise SystemExit(2)\n" \
	"mfs=sorted(glob.glob(os.path.join(md,\"*.installlog\")))\n" \
	"if not mfs:\n  raise SystemExit(2)\n" \
	"paths=set()\n" \
	"for mf in mfs:\n" \
	"  try:\n" \
	"    with open(mf,\"r\",encoding=\"utf-8\",errors=\"replace\") as f:\n" \
	"      for line in f:\n" \
	"        line=line.strip()\n" \
	"        if not line or line.startswith(\"#\"): continue\n" \
	"        paths.add(line)\n" \
	"  except FileNotFoundError:\n    continue\n" \
	"files=[p for p in paths if os.path.isabs(p)]\n" \
	"removed_files=0\n" \
	"removed_dirs=0\n" \
	"for p in sorted(files, reverse=True):\n" \
	"  t=p\n" \
	"  try:\n    st=os.lstat(t)\n  except FileNotFoundError:\n    continue\n" \
	"  if os.path.isfile(t) or os.path.islink(t):\n" \
	"    try:\n      os.remove(t); removed_files+=1\n    except FileNotFoundError:\n      pass\n" \
	"# Prova a rimuovere directory elencate (solo se vuote)\n" \
	"for p in sorted(files, reverse=True):\n" \
	"  t=p\n" \
	"  try:\n" \
	"    if os.path.isdir(t) and not os.listdir(t):\n      os.rmdir(t); removed_dirs+=1\n" \
	"  except OSError:\n    pass\n" \
	"for mf in mfs:\n" \
	"  try:\n    os.remove(mf)\n  except FileNotFoundError:\n    pass\n" \
	"for d in (md, mb):\n" \
	"  try:\n" \
	"    if os.path.isdir(d) and not os.listdir(d):\n      os.rmdir(d)\n" \
	"  except OSError:\n    pass\n" \
	"print(f\"Uninstalled {removed_files} files and {removed_dirs} empty dirs (manifest mode)\")\n"; exec(code)' "$(DESTDIR)" "$(MANIFEST_DIR)" "$(MANIFEST_BASE)"; rc=$$?; \
	if [ $$rc -eq 2 ]; then \
		$(MAKE) uninstall-docs uninstall-panel uninstall-explorer uninstall-settings uninstall-dock uninstall-terminal uninstall-text; \
	else \
		exit $$rc; \
	fi

uninstall-docs:
	@for f in $(DOC_FILES); do \
		rm -f "$(DESTDIR)$(DOC_INSTALL_DIR_REAL)/$$f"; \
	done
	@rmdir "$(DESTDIR)$(DOC_INSTALL_DIR_REAL)" 2>/dev/null || true

define MESON_UNINSTALL
	@python3 -c 'import glob,json,os,subprocess,sys; code="build,destdir=sys.argv[1:3]\n" \
	"log=os.path.join(build,\"meson-logs\",\"install-log.txt\")\n" \
	"paths=[]\n" \
	"if os.path.isfile(log):\n" \
	"  with open(log,\"r\",encoding=\"utf-8\",errors=\"replace\") as f:\n" \
	"    for line in f:\n" \
	"      line=line.strip()\n" \
	"      if not line or line.startswith(\"#\"): continue\n" \
	"      paths.append(line)\n" \
	"else:\n" \
	"  installed=subprocess.check_output([\"meson\",\"introspect\",\"--installed\",build], text=True)\n" \
	"  m=json.loads(installed)\n" \
	"  paths=list(m.values()) if isinstance(m,dict) else []\n" \
	"removed_files=0\n" \
	"removed_dirs=0\n" \
	"for p in sorted([p for p in paths if os.path.isabs(p)], reverse=True):\n" \
	"  t=p if os.path.isfile(log) else (os.path.join(destdir, p.lstrip(os.sep)) if destdir else p)\n" \
	"  try:\n    os.lstat(t)\n  except FileNotFoundError:\n    continue\n" \
	"  if os.path.isfile(t) or os.path.islink(t):\n" \
	"    try:\n      os.remove(t); removed_files+=1\n    except FileNotFoundError:\n      pass\n" \
	"for p in sorted([p for p in paths if os.path.isabs(p)], reverse=True):\n" \
	"  t=p if os.path.isfile(log) else (os.path.join(destdir, p.lstrip(os.sep)) if destdir else p)\n" \
	"  try:\n" \
	"    if os.path.isdir(t) and not os.listdir(t):\n      os.rmdir(t); removed_dirs+=1\n" \
	"  except OSError:\n    pass\n" \
	"print(f\"Uninstalled {removed_files} files and {removed_dirs} empty dirs from {build}\")\n"; exec(code)' "$(1)" "$(DESTDIR)"
endef

uninstall-panel:
	@if [ ! -d "$(PANEL_BUILD)" ]; then echo "Missing build dir: $(PANEL_BUILD)"; exit 0; fi
	$(call MESON_UNINSTALL,$(PANEL_BUILD))

uninstall-explorer:
	@if [ ! -d "$(EXPLORER_BUILD)" ]; then echo "Missing build dir: $(EXPLORER_BUILD)"; exit 0; fi
	$(call MESON_UNINSTALL,$(EXPLORER_BUILD))

uninstall-settings:
	@if [ ! -d "$(SETTINGS_BUILD)" ]; then echo "Missing build dir: $(SETTINGS_BUILD)"; exit 0; fi
	$(call MESON_UNINSTALL,$(SETTINGS_BUILD))

uninstall-dock:
	@if [ ! -d "$(DOCK_BUILD)" ]; then echo "Missing build dir: $(DOCK_BUILD)"; exit 0; fi
	$(call MESON_UNINSTALL,$(DOCK_BUILD))

uninstall-terminal:
	@if [ ! -d "$(TERMINAL_BUILD)" ]; then echo "Missing build dir: $(TERMINAL_BUILD)"; exit 0; fi
	$(call MESON_UNINSTALL,$(TERMINAL_BUILD))

uninstall-text:
	@if [ ! -d "$(TEXT_DIR)" ] || [ ! -d "$(TEXT_BUILD)" ]; then echo "Skipping text: $(TEXT_DIR) not present"; exit 0; fi
	$(call MESON_UNINSTALL,$(TEXT_BUILD))

clean:
	@if [ -d "$(PANEL_BUILD)" ]; then meson compile -C "$(PANEL_BUILD)" --clean; fi
	@if [ -d "$(EXPLORER_BUILD)" ]; then meson compile -C "$(EXPLORER_BUILD)" --clean; fi
	@if [ -d "$(SETTINGS_BUILD)" ]; then meson compile -C "$(SETTINGS_BUILD)" --clean; fi
	@if [ -d "$(DOCK_BUILD)" ]; then meson compile -C "$(DOCK_BUILD)" --clean; fi
	@if [ -d "$(TERMINAL_BUILD)" ]; then meson compile -C "$(TERMINAL_BUILD)" --clean; fi
	@if [ -d "$(TEXT_BUILD)" ]; then meson compile -C "$(TEXT_BUILD)" --clean; fi
