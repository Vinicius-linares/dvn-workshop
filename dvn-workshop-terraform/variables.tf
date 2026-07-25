variable "vpc" {
  type = object({
    cidr_block = string
  })

  default = {
    cidr_block = "10.0.0.0/16"
  }
}