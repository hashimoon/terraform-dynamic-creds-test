output "project" {
  description = "The GCP project ID"
  value       = data.google_client_config.current.project
}

output "access_token_set" {
  description = "Whether an access token was obtained"
  value       = data.google_client_config.current.access_token != ""
}

output "test_role_id" {
  description = "ID of the test custom role (verifies write permissions)"
  value       = google_project_iam_custom_role.test_write_permission.id
}
