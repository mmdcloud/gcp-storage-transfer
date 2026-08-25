locals {
  current_timestamp = timestamp()
  start_year        = formatdate("YYYY", local.current_timestamp)
  start_month       = formatdate("MM", local.current_timestamp)
  start_day         = formatdate("DD", local.current_timestamp)
  hour              = formatdate("HH", local.current_timestamp)
  minute            = formatdate("mm", local.current_timestamp)

  # Add 24h as an actual duration, then derive the end date from the result
  end_timestamp = timeadd(local.current_timestamp, "24h")
  end_year      = formatdate("YYYY", local.end_timestamp)
  end_month     = formatdate("MM", local.end_timestamp)
  end_day       = formatdate("DD", local.end_timestamp)

  # Same issue applies to minutes - add as a duration too
  start_timestamp_plus_2m = timeadd(local.current_timestamp, "2m")
  schedule_minute         = formatdate("mm", local.start_timestamp_plus_2m)
  schedule_hour           = formatdate("HH", local.start_timestamp_plus_2m)
}

# -------------------------------------------------------------------------------
# Storage transfer service account
# -------------------------------------------------------------------------------
data "google_storage_transfer_project_service_account" "default" {
  project = var.project_id
}

# -------------------------------------------------------------------------------
# Cloud storage buckets
# -------------------------------------------------------------------------------
module "source_bucket" {
  source        = "./modules/gcs"
  name          = "source-bucket-${var.project_id}"
  storage_class = "STANDARD"
  location      = "asia-south1"
  force_destroy = true
  cors = [
    {
      origin          = ["*"]
      max_age_seconds = 3600
      method          = ["GET"]
      response_header = ["*"]
    }
  ]
  contents = [
    {
      name        = "image-1.jpg",
      content     = ""
      source_path = "../src/image-1.jpg"
    },
    {
      name        = "image-2.jpg",
      content     = ""
      source_path = "../src/image-2.jpg"
    },
    {
      name        = "image-3.jpg",
      content     = ""
      source_path = "../src/image-3.jpg"
    }
  ]
}

module "destination_bucket" {
  source        = "./modules/gcs"
  name          = "destination-bucket-${var.project_id}"
  storage_class = "STANDARD"
  location      = "asia-south2"
  force_destroy = true
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

# -------------------------------------------------------------------------------
# Cloud storage iam bindings
# -------------------------------------------------------------------------------
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

resource "google_storage_bucket_iam_member" "destination_bucket_legacy_writer" {
  bucket     = module.destination_bucket.bucket_name
  role       = "roles/storage.legacyBucketWriter"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.destination_bucket]
}

# -------------------------------------------------------------------------------
# PubSub configuration
# -------------------------------------------------------------------------------
module "topic" {
  source     = "./modules/pubsub"
  topic_name = var.pubsub_topic_name
}

resource "google_pubsub_topic_iam_member" "notification_config" {
  topic  = module.topic.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# -------------------------------------------------------------------------------
# Storage Transfer Job module
# -------------------------------------------------------------------------------
module "storage_transfer_service" {
  source      = "./modules/storage-transfer"
  name        = "transferJobs/storagetransfer"
  description = "Storage Transfer Service"

  transfer_spec = {
    gcs_data_sink = {
      bucket_name = module.destination_bucket.bucket_name
    }
    gcs_data_source = {
      bucket_name = module.source_bucket.bucket_name
    }
    transfer_options = {
      delete_objects_unique_in_sink = false
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
      schedule_repeat_interval = "3600s"
    }
  ]

  notification_config = [
    {
      pubsub_topic = module.topic.id
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
# Replication module usage 
# -------------------------------------------------------------------------------
# module "gcs_replication" {
#   source           = "./modules/storage-transfer"
#   name             = null
#   description      = "Continuous replication from raw to processed bucket"
#   deletion_policy  = "DELETE"
#   status           = "ENABLED"
#   service_account  = var.service_account
#   source_bucket_name = null   # not used, must be null so transfer_spec doesn't fire
#   dest_bucket_name   = null

#   replication_spec = [{
#     source_bucket_name = "raw-data-bucket"
#     sink_bucket_name    = "processed-data-bucket"
#     sink_path           = "incoming/"
#     transfer_options = {
#       overwrite_objects_already_existing_in_sink = true
#     }
#   }]

#   schedule             = []  # must stay empty with replication_spec
#   event_stream         = []  # must stay empty with replication_spec
#   notification_config  = []
# }
