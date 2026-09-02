locals {
  current_timestamp = timestamp()
  start_year        = formatdate("YYYY", local.current_timestamp)
  start_month       = formatdate("MM", local.current_timestamp)
  start_day         = formatdate("DD", local.current_timestamp)

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

resource "random_id" "id" {
  byte_length = 8
}

# -------------------------------------------------------------------------------
# Scheduled transfer usage 
# -------------------------------------------------------------------------------
# module "source_bucket" {
#   source        = "./modules/gcs"
#   name          = "source-bucket-${var.project_id}"
#   storage_class = "STANDARD"
#   location      = "asia-south1"
#   force_destroy = true
#   cors = [
#     {
#       origin          = ["*"]
#       max_age_seconds = 3600
#       method          = ["GET"]
#       response_header = ["*"]
#     }
#   ]
#   contents = [
#     {
#       name        = "image-1.jpg",
#       content     = ""
#       source_path = "../src/image-1.jpg"
#     },
#     {
#       name        = "image-2.jpg",
#       content     = ""
#       source_path = "../src/image-2.jpg"
#     },
#     {
#       name        = "image-3.jpg",
#       content     = ""
#       source_path = "../src/image-3.jpg"
#     }
#   ]
# }

# module "destination_bucket" {
#   source        = "./modules/gcs"
#   name          = "destination-bucket-${var.project_id}"
#   storage_class = "STANDARD"
#   location      = "asia-south2"
#   force_destroy = true
#   cors = [
#     {
#       origin          = ["*"]
#       max_age_seconds = 3600
#       method          = ["PUT"]
#       response_header = ["*"]
#     }
#   ]
#   contents = []
# }

# resource "google_storage_bucket_iam_member" "source_bucket_object_viewer" {
#   bucket     = module.source_bucket.bucket_name
#   role       = "roles/storage.objectViewer"
#   member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
#   depends_on = [module.source_bucket]
# }

# resource "google_storage_bucket_iam_member" "source_bucket_legacy_reader" {
#   bucket     = module.source_bucket.bucket_name
#   role       = "roles/storage.legacyBucketReader"
#   member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
#   depends_on = [module.source_bucket]
# }

# resource "google_storage_bucket_iam_member" "destination_bucket_legacy_writer" {
#   bucket     = module.destination_bucket.bucket_name
#   role       = "roles/storage.legacyBucketWriter"
#   member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
#   depends_on = [module.destination_bucket]
# }

# module "topic" {
#   source     = "./modules/pubsub"
#   topic_name = var.pubsub_topic_name
# }

# resource "google_pubsub_topic_iam_member" "notification_config" {
#   topic  = module.topic.id
#   role   = "roles/pubsub.publisher"
#   member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# module "storage_transfer_service" {
#   source      = "./modules/storage-transfer"
#   description = "Storage Transfer Service"

#   transfer_spec = {
#     gcs_data_sink = {
#       bucket_name = module.destination_bucket.bucket_name
#     }
#     gcs_data_source = {
#       bucket_name = module.source_bucket.bucket_name
#     }
#     transfer_options = {
#       delete_objects_unique_in_sink = false
#     }
#   }

#   schedule = [
#     {
#       start_year               = local.start_year
#       start_month              = local.start_month
#       start_day                = local.start_day
#       end_year                 = local.end_year
#       end_month                = local.end_month
#       end_day                  = local.end_day
#       hours                    = local.schedule_hour
#       minutes                  = local.schedule_minute
#       seconds                  = 0
#       nanos                    = 0
#       schedule_repeat_interval = "3600s"
#     }
#   ]

#   notification_config = [
#     {
#       pubsub_topic = module.topic.id
#       event_types = [
#         "TRANSFER_OPERATION_SUCCESS",
#         "TRANSFER_OPERATION_FAILED"
#       ]
#       payload_format = "JSON"
#     }
#   ]

#   depends_on = [
#     google_storage_bucket_iam_member.source_bucket_object_viewer,
#     google_storage_bucket_iam_member.source_bucket_legacy_reader,
#     google_storage_bucket_iam_member.destination_bucket_legacy_writer,
#     google_pubsub_topic_iam_member.notification_config
#   ]
# }

# -------------------------------------------------------------------------------
# Replication module usage 
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

resource "google_storage_bucket_iam_member" "source_bucket_object_viewer" {
  bucket     = module.source_bucket.bucket_name
  role       = "roles/storage.objectViewer"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.source_bucket]
}

resource "google_storage_bucket_iam_member" "source_bucket_legacy_owner" {
  bucket     = module.source_bucket.bucket_name
  role       = "roles/storage.legacyBucketOwner"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.source_bucket]
}

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

resource "google_project_iam_member" "sts_pubsub_editor" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
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

module "gcs_replication" {
  source      = "./modules/storage-transfer"
  name        = null
  description = "Continuous replication from raw to processed bucket"
  status      = "ENABLED"

  replication_spec = [{
    source_bucket_name = module.source_bucket.bucket_name
    sink_bucket_name   = module.destination_bucket.bucket_name
    source_path        = ""
    sink_path          = ""
    transfer_options = {
      delete_objects_unique_in_sink = false
    }
  }]

  schedule     = [] # must stay empty with replication_spec
  event_stream = [] # must stay empty with replication_spec
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
    google_storage_bucket_iam_member.source_bucket_legacy_owner,
    google_storage_bucket_iam_member.source_bucket_object_viewer,
    google_storage_bucket_iam_member.destination_bucket_legacy_writer,
    google_project_iam_member.sts_pubsub_editor,
    google_project_iam_member.gcs_pubsub_publisher,
    google_pubsub_topic_iam_member.notification_config
  ]
}

# -------------------------------------------------------------------------------
# Event stream usage 
# -------------------------------------------------------------------------------
# data "google_storage_project_service_account" "gcs_sa" {}

# resource "google_pubsub_topic" "gcs_updates" {
#   name = "gcs-source-bucket-updates"
# }

# # Pull subscription consumed by the Storage Transfer Service
# resource "google_pubsub_subscription" "transfer_sub" {
#   name  = "gcs-transfer-subscription"
#   topic = google_pubsub_topic.gcs_updates.id

#   # Retain unacknowledged messages for 7 days
#   message_retention_duration = "604800s"
#   retain_acked_messages      = false
#   ack_deadline_seconds       = 30
# }

# module "source_bucket" {
#   source        = "./modules/gcs"
#   name          = "source-bucket-${var.project_id}"
#   storage_class = "STANDARD"
#   location      = "asia-south1"
#   force_destroy = true
#   cors = [
#     {
#       origin          = ["*"]
#       max_age_seconds = 3600
#       method          = ["GET"]
#       response_header = ["*"]
#     }
#   ]
#   contents = [
#     {
#       name        = "image-1.jpg",
#       content     = ""
#       source_path = "../src/image-1.jpg"
#     },
#     {
#       name        = "image-2.jpg",
#       content     = ""
#       source_path = "../src/image-2.jpg"
#     },
#     {
#       name        = "image-3.jpg",
#       content     = ""
#       source_path = "../src/image-3.jpg"
#     }
#   ]
#   notifications = [
#     {
#       event_types    = ["OBJECT_FINALIZE"]
#       payload_format = "JSON_API_V1"
#       topic_id       = google_pubsub_topic.gcs_updates.id
#     }
#   ]
# }

# module "destination_bucket" {
#   source        = "./modules/gcs"
#   name          = "destination-bucket-${var.project_id}"
#   storage_class = "STANDARD"
#   location      = "asia-south2"
#   force_destroy = true
#   cors = [
#     {
#       origin          = ["*"]
#       max_age_seconds = 3600
#       method          = ["PUT"]
#       response_header = ["*"]
#     }
#   ]
#   contents = []
# }

# module "notification_topic" {
#   source     = "./modules/pubsub"
#   topic_name = var.pubsub_topic_name
# }

# resource "google_pubsub_topic_iam_member" "notification_config" {
#   topic  = module.notification_topic.id
#   role   = "roles/pubsub.publisher"
#   member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# resource "google_pubsub_topic_iam_member" "gcs_publisher" {
#   topic  = google_pubsub_topic.gcs_updates.name
#   role   = "roles/pubsub.publisher"
#   member = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
# }

# resource "google_pubsub_subscription_iam_member" "transfer_subscriber" {
#   subscription = google_pubsub_subscription.transfer_sub.name
#   role         = "roles/pubsub.subscriber"
#   member       = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# # Grant Transfer SA read access to the Source Bucket
# resource "google_storage_bucket_iam_member" "source_viewer" {
#   bucket = module.source_bucket.bucket_name
#   role   = "roles/storage.objectViewer"
#   member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# resource "google_storage_bucket_iam_member" "source_legacy_bucket_reader" {
#   bucket = module.source_bucket.bucket_name
#   role   = "roles/storage.legacyBucketReader"
#   member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# # Grant Transfer SA write access to Destination Bucket
# resource "google_storage_bucket_iam_member" "destination_writer" {
#   bucket = module.destination_bucket.bucket_name
#   role   = "roles/storage.objectAdmin"
#   member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# resource "google_storage_bucket_iam_member" "destination_bucket_legacy_writer" {
#   bucket = module.destination_bucket.bucket_name
#   role   = "roles/storage.legacyBucketWriter"
#   member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
# }

# module "storage_transfer_service" {
#   source      = "./modules/storage-transfer"
#   name        = "transferJobs/storagetransfer-${random_id.id.hex}"
#   description = "Storage Transfer Service"

#   transfer_spec = {
#     gcs_data_sink = {
#       bucket_name = module.destination_bucket.bucket_name
#     }
#     gcs_data_source = {
#       bucket_name = module.source_bucket.bucket_name
#     }
#     transfer_options = {
#       delete_objects_unique_in_sink = false
#     }
#   }

#   event_stream = [
#     {
#       name = google_pubsub_subscription.transfer_sub.id
#     }
#   ]

#   notification_config = [
#     {
#       pubsub_topic = module.notification_topic.id
#       event_types = [
#         "TRANSFER_OPERATION_SUCCESS",
#         "TRANSFER_OPERATION_FAILED"
#       ]
#       payload_format = "JSON"
#     }
#   ]

#   depends_on = [
#     google_pubsub_subscription_iam_member.transfer_subscriber,
#     google_storage_bucket_iam_member.source_viewer,
#     google_storage_bucket_iam_member.destination_writer
#   ]
# }