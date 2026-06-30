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

# ------------------------------------------------------------------------------
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
  bucket_name   = "madmaxweb1"
  storage_class = "STANDARD"
  location      = "asia-south1"
  force_destroy = true
  objects = [
    {
      name   = "image-1.jpg",
      source = "../src/image-1.jpg"
    },
    {
      name   = "image-2.jpg",
      source = "../src/image-2.jpg"
    },
    {
      name   = "image-3.jpg",
      source = "../src/image-3.jpg"
    }
  ]
}

module "destination_bucket" {
  source        = "./modules/gcs"
  bucket_name   = "madmaxweb2"
  storage_class = "STANDARD"
  location      = "asia-south2"
  force_destroy = true
}

# -------------------------------------------------------------------------------
# Cloud storage iam bindings
# -------------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "source_bucket_iam" {
  bucket     = module.source_bucket.name
  role       = "roles/storage.admin"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.source_bucket]
}

resource "google_storage_bucket_iam_member" "destination_bucket_iam" {
  bucket     = module.destination_bucket.name
  role       = "roles/storage.admin"
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
  source                        = "./modules/storage-transfer"
  description                   = "Storage Transfer Service"
  delete_objects_unique_in_sink = false
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
  source_bucket_name = module.source_bucket.name
  dest_bucket_name   = module.destination_bucket.name

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
  depends_on = [google_storage_bucket_iam_member.destination_bucket_iam, google_storage_bucket_iam_member.source_bucket_iam, google_pubsub_topic_iam_member.notification_config]
}
