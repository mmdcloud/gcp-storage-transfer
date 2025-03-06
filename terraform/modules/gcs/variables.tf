variable "bucket_name" {}
variable "storage_class" {}
variable "location" {}
variable "force_destroy" {}
variable "objects" {
  type = list(object({
    name    = string
    source = string
  }))

  default = []
}
