.PHONY: run format

.SILENT:

run:
	docker run --platform linux/amd64 -it --rm -v $(shell pwd):/usr/src/app -p "4000:4000"   starefossen/github-pages

format:
	npx prettier '**/*' --write --ignore-unknown