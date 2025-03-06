locals {
  current_timestamp = timestamp()
  year              = formatdate("YYYY", local.current_timestamp)
  month             = formatdate("MM", local.current_timestamp)
  day               = formatdate("DD", local.current_timestamp)
  hour              = formatdate("HH", local.current_timestamp)
  minute            = formatdate("mm", local.current_timestamp)
}

data "google_storage_transfer_project_service_account" "default" {
  project = var.project_id
}

# Creating soource and destination buckets
module "source_bucket" {
  source        = "./modules/gcs"
  bucket_name   = "madmaxweb1"
  storage_class = "STANDARD"
  location      = "asia-south1"
  force_destroy = true
  objects = [
    {
      name   = "image-1.jpg",
      source = "../images/image-1.jpg"
    },
    {
      name   = "image-2.jpg",
      source = "../images/image-2.jpg"
    },
    {
      name   = "image-3.jpg",
      source = "../images/image-3.jpg"
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

module "topic" {
  source     = "./modules/pubsub"
  topic_name = var.pubsub_topic_name
}

resource "google_pubsub_topic_iam_member" "notification_config" {
  topic  = module.topic.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# Storage Transfer Job module
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
      start_year               = local.year
      start_month              = local.month
      start_day                = local.day
      end_year                 = local.year
      end_month                = local.month
      end_day                  = local.day + 1
      hours                    = local.hour
      minutes                  = local.minute + 2
      seconds                  = 0
      nanos                    = 0
      schedule_repeat_interval = "3600s"
    }
  ]
  depends_on = [ google_storage_bucket_iam_member.destination_bucket_iam,google_storage_bucket_iam_member.source_bucket_iam ]
}