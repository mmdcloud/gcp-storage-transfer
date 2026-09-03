# -------------------------------------------------------------------------------
# Core Configuration
# -------------------------------------------------------------------------------
variable "project_id" {
  description = "The GCP Project ID where resources will be deployed."
  type        = string
}

variable "region" {
  description = "Primary GCP region for resources."
  type        = string
  default     = "asia-south1"
}

# -------------------------------------------------------------------------------
# GCS Bucket Configuration
# -------------------------------------------------------------------------------
variable "source_bucket_name_prefix" {
  description = "Prefix for the source GCS bucket name."
  type        = string
  default     = "source-bucket"
}

variable "source_bucket_location" {
  description = "GCP location for the source bucket."
  type        = string
  default     = "asia-south1"
}

variable "destination_bucket_name_prefix" {
  description = "Prefix for the destination GCS bucket name."
  type        = string
  default     = "destination-bucket"
}

variable "destination_bucket_location" {
  description = "GCP location for the destination bucket."
  type        = string
  default     = "asia-south2"
}

variable "storage_class" {
  description = "Storage class for the GCS buckets."
  type        = string
  default     = "STANDARD"
}

variable "bucket_force_destroy" {
  description = "When set to true, allows deletion of non-empty buckets."
  type        = bool
  default     = true
}

variable "source_files" {
  description = "List of initial contents to seed into the source bucket."
  type = list(object({
    name        = string
    content     = string
    source_path = string
  }))
  default = [
    {
      name        = "image-1.jpg"
      content     = ""
      source_path = "../src/image-1.jpg"
    },
    {
      name        = "image-2.jpg"
      content     = ""
      source_path = "../src/image-2.jpg"
    },
    {
      name        = "image-3.jpg"
      content     = ""
      source_path = "../src/image-3.jpg"
    }
  ]
}

# -------------------------------------------------------------------------------
# Pub/Sub Configuration
# -------------------------------------------------------------------------------
variable "pubsub_topic_name" {
  description = "Name of the central notification Pub/Sub topic."
  type        = string
  default     = "transfer-notifications-topic"
}

variable "gcs_updates_topic_name" {
  description = "Pub/Sub topic name for source GCS bucket event stream notifications."
  type        = string
  default     = "gcs-source-bucket-updates"
}

variable "transfer_subscription_name" {
  description = "Name of the Pub/Sub subscription consumed by Storage Transfer Service."
  type        = string
  default     = "gcs-transfer-subscription"
}

variable "subscription_message_retention" {
  description = "Duration (in seconds) to retain unacknowledged Pub/Sub messages."
  type        = string
  default     = "604800s" # 7 days
}

variable "subscription_ack_deadline" {
  description = "Acknowledgement deadline (in seconds) for Pub/Sub subscription."
  type        = number
  default     = 30
}

# -------------------------------------------------------------------------------
# Storage Transfer Service & Schedule Settings
# -------------------------------------------------------------------------------
variable "transfer_job_description" {
  description = "Description for the scheduled Storage Transfer job."
  type        = string
  default     = "Scheduled GCS to GCS Storage Transfer Service"
}

variable "replication_job_description" {
  description = "Description for the continuous GCS replication job."
  type        = string
  default     = "Continuous replication from raw to processed bucket"
}

variable "schedule_end_offset_hours" {
  description = "Hours from execution time when the scheduled transfer job should stop."
  type        = number
  default     = 24
}

variable "schedule_start_offset_minutes" {
  description = "Minutes to add to current time for the initial schedule start execution."
  type        = number
  default     = 2
}

variable "schedule_repeat_interval" {
  description = "Repeat interval for scheduled transfer job (e.g., '3600s' for hourly)."
  type        = string
  default     = "3600s"
}

variable "delete_objects_unique_in_sink" {
  description = "Whether to delete objects in sink that do not exist in source."
  type        = bool
  default     = false
}