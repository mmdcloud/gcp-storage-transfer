variable "project_id" {
  type    = string
  default = "orbital-bee-455915-h5"
}
variable "source_bucket_location" {
  type    = string
  default = "asia-south1"
}
variable "destination_bucket_location" {
  type    = string
  default = "asia-south2"
}
variable "pubsub_topic_name" {
  type    = string
  default = "storage-transfer-topic"
}
