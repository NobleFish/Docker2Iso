.PHONY: all iso ubuntu clean

# Build both artifacts
all:
	docker buildx bake

# Build the custom ISO
iso:
	docker buildx build \
		--target iso-artifact \
		--build-arg RUN_CUSTOMIZATION=true \
		--output type=local,dest=./iso-output \
		.

# Build the custom Ubuntu image
ubuntu:
	docker buildx build \
		--no-cache \
		--target ubuntu-image \
		--build-arg RUN_CUSTOMIZATION=true \
		--tag custom-ubuntu:latest \
		--load \
		.

# Remove generated artifacts
clean:
	rm -rf ./iso-output