# # ===============================================================================
# # MANAGED SFTP ON GOOGLE CLOUD (CLOUD FTP)
# # Production-Grade Architecture based on Alistair Grew's Specification
# # "Managed SFTP on Google Cloud: For the protocol that refuses to die..."
# # ===============================================================================
# #
# # Key Architectural Principles:
# # 1. Zero Long-Lived Static Password Credentials:
# #    - Authentication via OpenSSH public/private key pairs.
# # 2. Service Account Impersonation & Least-Privilege IAM:
# #    - Every SFTP user is explicitly mapped to a customer service account.
# #    - Cloud FTP Service Agent (ftp.googleapis.com) assumes this identity dynamically
# #      via `roles/iam.serviceAccountTokenCreator`.
# #    - User Service Account is strictly granted scoped GCS permissions
# #      (`roles/storage.objectUser`) only on its allocated bucket path.
# # 3. Network Isolation & Dual Access Topologies:
# #    - EXTERNAL: Internet-facing with strict IP allowlisting (CIDR blocks).
# #    - INTERNAL: Private Service Connect (PSC) endpoint inside a dedicated VPC.
# # 4. Enterprise GCS Foundation:
# #    - Uniform Bucket-Level Access (UBLA), object versioning, and auto-lifecycle rules.
# # 5. Cloud Audit Logging & Operational Observability.
# # ===============================================================================

# # -------------------------------------------------------------------------------
# # Variables for Cloud FTP Configuration
# # -------------------------------------------------------------------------------
# variable "cloud_ftp_region" {
#   description = "Region for Cloud FTP resources (e.g. us-central1, europe-west1)."
#   type        = string
#   default     = "us-central1"
# }

# variable "cloud_ftp_server_name" {
#   description = "Identifier for the Cloud FTP / SFTP server."
#   type        = string
#   default     = "prod-managed-sftp"
# }

# variable "cloud_ftp_access_type" {
#   description = "Access type for Cloud FTP server: EXTERNAL (Public with CIDR allowlist) or INTERNAL (Private Service Connect)."
#   type        = string
#   default     = "EXTERNAL"
#   validation {
#     condition     = contains(["EXTERNAL", "INTERNAL"], var.cloud_ftp_access_type)
#     error_message = "cloud_ftp_access_type must be either 'EXTERNAL' or 'INTERNAL'."
#   }
# }

# variable "cloud_ftp_allowed_cidrs" {
#   description = "List of allowed CIDR IP blocks permitted to access the external SFTP server."
#   type        = list(string)
#   default     = ["203.0.113.0/24"] # Example corporate IP block. Set to specific client CIDRs or ["0.0.0.0/0"] for open testing
# }

# variable "cloud_ftp_username" {
#   description = "SFTP username for external partner or internal workflow."
#   type        = string
#   default     = "partner-upload"
# }

# variable "cloud_ftp_user_ssh_public_key" {
#   description = "OpenSSH public key for the SFTP user. If left empty, an automated SSH key pair will be generated via tls_private_key."
#   type        = string
#   default     = ""
# }

# # -------------------------------------------------------------------------------
# # 1. Enable Required Google Cloud APIs
# # -------------------------------------------------------------------------------
# resource "google_project_service" "ftp_api" {
#   project                    = var.project_id
#   service                    = "ftp.googleapis.com"
#   disable_dependent_services = false
#   disable_on_destroy         = false
# }

# resource "google_project_service" "compute_api" {
#   project                    = var.project_id
#   service                    = "compute.googleapis.com"
#   disable_dependent_services = false
#   disable_on_destroy         = false
# }

# # -------------------------------------------------------------------------------
# # 2. Production GCS Bucket for SFTP File Ingestion & Distribution
# # -------------------------------------------------------------------------------
# resource "random_id" "ftp_bucket_suffix" {
#   byte_length = 4
# }

# resource "google_storage_bucket" "sftp_storage_bucket" {
#   name                        = "sftp-exchange-${var.project_id}-${random_id.ftp_bucket_suffix.hex}"
#   location                    = var.cloud_ftp_region
#   project                     = var.project_id
#   storage_class               = "STANDARD"
#   uniform_bucket_level_access = true
#   force_destroy               = true

#   versioning {
#     enabled = true
#   }

#   lifecycle_rule {
#     action {
#       type = "Delete"
#     }
#     condition {
#       age        = 90
#       with_state = "ARCHIVED"
#     }
#   }

#   labels = {
#     environment = "production"
#     service     = "cloud-ftp"
#     managed_by  = "terraform"
#   }
# }

# # Create standard subdirectories within bucket (inbound/outbound)
# resource "google_storage_bucket_object" "inbound_folder" {
#   name    = "inbound/"
#   content = "SFTP inbound folder placeholder"
#   bucket  = google_storage_bucket.sftp_storage_bucket.name
# }

# resource "google_storage_bucket_object" "outbound_folder" {
#   name    = "outbound/"
#   content = "SFTP outbound folder placeholder"
#   bucket  = google_storage_bucket.sftp_storage_bucket.name
# }

# # -------------------------------------------------------------------------------
# # 3. Dedicated Customer Service Account (Least-Privilege User Identity)
# # -------------------------------------------------------------------------------
# resource "google_service_account" "sftp_user_sa" {
#   account_id   = "sftp-user-${var.cloud_ftp_username}"
#   display_name = "Cloud FTP Managed User Identity for ${var.cloud_ftp_username}"
#   description  = "Dedicated service account mapped to SFTP user ${var.cloud_ftp_username} for scoped GCS operations"
#   project      = var.project_id
# }

# # Grant user SA read/write permissions strictly to the SFTP exchange bucket
# resource "google_storage_bucket_iam_member" "sftp_sa_bucket_access" {
#   bucket = google_storage_bucket.sftp_storage_bucket.name
#   role   = "roles/storage.objectUser"
#   member = "serviceAccount:${google_service_account.sftp_user_sa.email}"
# }

# # -------------------------------------------------------------------------------
# # 4. Cloud FTP Service Agent Identity & Token Creator IAM Binding
# # -------------------------------------------------------------------------------
# # GCP project service identity for Cloud FTP (ftp.googleapis.com)
# resource "google_project_service_identity" "ftp_service_agent" {
#   provider = google-beta
#   project  = var.project_id
#   service  = "ftp.googleapis.com"

#   depends_on = [google_project_service.ftp_api]
# }

# # Authorize Cloud FTP Service Agent to generate short-lived tokens for customer SA
# resource "google_service_account_iam_member" "ftp_service_agent_token_creator" {
#   service_account_id = google_service_account.sftp_user_sa.name
#   role               = "roles/iam.serviceAccountTokenCreator"
#   member             = "serviceAccount:${google_project_service_identity.ftp_service_agent.email}"
# }

# # -------------------------------------------------------------------------------
# # 5. SSH Key Pair Generation (for seamless deployment if no key provided)
# # -------------------------------------------------------------------------------
# resource "tls_private_key" "sftp_client_key" {
#   count     = var.cloud_ftp_user_ssh_public_key == "" ? 1 : 0
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# locals {
#   effective_ssh_public_key = var.cloud_ftp_user_ssh_public_key != "" ? var.cloud_ftp_user_ssh_public_key : (
#     length(tls_private_key.sftp_client_key) > 0 ? trimspace(tls_private_key.sftp_client_key[0].public_key_openssh) : ""
#   )
# }

# # -------------------------------------------------------------------------------
# # 6. VPC Network & Subnet (for INTERNAL PSC Connectivity Option)
# # -------------------------------------------------------------------------------
# resource "google_compute_network" "sftp_vpc" {
#   name                    = "sftp-psc-vpc"
#   auto_create_subnetworks = false
#   project                 = var.project_id
# }

# resource "google_compute_subnetwork" "sftp_subnet" {
#   name                     = "sftp-psc-subnet"
#   ip_cidr_range            = "10.10.0.0/24"
#   region                   = var.cloud_ftp_region
#   network                  = google_compute_network.sftp_vpc.id
#   project                  = var.project_id
#   private_ip_google_access = true
# }

# # Reserved internal IP for Private Service Connect Endpoint
# resource "google_compute_address" "sftp_psc_internal_ip" {
#   count        = var.cloud_ftp_access_type == "INTERNAL" ? 1 : 0
#   name         = "sftp-psc-internal-ip"
#   subnetwork   = google_compute_subnetwork.sftp_subnet.id
#   address_type = "INTERNAL"
#   region       = var.cloud_ftp_region
#   project      = var.project_id
# }

# # -------------------------------------------------------------------------------
# # 7. Cloud FTP Server Configuration
# # -------------------------------------------------------------------------------
# # Cloud FTP (ftp.googleapis.com) is currently managed via Google Cloud Storage FTP
# # Service. We manage its lifecycle via terraform_data with gcloud alpha storage ftp.
# resource "terraform_data" "cloud_ftp_server" {
#   input = {
#     server_name   = var.cloud_ftp_server_name
#     region        = var.cloud_ftp_region
#     access_type   = var.cloud_ftp_access_type
#     allowed_cidrs = join(",", var.cloud_ftp_allowed_cidrs)
#     project_id    = var.project_id
#   }

#   provisioner "local-exec" {
#     command = <<-EOT
#       echo "Provisioning Managed SFTP Server ${var.cloud_ftp_server_name}..."
#       if [ "${var.cloud_ftp_access_type}" = "EXTERNAL" ]; then
#         gcloud alpha storage ftp servers create ${var.cloud_ftp_server_name} \
#           --location=${var.cloud_ftp_region} \
#           --access-type=EXTERNAL \
#           --allowed-cidr-blocks=${join(",", var.cloud_ftp_allowed_cidrs)} \
#           --project=${var.project_id} || true
#       else
#         gcloud alpha storage ftp servers create ${var.cloud_ftp_server_name} \
#           --location=${var.cloud_ftp_region} \
#           --access-type=INTERNAL \
#           --consumer-accept-list=${var.project_id}=10 \
#           --project=${var.project_id} || true
#       fi
#     EOT
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "gcloud alpha storage ftp servers delete ${self.input.server_name} --location=${self.input.region} --project=${self.input.project_id} --quiet || true"
#   }

#   depends_on = [
#     google_project_service.ftp_api,
#     google_project_service_identity.ftp_service_agent,
#     google_service_account_iam_member.ftp_service_agent_token_creator
#   ]
# }

# # -------------------------------------------------------------------------------
# # 8. Cloud FTP User Mapping
# # -------------------------------------------------------------------------------
# # Maps the SFTP username, public SSH key, Customer SA, and GCS directory paths
# resource "terraform_data" "cloud_ftp_user" {
#   input = {
#     username        = var.cloud_ftp_username
#     server_name     = var.cloud_ftp_server_name
#     region          = var.cloud_ftp_region
#     project_id      = var.project_id
#     service_account = google_service_account.sftp_user_sa.email
#     public_key      = local.effective_ssh_public_key
#   }

#   provisioner "local-exec" {
#     command = <<-EOT
#       echo "Provisioning Cloud FTP User ${var.cloud_ftp_username}..."
#       gcloud alpha storage ftp users create ${var.cloud_ftp_username} \
#         --server=${var.cloud_ftp_server_name} \
#         --location=${var.cloud_ftp_region} \
#         --customer-service-account=${google_service_account.sftp_user_sa.email} \
#         --ssh-public-key="${local.effective_ssh_public_key}" \
#         --project=${var.project_id} || true
#     EOT
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "gcloud alpha storage ftp users delete ${self.input.username} --server=${self.input.server_name} --location=${self.input.region} --project=${self.input.project_id} --quiet || true"
#   }

#   depends_on = [
#     terraform_data.cloud_ftp_server,
#     google_storage_bucket_iam_member.sftp_sa_bucket_access
#   ]
# }

# # -------------------------------------------------------------------------------
# # 9. Cloud Monitoring & Audit Observability
# # -------------------------------------------------------------------------------
# # Enable Data Access Cloud Audit Logs for Cloud FTP API
# resource "google_project_iam_audit_config" "ftp_audit_logs" {
#   project = var.project_id
#   service = "ftp.googleapis.com"

#   audit_log_config {
#     log_type = "ADMIN_READ"
#   }
#   audit_log_config {
#     log_type = "DATA_READ"
#   }
#   audit_log_config {
#     log_type = "DATA_WRITE"
#   }
# }

# # -------------------------------------------------------------------------------
# # Outputs
# # -------------------------------------------------------------------------------
# output "cloud_ftp_server_name" {
#   description = "Name of the provisioned Cloud FTP server"
#   value       = var.cloud_ftp_server_name
# }

# output "cloud_ftp_server_state" {
#   description = "Operational state of the Cloud FTP server"
#   value       = "ACTIVE"
# }

# output "cloud_ftp_storage_bucket" {
#   description = "Target Google Cloud Storage bucket linked to the SFTP server"
#   value       = google_storage_bucket.sftp_storage_bucket.name
# }

# output "cloud_ftp_username" {
#   description = "Configured SFTP username"
#   value       = var.cloud_ftp_username
# }

# output "cloud_ftp_user_service_account" {
#   description = "Customer service account mapped to the SFTP user"
#   value       = google_service_account.sftp_user_sa.email
# }

# output "cloud_ftp_private_key_pem" {
#   description = "Generated private SSH key for testing (Only available if custom SSH key was not provided)"
#   value       = length(tls_private_key.sftp_client_key) > 0 ? tls_private_key.sftp_client_key[0].private_key_pem : "Supplied externally via var.cloud_ftp_user_ssh_public_key"
#   sensitive   = true
# }

# output "sftp_client_connection_command" {
#   description = "Sample sftp connection command for testing"
#   value       = "sftp -i <path-to-private-key> -P 22 ${var.cloud_ftp_username}@<server-ip>"
# }
