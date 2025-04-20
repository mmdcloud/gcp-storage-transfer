# GCS Bucket-to-Bucket Transfer using Storage Transfer Service

This repository provides Terraform code to automate file transfers between Google Cloud Storage buckets using the Storage Transfer Service.

## Overview

Google Cloud Storage Transfer Service allows you to easily and securely transfer data between cloud storage systems. This implementation focuses specifically on transferring files from one GCS bucket to another, either within the same Google Cloud project or across different projects.

## Features

- Automated one-time or recurring transfers between GCS buckets
- Configurable transfer schedules
- File filtering options based on prefixes and modification times
- Support for deletion options (delete from source after transfer, delete destination files not in source)
- Detailed transfer job status and history
- IAM permissions management for secure transfers

## Prerequisites

- Google Cloud Platform account with billing enabled
- `roles/storagetransfer.admin` and `roles/storage.admin` permissions
- Terraform v1.0.0+
- Google Cloud SDK (optional, for CLI operations)

## Setup

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/gcs-bucket-transfer.git
   cd gcs-bucket-transfer
   ```

2. Update the `terraform.tfvars` file with your configuration details:
   ```hcl
   project_id          = "your-project-id"
   source_bucket       = "source-bucket-name"
   destination_bucket  = "destination-bucket-name"
   transfer_schedule   = "every 24 hours"  # Optional, for recurring transfers
   ```

3. Initialize and apply the Terraform configuration:
   ```
   terraform init
   terraform apply
   ```

## Configuration Options

### Basic Configuration

```hcl
module "storage_transfer" {
  source            = "./modules/storage-transfer"
  project_id        = var.project_id
  source_bucket     = var.source_bucket
  destination_bucket = var.destination_bucket
  description       = "Daily backup transfer"
}
```

### Advanced Configuration with Schedule

```hcl
module "storage_transfer" {
  source            = "./modules/storage-transfer"
  project_id        = var.project_id
  source_bucket     = var.source_bucket
  destination_bucket = var.destination_bucket
  description       = "Weekly transfer with prefix filtering"
  
  # Only transfer files within this prefix
  prefix            = "data/"
  
  # Schedule transfer every Sunday at 2 AM
  schedule = {
    schedule_start_date = {
      year  = 2025
      month = 4
      day   = 20
    }
    schedule_end_date = {
      year  = 2026
      month = 4
      day   = 20
    }
    start_time_of_day = {
      hours   = 2
      minutes = 0
      seconds = 0
      nanos   = 0
    }
    repeat_interval = "604800s"  # 7 days in seconds
  }
  
  # Delete source files after transfer
  delete_objects_from_source_after_transfer = true
}
```

## Core Terraform Resources

The implementation uses the following key resources:

- `google_storage_transfer_job`: Defines the transfer job configuration
- `google_project_iam_member`: Manages IAM permissions for the transfer service account
- `google_storage_bucket_iam_member`: Sets bucket-level permissions

## Terraform Module Structure

```
.
├── main.tf           # Main Terraform configuration
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── modules/
│   └── storage-transfer/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── examples/
    ├── simple-transfer/
    └── scheduled-transfer/
```

## Monitoring Transfers

After deployment, you can monitor transfer jobs through:

1. Google Cloud Console: Navigate to "Storage Transfer Service" section
2. CLI: 
   ```
   gcloud transfer jobs list
   gcloud transfer jobs describe JOB_NAME
   ```

## Troubleshooting

Common issues and solutions:

- **Permission errors**: Ensure the Storage Transfer Service account has proper IAM permissions on both buckets
- **Failed transfers**: Check logs in Cloud Logging with filter `resource.type="storage_transfer_job"`
- **Scheduling issues**: Verify time zone settings and correct schedule format

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
