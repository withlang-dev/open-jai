SHELL := /bin/bash

OUT_DIR := out
BOOTSTRAP_DIR := bootstrap
BOOTSTRAP_PREFIX := $(OUT_DIR)/bootstrap
BOOTSTRAP_CACHE_DIR := $(OUT_DIR)/zig-cache/bootstrap
ZIG_GLOBAL_CACHE_DIR := $(OUT_DIR)/zig-cache/global
BOOTSTRAP_COMPILER := $(BOOTSTRAP_PREFIX)/bin/openjai
BOOTSTRAP_RUNTIME := $(BOOTSTRAP_PREFIX)/lib/openjai_runtime.o
EXAMPLES_OUT_DIR := $(OUT_DIR)/examples
SELFHOST_SRC := src/main.jai
SELFHOST_OUT_DIR := $(OUT_DIR)/selfhost
SELFHOST_COMPILER := $(SELFHOST_OUT_DIR)/openjai

SUPPORTED_EXAMPLES := $(shell find examples -type f -name '*.jai' | sort)

EXAMPLES ?= $(SUPPORTED_EXAMPLES)

.PHONY: bootstrap test test-bootstrap examples selfhost-check selfhost-build selfhost-hello test-jai test-all clean

bootstrap:
	@mkdir -p "$(OUT_DIR)"
	@cd "$(BOOTSTRAP_DIR)" && zig build \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

test-bootstrap:
	@mkdir -p "$(OUT_DIR)"
	@cd "$(BOOTSTRAP_DIR)" && zig build test \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

examples: bootstrap
	@rm -rf "$(EXAMPLES_OUT_DIR)"
	@mkdir -p "$(EXAMPLES_OUT_DIR)"
	@fail=0; count=0; \
	for src in $(EXAMPLES); do \
		rel="$${src#examples/}"; \
		out="$(EXAMPLES_OUT_DIR)/$${rel%.jai}"; \
		mkdir -p "$$(dirname "$$out")"; \
		echo "openjai $$src -> $$out"; \
		if ! "$(BOOTSTRAP_COMPILER)" "$$src" --check -o "$$out" --runtime "$(BOOTSTRAP_RUNTIME)"; then \
			fail=1; \
		fi; \
		count=$$((count + 1)); \
	done; \
	echo "compiled $$count supported example(s)"; \
	exit $$fail

selfhost-check: bootstrap
	@mkdir -p "$(SELFHOST_OUT_DIR)"
	@echo "openjai $(SELFHOST_SRC) --check"
	@"$(BOOTSTRAP_COMPILER)" "$(SELFHOST_SRC)" --check \
		-o "$(SELFHOST_COMPILER)" \
		--runtime "$(BOOTSTRAP_RUNTIME)"

selfhost-build: bootstrap
	@mkdir -p "$(SELFHOST_OUT_DIR)"
	@echo "openjai $(SELFHOST_SRC) -> $(SELFHOST_COMPILER)"
	@"$(BOOTSTRAP_COMPILER)" "$(SELFHOST_SRC)" \
		-o "$(SELFHOST_COMPILER)" \
		--runtime "$(BOOTSTRAP_RUNTIME)"

selfhost-hello: selfhost-build
	@echo "selfhost-hello is blocked until the Jai port owns runtime file I/O, LLVM emission, and linking."
	@echo "Run make selfhost-check for the current source-port milestone."
	@exit 1

test-jai: bootstrap
	@cd "$(BOOTSTRAP_DIR)" && zig build test-jai \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

test-all: test-bootstrap examples test-jai

test: test-all

clean:
	rm -rf "$(OUT_DIR)"
