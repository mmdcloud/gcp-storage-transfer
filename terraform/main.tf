# -------------------------------------------------------------------------------
# Dynamic Timestamp Calculations
# -------------------------------------------------------------------------------
locals {
  current_timestamp = timestamp()
  start_year        = formatdate("YYYY", local.current_timestamp)
  start_month       = formatdate("MM", local.current_timestamp)
  start_day         = formatdate("DD", local.current_timestamp)

  # Derive end date using variable hours offset
  end_timestamp = timeadd(local.current_timestamp, "${var.schedule_end_offset_hours}h")
  end_year      = formatdate("YYYY", local.end_timestamp)
  end_month     = formatdate("MM", local.end_timestamp)
  end_day       = formatdate("DD", local.end_timestamp)

  # Derive scheduled start hour/minute using variable minutes offset
  start_timestamp_plus_offset = timeadd(local.current_timestamp, "${var.schedule_start_offset_minutes}m")
  schedule_minute             = formatdate("mm", local.start_timestamp_plus_offset)
  schedule_hour               = formatdate("HH", local.start_timestamp_plus_offset)
}

# -------------------------------------------------------------------------------
# Service Accounts & Core Identifiers
# -------------------------------------------------------------------------------
data "google_storage_transfer_project_service_account" "default" {
  project = var.project_id
}

data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

resource "random_id" "id" {
  byte_length = 8
}

# -------------------------------------------------------------------------------
# Core Infrastructure: Storage Buckets & Event Streams
# -------------------------------------------------------------------------------
module "gcs_updates" {
  source        = "./modules/pubsub"
  topic_name    = var.gcs_updates_topic_name
  enable_schema = false
  topic_iam = {
    bindings = {
      "roles/pubsub.publisher" = ["serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"]
    }
  }
  subscriptions = {
    gcs_transfer_subscription = {
      subscription_name = var.transfer_subscription_name
      iam = {
        bindings = {
          "roles/pubsub.subscriber" = ["serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"]
        }
      }
      message_retention_duration = var.subscription_message_retention
      retain_acked_messages      = false
      ack_deadline_seconds       = var.subscription_ack_deadline
    }
  }
}

module "source_bucket" {
  source        = "./modules/gcs"
  name          = "${var.source_bucket_name_prefix}-${var.project_id}"
  storage_class = var.storage_class
  location      = var.source_bucket_location
  force_destroy = var.bucket_force_destroy
  cors = [
    {
      origin          = ["*"]
      max_age_seconds = 3600
      method          = ["GET"]
      response_header = ["*"]
    }
  ]
  contents = var.source_files
  notifications = [
    {
      event_types    = ["OBJECT_FINALIZE"]
      payload_format = "JSON_API_V1"
      topic_id       = module.gcs_updates.topic_id
    }
  ]
}

module "destination_bucket" {
  source        = "./modules/gcs"
  name          = "${var.destination_bucket_name_prefix}-${var.project_id}"
  storage_class = var.storage_class
  location      = var.destination_bucket_location
  force_destroy = var.bucket_force_destroy
  cors = [
    {
      origin          = ["*"]
      max_age_seconds = 3600
      method          = ["PUT"]
      response_header = ["*"]
    }
  ]
  contents = []
}

# Notification Pub/Sub Topic for STS status alerts
module "notification_topic" {
  source        = "./modules/pubsub"
  topic_name    = var.pubsub_topic_name
  enable_schema = false
}

# -------------------------------------------------------------------------------
# Unified IAM Permissions
# -------------------------------------------------------------------------------
# Source Bucket Permissions
resource "google_storage_bucket_iam_member" "source_bucket_object_viewer" {
  bucket     = module.source_bucket.bucket_name
  role       = "roles/storage.objectViewer"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.source_bucket]
}

resource "google_storage_bucket_iam_member" "source_bucket_legacy_reader" {
  bucket     = module.source_bucket.bucket_name
  role       = "roles/storage.legacyBucketReader"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.source_bucket]
}

resource "google_storage_bucket_iam_member" "source_bucket_legacy_owner" {
  bucket     = module.source_bucket.bucket_name
  role       = "roles/storage.legacyBucketOwner"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.source_bucket]
}

# Destination Bucket Permissions
resource "google_storage_bucket_iam_member" "destination_bucket_object_admin" {
  bucket     = module.destination_bucket.bucket_name
  role       = "roles/storage.objectAdmin"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.destination_bucket]
}

resource "google_storage_bucket_iam_member" "destination_bucket_legacy_writer" {
  bucket     = module.destination_bucket.bucket_name
  role       = "roles/storage.legacyBucketWriter"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.destination_bucket]
}

# Project & Pub/Sub IAM
resource "google_project_iam_member" "sts_pubsub_editor" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

resource "google_pubsub_topic_iam_member" "notification_config" {
  topic  = module.notification_topic.topic_name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# resource "google_pubsub_topic_iam_member" "gcs_publisher" {
#   topic  = module.gcs_updates.topic_name
#   role   = "roles/pubsub.publisher"
#   member = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
# }

# resource "google_pubsub_subscription_iam_member" "transfer_subscriber" {
#   subscription = google_pubsub_subscription.transfer_sub.name
#   role         = "roles/pubsub.subscriber"
#   member       = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# -------------------------------------------------------------------------------
# 1. Scheduled Storage Transfer Service
# -------------------------------------------------------------------------------
module "storage_transfer_scheduled" {
  source      = "./modules/storage-transfer"
  description = var.transfer_job_description

  transfer_spec = {
    gcs_data_sink = {
      bucket_name = module.destination_bucket.bucket_name
    }
    gcs_data_source = {
      bucket_name = module.source_bucket.bucket_name
    }
    transfer_options = {
      delete_objects_unique_in_sink = var.delete_objects_unique_in_sink
    }
  }

  schedule = [
    {
      start_year               = local.start_year
      start_month              = local.start_month
      start_day                = local.start_day
      end_year                 = local.end_year
      end_month                = local.end_month
      end_day                  = local.end_day
      hours                    = local.schedule_hour
      minutes                  = local.schedule_minute
      seconds                  = 0
      nanos                    = 0
      schedule_repeat_interval = var.schedule_repeat_interval
    }
  ]

  notification_config = [
    {
      pubsub_topic = module.notification_topic.topic_id
      event_types = [
        "TRANSFER_OPERATION_SUCCESS",
        "TRANSFER_OPERATION_FAILED"
      ]
      payload_format = "JSON"
    }
  ]

  depends_on = [
    google_storage_bucket_iam_member.source_bucket_object_viewer,
    google_storage_bucket_iam_member.source_bucket_legacy_reader,
    google_storage_bucket_iam_member.destination_bucket_legacy_writer,
    google_pubsub_topic_iam_member.notification_config
  ]
}

# -------------------------------------------------------------------------------
# 2. Continuous Replication Module
# -------------------------------------------------------------------------------
module "gcs_replication" {
  source      = "./modules/storage-transfer"
  name        = null
  description = var.replication_job_description
  status      = "ENABLED"

  replication_spec = [{
    source_bucket_name = module.source_bucket.bucket_name
    sink_bucket_name   = module.destination_bucket.bucket_name
    source_path        = ""
    sink_path          = ""
    transfer_options = {
      delete_objects_unique_in_sink = var.delete_objects_unique_in_sink
    }
  }]

  schedule     = []
  event_stream = []
  notification_config = [
    {
      pubsub_topic = module.notification_topic.topic_id
      event_types = [
        "TRANSFER_OPERATION_SUCCESS",
        "TRANSFER_OPERATION_FAILED"
      ]
      payload_format = "JSON"
    }
  ]

  depends_on = [
    google_storage_bucket_iam_member.source_bucket_legacy_owner,
    google_storage_bucket_iam_member.source_bucket_object_viewer,
    google_storage_bucket_iam_member.destination_bucket_legacy_writer,
    google_project_iam_member.sts_pubsub_editor,
    google_project_iam_member.gcs_pubsub_publisher,
    google_pubsub_topic_iam_member.notification_config
  ]
}

# -------------------------------------------------------------------------------
# 3. Event-Driven Stream Storage Transfer
# -------------------------------------------------------------------------------
module "storage_transfer_event_driven" {
  source      = "./modules/storage-transfer"
  name        = "transferJobs/storagetransfer-${random_id.id.hex}"
  description = "${var.transfer_job_description} (Event Driven)"

  transfer_spec = {
    gcs_data_sink = {
      bucket_name = module.destination_bucket.bucket_name
    }
    gcs_data_source = {
      bucket_name = module.source_bucket.bucket_name
    }
    transfer_options = {
      delete_objects_unique_in_sink = var.delete_objects_unique_in_sink
    }
  }

  event_stream = [
    {
      name = module.gcs_updates.subscription_ids["gcs_transfer_subscription"]
    }
  ]

  notification_config = [
    {
      pubsub_topic = module.notification_topic.topic_id
      event_types = [
        "TRANSFER_OPERATION_SUCCESS",
        "TRANSFER_OPERATION_FAILED"
      ]
      payload_format = "JSON"
    }
  ]

  depends_on = [
    google_storage_bucket_iam_member.source_bucket_object_viewer,
    google_storage_bucket_iam_member.destination_bucket_object_admin
  ]
}
