.PHONY: check

check:
	sh -n install-all.sh
	bash -n install-all.sh
	sh tests/check.sh
