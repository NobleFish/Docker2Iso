.PHONY: all iso ubuntu ubuntu-clean test-image clean

DOCKER ?= docker
IMAGE_TAG ?= custom-ubuntu:latest
ISO_OUTPUT_DIR ?= ./iso-output
DEBUG_CUSTOMIZATION ?= false

# Build both artifacts
all:
	$(DOCKER) buildx bake

# Build the custom ISO
iso:
	$(DOCKER) buildx build \
		--target iso-artifact \
		--build-arg RUN_CUSTOMIZATION=true \
		--build-arg DEBUG_CUSTOMIZATION=$(DEBUG_CUSTOMIZATION) \
		--output type=local,dest=$(ISO_OUTPUT_DIR) \
		.

# Build the custom Ubuntu image
ubuntu:
	$(DOCKER) buildx build \
		--target ubuntu-image \
		--build-arg RUN_CUSTOMIZATION=true \
		--build-arg DEBUG_CUSTOMIZATION=$(DEBUG_CUSTOMIZATION) \
		--tag $(IMAGE_TAG) \
		--load \
		.

# Rebuild every layer when diagnosing stale-cache issues.
ubuntu-clean:
	$(DOCKER) buildx build \
		--no-cache \
		--target ubuntu-image \
		--build-arg RUN_CUSTOMIZATION=true \
		--build-arg DEBUG_CUSTOMIZATION=$(DEBUG_CUSTOMIZATION) \
		--tag $(IMAGE_TAG) \
		--load \
		.

# Build and load the image, then verify the results of every customization stage.
test-image: ubuntu
	$(DOCKER) run --rm -i $(IMAGE_TAG) /bin/bash -s < confirmation.sh

# Remove generated artifacts
clean:
	rm -rf $(ISO_OUTPUT_DIR)
