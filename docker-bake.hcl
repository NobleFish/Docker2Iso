group "default" {
  targets = ["iso", "image"]
}

target "iso" {
  context = "."
  dockerfile = "Dockerfile"
  target = "iso-artifact"
  output = ["type=local,dest=./iso-output"]
  args = {
    RUN_CUSTOMIZATION = "true"
  }
}

target "image" {
  context = "."
  dockerfile = "Dockerfile"
  target = "ubuntu-image"
  tags = ["custom-ubuntu:latest"]
  output = ["type=docker"]
  args = {
    RUN_CUSTOMIZATION = "true"
  }
}
