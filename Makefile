SHELL := /bin/bash

OUT_DIR := out
BOOTSTRAP_DIR := bootstrap
BOOTSTRAP_PREFIX := $(OUT_DIR)/bootstrap
BOOTSTRAP_CACHE_DIR := $(OUT_DIR)/zig-cache/bootstrap
ZIG_GLOBAL_CACHE_DIR := $(OUT_DIR)/zig-cache/global
BOOTSTRAP_COMPILER := $(BOOTSTRAP_PREFIX)/bin/openjai
BOOTSTRAP_RUNTIME := $(BOOTSTRAP_PREFIX)/lib/openjai_runtime.o
EXAMPLES_OUT_DIR := $(OUT_DIR)/examples

SUPPORTED_EXAMPLES := \
	examples/03/3.1_hello_sailor.jai \
	examples/05/5.1_literals.jai \
	examples/30/main.jai \
	examples/30/main2.jai \
	examples/30/main3.jai \
	examples/30/main6.jai \
	examples/30/main8.jai \
	examples/31/main.jai

EXAMPLES ?= $(SUPPORTED_EXAMPLES)

.PHONY: bootstrap examples clean

bootstrap:
	@mkdir -p "$(OUT_DIR)"
	@cd "$(BOOTSTRAP_DIR)" && zig build \
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
		if ! "$(BOOTSTRAP_COMPILER)" "$$src" -o "$$out" --runtime "$(BOOTSTRAP_RUNTIME)"; then \
			fail=1; \
		fi; \
		count=$$((count + 1)); \
	done; \
	echo "compiled $$count supported example(s)"; \
	exit $$fail

clean:
	rm -rf "$(OUT_DIR)"
