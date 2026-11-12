group "default" {
  targets = ["iso", "image"]
}

variable "IMAGE_TAG" {
  default = "custom-ubuntu:latest"
}

variable "DEBUG_CUSTOMIZATION" {
  default = "false"
}

target "_common" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64"]
  args = {
    RUN_CUSTOMIZATION = "true"
    DEBUG_CUSTOMIZATION = DEBUG_CUSTOMIZATION
  }
}

target "iso" {
  inherits = ["_common"]
  target = "iso-artifact"
  output = ["type=local,dest=./iso-output"]
}

target "image" {
  inherits = ["_common"]
  target = "ubuntu-image"
  tags = [IMAGE_TAG]
  output = ["type=docker"]
}
