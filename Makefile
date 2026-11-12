.PHONY: all iso ubuntu test-image clean

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

# Build and load the image, then verify the results of every customization stage.
test-image: ubuntu
	docker run --rm -i custom-ubuntu:latest /bin/bash -s < confirmation.sh

# Remove generated artifacts
clean:
	rm -rf ./iso-output
