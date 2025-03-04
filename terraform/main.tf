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

resource "google_storage_bucket" "source_bucket" {
  name          = "madmaxweb1"
  storage_class = "STANDARD"
  project       = var.project_id
  location      = "asia-south1"
  force_destroy = true
}

resource "google_storage_bucket" "destination_bucket" {
  name          = "madmaxweb2"
  storage_class = "STANDARD"
  project       = var.project_id
  location      = "asia-south2"
  force_destroy = true
}

resource "google_storage_bucket_object" "image1" {
  name   = "image-1.jpg"
  bucket = google_storage_bucket.source_bucket.name
  source = "../images/image-1.jpg"
}

resource "google_storage_bucket_object" "image2" {
  name   = "image-2.jpg"
  bucket = google_storage_bucket.source_bucket.name
  source = "../images/image-2.jpg"
}

resource "google_storage_bucket_object" "image3" {
  name   = "image-3.jpg"
  bucket = google_storage_bucket.source_bucket.name
  source = "../images/image-3.jpg"
}

resource "google_storage_bucket_iam_member" "source_bucket_iam" {
  bucket     = google_storage_bucket.source_bucket.name
  role       = "roles/storage.admin"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [google_storage_bucket.source_bucket]
}

resource "google_storage_bucket_iam_member" "destination_bucket_iam" {
  bucket     = google_storage_bucket.destination_bucket.name
  role       = "roles/storage.admin"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [google_storage_bucket.destination_bucket]
}

resource "google_pubsub_topic" "topic" {
  name = var.pubsub_topic_name
}

resource "google_pubsub_topic_iam_member" "notification_config" {
  topic  = google_pubsub_topic.topic.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

resource "google_storage_transfer_job" "storage_transfer_service" {
  description = "Storage Transfer Service"
  project     = var.project_id

  transfer_spec {
    transfer_options {
      delete_objects_unique_in_sink = false
    }
    gcs_data_source {
      bucket_name = google_storage_bucket.source_bucket.name
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.destination_bucket.name
    }
  }

  schedule {
    schedule_start_date {
      year  = local.year
      month = local.month
      day   = local.day
    }
    schedule_end_date {
      year  = local.year
      month = local.month
      day   = local.day + 1
    }
    start_time_of_day {
      hours   = local.hour
      minutes = local.minute + 2
      seconds = 0
      nanos   = 0
    }
    repeat_interval = "3600s"
  }

  notification_config {
    pubsub_topic = google_pubsub_topic.topic.id
    event_types = [
      "TRANSFER_OPERATION_SUCCESS",
      "TRANSFER_OPERATION_FAILED"
    ]
    payload_format = "JSON"
  }

  depends_on = [google_storage_bucket_iam_member.source_bucket_iam, google_pubsub_topic_iam_member.notification_config]
}
