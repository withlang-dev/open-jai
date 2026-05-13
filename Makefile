SHELL := /bin/bash

ROOT_DIR := $(CURDIR)
OUT_DIR ?= out
BOOTSTRAP_DIR := bootstrap
BOOTSTRAP_PREFIX := $(OUT_DIR)/bootstrap
BOOTSTRAP_CACHE_DIR := $(OUT_DIR)/zig-cache/bootstrap
ZIG_GLOBAL_CACHE_DIR := $(OUT_DIR)/zig-cache/global
BOOTSTRAP_COMPILER := $(BOOTSTRAP_PREFIX)/bin/openjai
BOOTSTRAP_RUNTIME_OBJECT := $(BOOTSTRAP_PREFIX)/lib/openjai_runtime.o
BOOTSTRAP_RUNTIME_MANIFEST := $(BOOTSTRAP_PREFIX)/lib/openjai_runtime.manifest
BOOTSTRAP_RUNTIME := $(BOOTSTRAP_RUNTIME_MANIFEST)
EXAMPLES_OUT_DIR := $(OUT_DIR)/examples
SELFHOST_SRC := src/main.jai
SELFHOST_SOURCES := $(shell find src -type f -name '*.jai' | sort)
OUT_TMP_DIR := $(OUT_DIR)/tmp
REPO_SERIAL_LOCK := $(OUT_TMP_DIR)/repo-serial.lock
SEED_COMPILER ?= $(BOOTSTRAP_COMPILER)
SEED_RUNTIME ?= $(BOOTSTRAP_RUNTIME)
STAGE1_OUT_DIR := $(OUT_DIR)/stage1
STAGE2_OUT_DIR := $(OUT_DIR)/stage2
STAGE3_OUT_DIR := $(OUT_DIR)/stage3
STAGE1_COMPILER := $(STAGE1_OUT_DIR)/openjai
STAGE2_COMPILER := $(STAGE2_OUT_DIR)/openjai
STAGE3_COMPILER := $(STAGE3_OUT_DIR)/openjai
SELFHOST_OUT_DIR := $(STAGE1_OUT_DIR)
SELFHOST_COMPILER := $(STAGE1_COMPILER)

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
INSTALL_BINDIR := $(DESTDIR)$(BINDIR)

SUPPORTED_EXAMPLES := $(shell bash scripts/list_supported_examples.sh)

EXAMPLES ?= $(SUPPORTED_EXAMPLES)

# Targets share out/, so keep Make's own target scheduler serial even when
# invoked with -j. Individual tools may still parallelize internally.
.NOTPARALLEL:

.PHONY: all build seed stage0 stage1 stage2 stage3 fixpoint bootstrap runtime smoke test test-bootstrap examples selfhost-check selfhost-build selfhost-hello test-jai test-all install install-user clean \
	__build __seed __stage0 __stage1 __stage2 __stage3 __fixpoint __bootstrap __runtime __smoke __test __test-bootstrap __examples __selfhost-check __selfhost-build __test-jai __test-all __install __install-user __clean

define OPENJAI_REPO_LOCK
	@set -euo pipefail; \
	mkdir -p "$(OUT_TMP_DIR)"; \
	lock="$(REPO_SERIAL_LOCK)"; \
	owner_file="$$lock/owner"; \
	acquire_lock() { mkdir "$$lock" 2>/dev/null && { printf 'target=%s pid=%s started=%s\n' "$@" "$$$$" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$$owner_file"; return 0; }; return 1; }; \
	if acquire_lock; then \
		trap 'rm -rf "$$lock"' EXIT INT TERM HUP; \
		$(1); \
	else \
		i=0; while [ $$i -lt 10 ] && [ ! -f "$$owner_file" ]; do sleep 0.1; i=$$((i + 1)); done; \
		if [ ! -f "$$owner_file" ] && rmdir "$$lock" 2>/dev/null && acquire_lock; then \
			trap 'rm -rf "$$lock"' EXIT INT TERM HUP; \
			$(1); \
			exit 0; \
		fi; \
		if [ -f "$$owner_file" ]; then owner="$$(cat "$$owner_file")"; else owner="target=<unknown> pid=<unknown> started=<unknown>"; fi; \
		echo "error: another top-level OpenJai build/test target is already running: $$owner" >&2; \
		exit 1; \
	fi
endef

all: build

build:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __build)

seed:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __seed)

stage0:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __stage0)

stage1:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __stage1)

stage2:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __stage2)

stage3:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __stage3)

fixpoint:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __fixpoint)

bootstrap:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __bootstrap)

runtime:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __runtime)

smoke:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __smoke)

test-bootstrap:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __test-bootstrap)

examples:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __examples)

selfhost-check:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __selfhost-check)

selfhost-build:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __selfhost-build)

test-jai:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __test-jai)

test-all:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __test-all)

test:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __test)

install:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __install)

install-user:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __install-user)

clean:
	$(call OPENJAI_REPO_LOCK,$(MAKE) --no-print-directory __clean)

__build: __bootstrap

__seed: __stage0
	@echo "seed compiler: $(SEED_COMPILER)"
	@echo "seed runtime:  $(SEED_RUNTIME)"

__stage0: __bootstrap

__stage1: $(STAGE1_COMPILER)

__stage2: $(STAGE2_COMPILER)

__stage3: $(STAGE3_COMPILER)

__fixpoint: __stage2 __stage3
	@cmp "$(STAGE2_COMPILER)" "$(STAGE3_COMPILER)" && echo "FIXPOINT"

$(OUT_DIR) $(OUT_TMP_DIR) $(EXAMPLES_OUT_DIR) $(STAGE1_OUT_DIR) $(STAGE2_OUT_DIR) $(STAGE3_OUT_DIR):
	@mkdir -p "$@"

__bootstrap: | $(OUT_DIR)
	@cd "$(BOOTSTRAP_DIR)" && zig build \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"
	@test -f "$(BOOTSTRAP_RUNTIME_OBJECT)"
	@test -f "$(BOOTSTRAP_RUNTIME_MANIFEST)"

__runtime: __bootstrap
	@echo "runtime manifest: $(BOOTSTRAP_RUNTIME_MANIFEST)"
	@sed 's/^/  /' "$(BOOTSTRAP_RUNTIME_MANIFEST)"

__test-bootstrap: | $(OUT_DIR)
	@cd "$(BOOTSTRAP_DIR)" && zig build test \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

__examples: __bootstrap | $(EXAMPLES_OUT_DIR)
	@rm -rf "$(EXAMPLES_OUT_DIR)"
	@mkdir -p "$(EXAMPLES_OUT_DIR)"
	@fail=0; count=0; \
	for src in $(EXAMPLES); do \
		rel="$${src#examples/}"; \
		out="$(EXAMPLES_OUT_DIR)/$${rel%.jai}"; \
		extra_args=; \
		case "$$src" in \
			examples/30/30.14_build_inlining.jai) extra_args="-- main8" ;; \
		esac; \
		mkdir -p "$$(dirname "$$out")"; \
		echo "openjai $$src -> $$out"; \
		if ! "$(BOOTSTRAP_COMPILER)" "$$src" --check -o "$$out" --runtime "$(BOOTSTRAP_RUNTIME)" $$extra_args; then \
			fail=1; \
		fi; \
		count=$$((count + 1)); \
	done; \
	echo "compiled $$count supported example(s)"; \
	exit $$fail

__selfhost-check: __bootstrap | $(SELFHOST_OUT_DIR)
	@echo "openjai $(SELFHOST_SRC) --check"
	@"$(BOOTSTRAP_COMPILER)" "$(SELFHOST_SRC)" --check \
		-o "$(SELFHOST_COMPILER)" \
		--runtime "$(BOOTSTRAP_RUNTIME)"

__selfhost-build: __stage1

$(STAGE1_COMPILER): __bootstrap $(SELFHOST_SOURCES) | $(STAGE1_OUT_DIR)
	@echo "openjai $(SELFHOST_SRC) -> $(SELFHOST_COMPILER)"
	@rm -f "$(STAGE1_COMPILER)"
	@"$(SEED_COMPILER)" "$(SELFHOST_SRC)" \
		-o "$(STAGE1_COMPILER)" \
		--runtime "$(SEED_RUNTIME)"
	@test -x "$(STAGE1_COMPILER)" || { echo "error: stage1 compiler was not produced: $(STAGE1_COMPILER)" >&2; exit 1; }

$(STAGE2_COMPILER): __stage1 $(SELFHOST_SOURCES) | $(STAGE2_OUT_DIR)
	@echo "stage1 openjai $(SELFHOST_SRC) -> $(STAGE2_COMPILER)"
	@rm -f "$(STAGE2_COMPILER)"
	@"$(STAGE1_COMPILER)" "$(SELFHOST_SRC)" \
		-o "$(STAGE2_COMPILER)" \
		--runtime "$(SEED_RUNTIME)"
	@test -x "$(STAGE2_COMPILER)" || { echo "error: stage2 compiler was not produced: $(STAGE2_COMPILER)" >&2; exit 1; }

$(STAGE3_COMPILER): __stage2 $(SELFHOST_SOURCES) | $(STAGE3_OUT_DIR)
	@echo "stage2 openjai $(SELFHOST_SRC) -> $(STAGE3_COMPILER)"
	@rm -f "$(STAGE3_COMPILER)"
	@"$(STAGE2_COMPILER)" "$(SELFHOST_SRC)" \
		-o "$(STAGE3_COMPILER)" \
		--runtime "$(SEED_RUNTIME)"
	@test -x "$(STAGE3_COMPILER)" || { echo "error: stage3 compiler was not produced: $(STAGE3_COMPILER)" >&2; exit 1; }

selfhost-hello: selfhost-build
	@echo "selfhost-hello is blocked until the Jai port owns runtime file I/O, LLVM emission, and linking."
	@echo "Run make selfhost-check for the current source-port milestone."
	@exit 1

__smoke: __selfhost-check

__test-jai: __bootstrap
	@cd "$(BOOTSTRAP_DIR)" && zig build test-jai \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

__test-all: __test-bootstrap __examples __test-jai

__test: __test-all

__install: __bootstrap
	install -d "$(INSTALL_BINDIR)"
	install -m 0755 "$(BOOTSTRAP_COMPILER)" "$(INSTALL_BINDIR)/openjai"

__install-user:
	$(MAKE) --no-print-directory __install PREFIX="$(HOME)/.local"

__clean:
	rm -rf "$(OUT_DIR)"
