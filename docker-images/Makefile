TAG ?= runner-images
IMAGES := $(patsubst %/Dockerfile,%,$(wildcard */Dockerfile))

.PHONY: build
build: $(addprefix build-,$(IMAGES))

.PHONY: publish
publish: $(addprefix publish-,$(IMAGES))

# Note: Make sure the version label is here to overwrite the value inherited from the base image
build-%:
	cd "$*" && \
	docker build --tag "$(TAG):$*" . \
		--label "org.opencontainers.image.created=$$(date --utc '+%FT%T.%NZ')" \
		--label "org.opencontainers.image.revision=$$(git describe --always --dirty --no-abbrev)" \
		--label "org.opencontainers.image.version=0.0.0+$$(date --utc '+%Y%m%d%H%M%S')"

publish-%: build-%
	docker tag "$*" "$(TAG):$*"
	docker push "$(TAG):$*"
