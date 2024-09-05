USER := tirion
ID := $(shell basename $(CURDIR))
CONTAINER_ID := $(addsuffix _container, $(ID))
CONTAINER_ID_INTERNAL := $(addsuffix _container_internal, $(ID))
IMAGE_ID := $(addsuffix _image, $(ID))
CS = $(shell docker ps -a -q)
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
# NOTE: сохраняем массив в перемнную ENVS из строки используя разделитель ";"
# Далее распаковываем массив в аргументы при вызове команды sudo ${ENVS[@]}
# Так переменные окружения попадют в сеанс sudo
# Пример: sudo "ENV1=value1" "ENV2=value with spaces" "ENV3=value3" -u tirion -s
GET_ENVS := IFS=";" ENVS=(`get-forwarded-envs`)

# получаем uid и gid пользователя
USER_UID := $(shell docker run --rm $(IMAGE_ID) id -u $(USER))
USER_GID := $(shell docker run --rm $(IMAGE_ID) id -g $(USER))
TEMP_VOLUME := temp_volume

docs-js:
	docker exec -it $(CONTAINER_ID) /bin/bash -c '$(GET_ENVS) && sudo "$${ENVS[@]}" -u $(USER) rm -rf docs && mkdir -p docs && /import-documentation/dist/bin/import-documentation.js . -o docs'

test:
ifeq ([], $(shell docker inspect $(CONTAINER_ID) 2> /dev/null))
	@ echo "Please, run 'make start' before 'make test'" >&2; exit 1;
else
	docker exec -it $(CONTAINER_ID) /bin/bash -c '$(GET_ENVS) && sudo "$${ENVS[@]}" -u $(USER) make test'
endif

prepare:
ifeq ([], $(shell docker inspect $(CONTAINER_ID) 2> /dev/null))
	@ echo "Please, run 'make start' before 'make test'" >&2; exit 1;
else
	docker exec -it $(CONTAINER_ID) make prepare
endif

build: stop
	docker build -t $(IMAGE_ID) .


# небольшой хак, чтобы маунтить вольюм практики CURDIR/exercise с uid и gid пользователя внутри контейнера
# создаем промежуточный контейнер, в котором меняем права на USER
# промежуточный контейнер необходим, тк в командах bash и start вольюм монтируется в read-only
temp-volume:
	docker volume create --name $(TEMP_VOLUME)

	docker run --rm \
	  -v $(CURDIR)/exercise/:/from \
	  -v $(TEMP_VOLUME):/to \
	  alpine sh -c 'cp -R /from/* /to && chown -R $(USER_UID):$(USER_GID) /to'

rm-volume:
	docker volume rm -f $(TEMP_VOLUME)

bash: rm-volume temp-volume
	docker run --rm --read-only -it \
	  -v /tmp \
	  -v $(ROOT_DIR)scripts/get-forwarded-envs:/usr/local/bin/get-forwarded-envs \
	  -v $(CURDIR)/exercise_internal:/exercise_internal \
	  -v $(TEMP_VOLUME):/usr/src/app \
	  $(IMAGE_ID) \
	  /bin/bash -c '$(GET_ENVS) && sudo "$${ENVS[@]}" -u tirion -s'


bash-root:
	docker run --rm -it -v /tmp \
		-v $(ROOT_DIR)scripts/get-forwarded-envs:/usr/local/bin/get-forwarded-envs \
	  -v $(CURDIR)/exercise_internal:/exercise_internal \
	  -v $(CURDIR)/exercise/:/usr/src/app $(IMAGE_ID) \
	  /bin/bash -c '$(GET_ENVS) && sudo "$${ENVS[@]}" -u root -s'

attach:
ifeq ([], $(shell docker inspect $(CONTAINER_ID) 2> /dev/null))
	@ make start
endif
	docker exec -it $(CONTAINER_ID) /bin/bash -c '$(GET_ENVS) && sudo "$${ENVS[@]}" -u $(USER) -s'

logs:
	docker logs -f $(CONTAINER_ID)

start: stop rm-volume temp-volume
ifeq ([], $(shell docker inspect $(IMAGE_ID) 2> /dev/null))
	@ echo "Please, run 'make build' before 'make start'" >&2; exit 1;
else
	docker run -d -t --read-only --rm \
		--label hexlet-exercise \
		--memory=500m \
		--memory-swap=500m \
		--cpu-shares=256 \
		--oom-kill-disable=true \
		--pids-limit=150 \
		--memory-swappiness=0 \
		-v $(ROOT_DIR)import-documentation:/import-documentation \
		-v /tmp \
		-v /var/tmp \
		-v $(ROOT_DIR)scripts/get-forwarded-envs:/usr/local/bin/get-forwarded-envs \
		-v $(TEMP_VOLUME):/usr/src/app \
		-v $(CURDIR)/exercise_internal:/exercise_internal \
		-p 8000:8000 -p 80:8080 -p 5006:5006 --name $(CONTAINER_ID) $(IMAGE_ID)
endif

stop:
	docker stop `docker ps -a -q --filter label=hexlet-exercise` || true

diff:
	@ docker diff $(CS)

# start_internal: stop
# ifeq ([], $(shell docker inspect $(IMAGE_ID) 2> /dev/null))
# 	@ echo "Please, run 'make build'" >&2; exit 1;
# else
# 	docker run -d -t -v $(CURDIR)/exercise_internal:/exercise_internal --name $(CONTAINER_ID_INTERNAL) $(IMAGE_ID)
# endif

test_internal:
ifeq ([], $(shell docker inspect $(CONTAINER_ID) 2> /dev/null))
	@ echo "Please, run 'make start_internal'" >&2; exit 1;
else
	# docker exec $(CONTAINER_ID) make test -C /exercise_internal
	docker exec $(CONTAINER_ID) /bin/bash -c '$(GET_ENVS) && sudo "$${ENVS[@]}" -u $(USER) make test -C /exercise_internal'
endif

lint-js:
	@npx eslint .

lint-hexlet-python:
	@make lint L=python-flake8

lint-hexlet-js:
	@make lint L=eslint

lint-hexlet-php:
	@make lint L=phpcs

lint-hexlet-java:
	@make lint L=checkstyle

lint-hexlet-sql:
	@make lint L=sqlint

lint-hexlet-ruby:
	@make lint L=rubocop

lint-hexlet-layout:
	@make lint L=layout-designer-lint

lint-hexlet-multi-language:
	@make lint L=multi-language

lint:
	@docker run --rm -it \
		-v $(CURDIR)/exercise:/usr/src/app \
		-v hexlet-linter-${L}:/usr/src/linter \
		$(IMAGE_ID) \
		/usr/src/linter/linter

all: build start test

.PHONY: test build bash run stop start

markdown-lint:
	npx markdownlint -c ../../../../.markdownlint.json ${CURDIR}

markdown-lint-fix:
	npx markdownlint -f -c ../../../../.markdownlint.json ${CURDIR}

spellcheck:
	docker run --rm -v ./:/content ghcr.io/hexlet/languagetool-cli node ./bin/run.js check /content/**/*.md
