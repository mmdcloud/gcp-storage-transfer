variable "project_id" {
  type    = string
  default = "nodal-talon-445602-m1"
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
