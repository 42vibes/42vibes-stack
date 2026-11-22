.PHONY: check

check:
	sh -n install-all.sh
	bash -n install-all.sh
	@set -e; \
	tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT HUP INT TERM; \
	HOME="$$tmp" ./install-all.sh --all --dry-run --home "$$tmp" >/dev/null; \
	test -z "$$(ls -A "$$tmp")"; \
	./install-all.sh --help >/dev/null; \
	echo "check: ok"
