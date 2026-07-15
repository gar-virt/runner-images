TAG ?= docker.yourdomain.local/runner-images
IMAGES := $(patsubst %/Dockerfile,%,$(wildcard */Dockerfile))

.PHONY: build
build: $(addprefix build-,$(IMAGES))

.PHONY: publish
publish: $(addprefix publish-,$(IMAGES))

build-%:
	cd "$*" && docker build -t "$*" .

publish-%: build-%
	docker tag "$*" "$(TAG):$*"
	docker push "$(TAG):$*"
