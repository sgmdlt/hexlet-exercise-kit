DOWNLOADER_IMAGE_NAME=hexlet/gitlab-downloader
DOWNLOADER_HOME=/home/tirion
SSH_KEYS_PATH?=$(HOME)/.ssh
UID := $(shell id -u)
GID := $(shell id -g)
HEXLETHQ=hexlethq
LOCALE ?=
REGISTRY := cr.yandex/crpa5i79t7oiqnj0ap8g

setup: create-config pull build-downloader prepare-dirs
	make -C import-documentation all
	npm ci

prepare-dirs:
	mkdir -p exercises
	mkdir -p courses
	mkdir -p projects
	mkdir -p programs
	mkdir -p boilerplates

pull:
	docker pull $(REGISTRY)/hexlet-python
	docker pull $(REGISTRY)/hexlet-java
	docker pull $(REGISTRY)/hexlet-javascript
	docker pull $(REGISTRY)/hexlet-php
	docker pull ghcr.io/hexlet/languagetool-cli

create-config:
	cp -n .env.example .env || echo 'already exists'

build-downloader: create-config
	docker build -t $(DOWNLOADER_IMAGE_NAME):latest \
		--build-arg UID=$(UID) \
		--build-arg GID=$(GID) \
		./repo-downloader

copy-from-cb:
	make -C code-basics-synchronizer

downloader-run:
	docker run -it --rm \
		--env-file ./.env \
		-v $(SSH_KEYS_PATH):/home/tirion/.ssh \
		-v $(CURDIR):/data/hexlethq \
		$(DOWNLOADER_IMAGE_NAME) \
		clone $(HEXLETHQ)/$(FILTER)$(if $(LOCALE),/$(LOCALE))

clone: clone-courses clone-exercises clone-projects clone-boilerplates

clone-courses:
	make downloader-run FILTER=courses

clone-exercises:
	make downloader-run FILTER=exercises

clone-projects:
	make downloader-run FILTER=projects

clone-boilerplates:
	make downloader-run FILTER=boilerplates

update-hexlet-linter:
	docker pull $(REGISTRY)/common-${L}
	docker volume rm -f hexlet-linter-${L}
	docker run --rm -v hexlet-linter-${L}:/linter $(REGISTRY)/common-${L} echo > /dev/null

update-hexlet-linters:
	make update-hexlet-linter L=eslint
	make update-hexlet-linter L=python-flake8
	make update-hexlet-linter L=phpcs
	make update-hexlet-linter L=checkstyle
	make update-hexlet-linter L=sqlint
	make update-hexlet-linter L=rubocop
	make update-hexlet-linter L=multi-language
	make update-hexlet-linter L=python-ruff

create-localizer-config:
	cp -n content-localizer/.env.template content-localizer/.env || echo 'already exists'

build-localizer: create-localizer-config
	docker build -t hexlet/content-localizer \
		--build-arg UID=$(UID) \
		--build-arg GID=$(GID) \
		./content-localizer
