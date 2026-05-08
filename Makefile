SHELL := /bin/bash

OUT_DIR := out
BOOTSTRAP_DIR := bootstrap
BOOTSTRAP_PREFIX := $(OUT_DIR)/bootstrap
BOOTSTRAP_CACHE_DIR := $(OUT_DIR)/zig-cache/bootstrap
ZIG_GLOBAL_CACHE_DIR := $(OUT_DIR)/zig-cache/global
BOOTSTRAP_COMPILER := $(BOOTSTRAP_PREFIX)/bin/openjai
BOOTSTRAP_RUNTIME := $(BOOTSTRAP_PREFIX)/lib/openjai_runtime.o
EXAMPLES_OUT_DIR := $(OUT_DIR)/examples
FOCUS_DIR := .reference/focus
FOCUS_OUT_DIR := $(OUT_DIR)/reference/focus

SUPPORTED_EXAMPLES := $(shell find examples -type f -name '*.jai' | sort)

EXAMPLES ?= $(SUPPORTED_EXAMPLES)

.PHONY: bootstrap test test-bootstrap examples focus test-jai test-all clean

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

focus: bootstrap
	@mkdir -p "$(FOCUS_OUT_DIR)"
	@echo "openjai $(FOCUS_DIR)/first.jai -> $(FOCUS_OUT_DIR)/focus"
	@cd "$(FOCUS_DIR)" && "$(abspath $(BOOTSTRAP_COMPILER))" first.jai --check \
		-o "$(abspath $(FOCUS_OUT_DIR))/focus" \
		--runtime "$(abspath $(BOOTSTRAP_RUNTIME))"

test-jai: bootstrap
	@cd "$(BOOTSTRAP_DIR)" && zig build test-jai \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

test-all: test-bootstrap examples test-jai

test: test-all

clean:
	rm -rf "$(OUT_DIR)"
