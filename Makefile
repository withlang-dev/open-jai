SHELL := /bin/bash

OUT_DIR := out
BOOTSTRAP_DIR := bootstrap
BOOTSTRAP_PREFIX := $(OUT_DIR)/bootstrap
BOOTSTRAP_CACHE_DIR := $(OUT_DIR)/zig-cache/bootstrap
ZIG_GLOBAL_CACHE_DIR := $(OUT_DIR)/zig-cache/global
BOOTSTRAP_COMPILER := $(BOOTSTRAP_PREFIX)/bin/openjai
BOOTSTRAP_RUNTIME := $(BOOTSTRAP_PREFIX)/lib/openjai_runtime.o
EXAMPLES_OUT_DIR := $(OUT_DIR)/examples

.PHONY: bootstrap examples clean

bootstrap:
	@mkdir -p "$(OUT_DIR)"
	@cd "$(BOOTSTRAP_DIR)" && zig build \
		--prefix "../$(BOOTSTRAP_PREFIX)" \
		--cache-dir "../$(BOOTSTRAP_CACHE_DIR)" \
		--global-cache-dir "../$(ZIG_GLOBAL_CACHE_DIR)"

examples: bootstrap
	@mkdir -p "$(EXAMPLES_OUT_DIR)"
	@fail=0; count=0; skipped=0; \
	while IFS= read -r src; do \
		if ! grep -Eq '^[[:space:]]*main[[:space:]]*::' "$$src"; then \
			skipped=$$((skipped + 1)); \
			continue; \
		fi; \
		rel="$${src#examples/}"; \
		out="$(EXAMPLES_OUT_DIR)/$${rel%.jai}"; \
		mkdir -p "$$(dirname "$$out")"; \
		echo "openjai $$src -> $$out"; \
		if ! "$(BOOTSTRAP_COMPILER)" "$$src" -o "$$out" --runtime "$(BOOTSTRAP_RUNTIME)"; then \
			fail=1; \
		fi; \
		count=$$((count + 1)); \
	done < <(find examples -type f -name '*.jai' ! -path '*/.build/*' -print | sort); \
	echo "compiled $$count example entry point(s); skipped $$skipped helper file(s)"; \
	exit $$fail

clean:
	rm -rf "$(OUT_DIR)"
