output "cloud_ftp_server_id" {
  description = "Identifier of the provisioned Cloud FTP server"
  value       = google_storage_ftp_server.sftp_server.server_id
}

output "cloud_ftp_server_state" {
  description = "Operational state of the Cloud FTP server"
  value       = google_storage_ftp_server.sftp_server.state
}

output "cloud_ftp_server_ip_or_attachment" {
  description = "Connection endpoint: Public IP (for EXTERNAL) or PSC Service Attachment (for INTERNAL)"
  value = var.cloud_ftp_access_type == "EXTERNAL" ? (
    length(google_storage_ftp_server.sftp_server.external_config) > 0 ? google_storage_ftp_server.sftp_server.external_config[0].ip_address : "Provisioning"
    ) : (
    length(google_storage_ftp_server.sftp_server.internal_config) > 0 ? google_storage_ftp_server.sftp_server.internal_config[0].service_attachment : "Provisioning"
  )
}

output "cloud_ftp_storage_bucket" {
  description = "Target Google Cloud Storage bucket linked to the SFTP server"
  value       = google_storage_bucket.sftp_storage_bucket.name
}

output "cloud_ftp_username" {
  description = "Configured SFTP username"
  value       = google_storage_ftp_user.sftp_user.user_id
}

output "cloud_ftp_user_service_account" {
  description = "Customer service account mapped to the SFTP user"
  value       = google_service_account.sftp_user_sa.email
}

output "cloud_ftp_private_key_pem" {
  description = "Generated private SSH key for testing (Only available if custom SSH key was not provided)"
  value       = length(tls_private_key.sftp_client_key) > 0 ? tls_private_key.sftp_client_key[0].private_key_pem : "Supplied externally via var.cloud_ftp_user_ssh_public_key"
  sensitive   = true
}

output "sftp_client_connection_command" {
  description = "Sample sftp connection command for testing"
  value       = "sftp -i <path-to-private-key> -P 22 ${var.cloud_ftp_username}@<server-ip>"
}