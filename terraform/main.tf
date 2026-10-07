# -------------------------------------------------------------------------------
# Dynamic Timestamp Calculations
# -------------------------------------------------------------------------------
resource "time_static" "schedule_anchor" {}

locals {
  anchor   = time_static.schedule_anchor.rfc3339
  start_ts = timeadd(local.anchor, "${var.schedule_start_offset_minutes}m")
  end_ts   = timeadd(local.anchor, "${var.schedule_end_offset_hours}h")

  start_year  = tonumber(formatdate("YYYY", local.start_ts))
  start_month = tonumber(formatdate("M", local.start_ts))
  start_day   = tonumber(formatdate("D", local.start_ts))

  schedule_hour   = tonumber(formatdate("HH", local.start_ts))
  schedule_minute = tonumber(formatdate("m", local.start_ts))

  end_year  = tonumber(formatdate("YYYY", local.end_ts))
  end_month = tonumber(formatdate("M", local.end_ts))
  end_day   = tonumber(formatdate("D", local.end_ts))
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
  source        = "./modules/gcp/pubsub"
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
  source        = "./modules/gcp/gcs"
  project_id    = var.project_id
  name          = "${var.source_bucket_name_prefix}-${var.project_id}"
  storage_class = var.storage_class
  location      = var.source_bucket_location
  force_destroy = var.bucket_force_destroy
  cors          = []
  contents      = var.source_files
  notifications = [
    {
      event_types    = ["OBJECT_FINALIZE"]
      payload_format = "JSON_API_V1"
      topic_id       = module.gcs_updates.topic_id
    }
  ]
  uniform_bucket_level_access = true
}

module "destination_bucket" {
  source                      = "./modules/gcp/gcs"
  project_id                  = var.project_id
  name                        = "${var.destination_bucket_name_prefix}-${var.project_id}"
  storage_class               = var.storage_class
  location                    = var.destination_bucket_location
  force_destroy               = var.bucket_force_destroy
  cors                        = []
  contents                    = []
  uniform_bucket_level_access = true
}

# Notification Pub/Sub Topic for STS status alerts
module "notification_topic" {
  source        = "./modules/gcp/pubsub"
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

# -------------------------------------------------------------------------------
# 1. Scheduled Storage Transfer Service
# -------------------------------------------------------------------------------
module "storage_transfer_scheduled" {
  source      = "./modules/gcp/storage-transfer/gcs-to-gcs-scheduled-transfer"
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

  schedule = [{
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
  }]

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
    google_storage_bucket_iam_member.destination_bucket_object_admin,
    google_storage_bucket_iam_member.destination_bucket_legacy_writer,
    google_pubsub_topic_iam_member.notification_config
  ]
}

# -------------------------------------------------------------------------------
# 2. Continuous Replication Module
# -------------------------------------------------------------------------------
module "gcs_replication" {
  source      = "./modules/gcp/storage-transfer/replication"
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
    google_storage_bucket_iam_member.source_bucket_object_viewer,
    google_storage_bucket_iam_member.source_bucket_legacy_reader,
    google_storage_bucket_iam_member.destination_bucket_object_admin,
    google_storage_bucket_iam_member.destination_bucket_legacy_writer,
    google_pubsub_topic_iam_member.notification_config
  ]
}

# -------------------------------------------------------------------------------
# 3. Event-Driven Stream Storage Transfer
# -------------------------------------------------------------------------------
module "storage_transfer_event_driven" {
  source      = "./modules/gcp/storage-transfer/gcs-to-gcs-event-stream"
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
    google_storage_bucket_iam_member.source_bucket_legacy_reader,
    google_storage_bucket_iam_member.destination_bucket_object_admin,
    google_pubsub_topic_iam_member.notification_config
  ]
}

# -------------------------------------------------------------------------------
# 4. Posix => GCS
# -------------------------------------------------------------------------------
resource "google_storage_transfer_agent_pool" "posix_agent_pool" {
  name         = "nfs-migration-pool"
  project      = var.project_id
  display_name = "NFS to GCS Agent Pool"

  # Production bandwidth limit (e.g., 1000 Mbps / 1 Gbps)
  bandwidth_limit {
    limit_mbps = "1000"
  }
}

resource "google_service_account" "transfer_agent_sa" {
  account_id   = "sts-posix-agent-sa"
  display_name = "Storage Transfer Service POSIX Agent"
  project      = var.project_id
}

# Required role for agent container to authenticate with STS Agent Pool
resource "google_project_iam_member" "agent_sa_transfer_agent" {
  project = var.project_id
  role    = "roles/storagetransfer.transferAgent"
  member  = "serviceAccount:${google_service_account.transfer_agent_sa.email}"
}

# Required role for agent container to stream control messages
resource "google_project_iam_member" "agent_sa_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.transfer_agent_sa.email}"
}

# IAM permissions for GCP STS Service Account on Destination Bucket
resource "google_storage_bucket_iam_member" "destination_object_admin" {
  bucket     = module.destination_bucket.bucket_name
  role       = "roles/storage.objectAdmin"
  member     = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
  depends_on = [module.destination_bucket]
}

resource "google_pubsub_topic_iam_member" "notification_publisher" {
  topic  = module.notification_topic.topic_name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

module "posix_to_gcs_transfer" {
  source      = "./modules/gcp/storage-transfer/posix-to-gcs"
  description = "Production POSIX/NFS share sync to GCS"
  status      = "ENABLED"

  transfer_spec = {
    source_agent_pool_name = google_storage_transfer_agent_pool.posix_agent_pool.name

    # Source POSIX / Mounted NFS path on agent host
    posix_data_source = {
      root_directory = "/mnt/nfs_share/"
    }

    # Destination GCS target bucket and optional subfolder
    gcs_data_sink = {
      bucket_name = module.destination_bucket.bucket_name
      path        = "nfs_data_sync/"
    }

    # Object conditions & filters
    object_conditions = {
      min_time_elapsed_since_last_modification = "300s" # Skip files being written (5m buffer)
      exclude_prefixes                         = [".snapshot/", ".tmp/", "lost+found/"]
    }

    # Production sync options & metadata preservation
    transfer_options = {
      overwrite_when                             = "DIFFERENT" # Transfer if size/mtime/checksum differs
      overwrite_objects_already_existing_in_sink = true
      delete_objects_unique_in_sink              = false # Prevent accidental data loss in bucket
      delete_objects_from_source_after_transfer  = false

      metadata_options = {
        mode          = "MODE_PRESERVE"         # Preserve POSIX file permissions
        gid           = "GID_NUMBER"            # Preserve POSIX group ID
        uid           = "UID_NUMBER"            # Preserve POSIX user ID
        symlink       = "SYMLINK_PRESERVE"      # Preserve symlinks
        time_created  = "TIME_CREATED_PRESERVE" # Preserve original file creation timestamps
        storage_class = "STORAGE_CLASS_DESTINATION_BUCKET_DEFAULT"
      }
    }
  }

  # Production transfer schedule (Runs daily at 02:00 UTC)
  schedule = [{
    start_year               = 2026
    start_month              = 1
    start_day                = 1
    end_year                 = 2030
    end_month                = 12
    end_day                  = 31
    hours                    = 2
    minutes                  = 0
    seconds                  = 0
    nanos                    = 0
    schedule_repeat_interval = "86400s" # Daily execution
  }]

  # Detailed audit logs in Cloud Logging
  logging_config = {
    enable_on_prem_gcs_transfer_logs = true
    log_actions                      = ["FIND", "COPY", "DELETE"]
    log_action_states                = ["SUCCEEDED", "FAILED"]
  }

  # Pub/Sub alert notifications
  notification_config = [
    {
      pubsub_topic = module.notification_topic.topic_id
      event_types = [
        "TRANSFER_OPERATION_SUCCESS",
        "TRANSFER_OPERATION_FAILED",
        "TRANSFER_OPERATION_ABORTED"
      ]
      payload_format = "JSON"
    }
  ]

  depends_on = [
    google_storage_bucket_iam_member.destination_object_admin,
    google_pubsub_topic_iam_member.notification_publisher
  ]
}

# -------------------------------------------------------------------------------
# 5. AWS S3 to GCS Event-Driven Stream Transfer
# -------------------------------------------------------------------------------
# 5.1 AWS S3 Source Bucket
resource "aws_s3_bucket" "source_bucket" {
  bucket        = "source-s3-${var.project_id}"
  force_destroy = true
}

# 5.2 AWS SQS Queue for S3 ObjectCreated Notifications
resource "aws_sqs_queue" "s3_event_queue" {
  name                      = "s3-gcs-transfer-events-${var.project_id}"
  message_retention_seconds = 604800 # 7 days
  receive_wait_time_seconds = 20     # Long polling
}

# 5.3 SQS Queue Policy (Permit S3 notifications & GCP STS consumer access)
resource "aws_sqs_queue_policy" "s3_event_queue_policy" {
  queue_url = aws_sqs_queue.s3_event_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketEvents"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.s3_event_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.source_bucket.arn
          }
        }
      }
    ]
  })
}

# 5.4 S3 Bucket Notification to SQS
resource "aws_s3_bucket_notification" "s3_events" {
  bucket = aws_s3_bucket.source_bucket.id

  queue {
    queue_arn = aws_sqs_queue.s3_event_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.s3_event_queue_policy]
}

# 5.5 AWS IAM Role for GCP Storage Transfer Service
resource "aws_iam_role" "gcp_sts_role" {
  name = "gcp-storage-transfer-role-${var.project_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "accounts.google.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "accounts.google.com:sub" = data.google_storage_transfer_project_service_account.default.subject_id
          }
        }
      }
    ]
  })
}

# 5.6 AWS IAM Policy for S3 read & SQS consume permissions
resource "aws_iam_role_policy" "gcp_sts_policy" {
  name = "gcp-sts-s3-sqs-access"
  role = aws_iam_role.gcp_sts_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SourcePermissions"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*"
        ]
      },
      {
        Sid    = "SQSConsumerPermissions"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.s3_event_queue.arn
      }
    ]
  })
}

# 5.7 AWS S3 to GCS Transfer Job Module
module "storage_transfer_s3_event_stream" {
  source      = "./modules/gcp/storage-transfer/s3-gcs-event-stream"
  name        = "transferJobs/s3-to-gcs-stream-${random_id.id.hex}"
  description = "Real-time AWS S3 to GCS Event Stream Sync"
  status      = "ENABLED"

  transfer_spec = {
    aws_s3_data_source = {
      bucket_name = aws_s3_bucket.source_bucket.id
      path        = "incoming/"
      role_arn    = aws_iam_role.gcp_sts_role.arn
    }

    gcs_data_sink = {
      bucket_name = module.destination_bucket.bucket_name
      path        = "s3_synced_data/"
    }

    object_conditions = {
      min_time_elapsed_since_last_modification = "120s"
    }

    transfer_options = {
      overwrite_when                             = "DIFFERENT"
      overwrite_objects_already_existing_in_sink = true
      delete_objects_unique_in_sink              = false
      delete_objects_from_source_after_transfer  = false
    }
  }

  event_stream = [
    {
      name = aws_sqs_queue.s3_event_queue.arn
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
    google_storage_bucket_iam_member.destination_bucket_object_admin,
    google_pubsub_topic_iam_member.notification_config,
    aws_s3_bucket_notification.s3_events,
    aws_iam_role_policy.gcp_sts_policy
  ]
}

# -------------------------------------------------------------------------------
# 6. Azure Blob Storage to GCS Event-Driven Stream Transfer
# -------------------------------------------------------------------------------
data "azuread_client_config" "current" {}
# 1. Create Azure AD App Registration for GCP STS
resource "azuread_application" "gcp_sts_app" {
  display_name = "gcp-storage-transfer-service-${var.project_id}"
}
resource "azuread_service_principal" "gcp_sts_sp" {
  client_id = azuread_application.gcp_sts_app.client_id
}
# 2. Establish Federated Trust with GCP Storage Transfer Service SA
resource "azuread_application_federated_identity_credential" "gcp_sts_fed_cred" {
  application_id = azuread_application.gcp_sts_app.id
  display_name   = "gcp-sts-federated-credential"
  description    = "Trust GCP Storage Transfer Service OIDC token"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://accounts.google.com"
  subject        = data.google_storage_transfer_project_service_account.default.subject_id
}
# 3. Grant Azure RBAC: Read Blobs
resource "azurerm_role_assignment" "sts_blob_reader" {
  scope                = azurerm_storage_account.source_storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.gcp_sts_sp.object_id
}
# 4. Grant Azure RBAC: Process Event Grid Queue Messages
resource "azurerm_role_assignment" "sts_queue_processor" {
  scope                = azurerm_storage_account.source_storage.id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = azuread_service_principal.gcp_sts_sp.object_id
}

# 6.1 Azure Resource Group
resource "azurerm_resource_group" "source_rg" {
  name     = "rg-storage-transfer-${var.project_id}"
  location = "eastus"
}

# 6.2 Azure Storage Account & Container
resource "azurerm_storage_account" "source_storage" {
  name                     = "stsaz${random_id.id.hex}"
  resource_group_name      = azurerm_resource_group.source_rg.name
  location                 = azurerm_resource_group.source_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "source_container" {
  name                  = "incoming-blobs"
  storage_account_id    = azurerm_storage_account.source_storage.id
  container_access_type = "private"
}

# 6.3 Azure Storage Queue for Event Grid BlobCreated Notifications
resource "azurerm_storage_queue" "blob_events" {
  name               = "blob-created-events"
  storage_account_id = azurerm_storage_account.source_storage.id
}

# 6.4 Azure Event Grid System Topic for Storage Account
resource "azurerm_eventgrid_system_topic" "storage_events" {
  name                = "st-eventgrid-topic-${var.project_id}"
  resource_group_name = azurerm_resource_group.source_rg.name
  location            = azurerm_resource_group.source_rg.location
  source_resource_id  = azurerm_storage_account.source_storage.id
  topic_type          = "Microsoft.Storage.StorageAccounts"
}

# 6.5 Azure Event Grid Event Subscription targeting Storage Queue
resource "azurerm_eventgrid_system_topic_event_subscription" "blob_created" {
  name                = "blob-created-subscription"
  system_topic        = azurerm_eventgrid_system_topic.storage_events.name
  resource_group_name = azurerm_resource_group.source_rg.name

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.source_storage.id
    queue_name         = azurerm_storage_queue.blob_events.name
  }

  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]
}

# 6.6 Azure Account SAS Token for Storage Transfer Service Authentication (Blob + Queue access)
data "azurerm_storage_account_sas" "account_sas" {
  connection_string = azurerm_storage_account.source_storage.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = true
    table = false
    file  = false
  }

  start  = "2026-01-01T00:00:00Z"
  expiry = "2030-01-01T00:00:00Z"

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = true
    add     = false
    create  = false
    update  = false
    process = true # Required for STS to read and dequeue event notifications from Azure Queue
    tag     = false
    filter  = false
  }
}

# 6.7 Azure Blob to GCS Transfer Job Module
module "storage_transfer_azure_event_stream" {
  source      = "./modules/gcp/storage-transfer/azure-to-gcs-event-stream"
  name        = "transferJobs/azure-to-gcs-stream-${random_id.id.hex}"
  description = "Real-time Azure Blob to GCS Event Stream Sync"
  status      = "ENABLED"

  transfer_spec = {
    azure_blob_storage_data_source = {
      storage_account = azurerm_storage_account.source_storage.name
      container       = azurerm_storage_container.source_container.name
      path            = ""
      federated_identity_config = {
        client_id = azuread_application.gcp_sts_app.client_id
        tenant_id = data.azuread_client_config.current.tenant_id
      }
      # azure_credentials = {
      #   sas_token = data.azurerm_storage_account_sas.account_sas.sas
      # }
    }

    gcs_data_sink = {
      bucket_name = module.destination_bucket.bucket_name
    }

    object_conditions = {
      min_time_elapsed_since_last_modification = "120s"
    }

    transfer_options = {
      overwrite_when                             = "DIFFERENT"
      overwrite_objects_already_existing_in_sink = true
      delete_objects_unique_in_sink              = false
      delete_objects_from_source_after_transfer  = false
    }
  }

  event_stream = [
    {
      name = "${azurerm_storage_account.source_storage.name}.queue.core.windows.net/${azurerm_storage_queue.blob_events.name}"
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
    google_storage_bucket_iam_member.destination_bucket_object_admin,
    google_pubsub_topic_iam_member.notification_config,
    azurerm_storage_queue.blob_events,
    azurerm_eventgrid_system_topic_event_subscription.blob_created
  ]
}
