run "verify_gcp_identity" {
  command = plan

  assert {
    condition     = data.google_client_config.current.project != ""
    error_message = "GCP client config should return a project ID"
  }

  assert {
    condition     = data.google_client_config.current.access_token != ""
    error_message = "GCP client config should return an access token"
  }
}

run "verify_gcp_write_permission" {
  command = apply

  assert {
    condition     = google_project_iam_custom_role.test_write_permission.id != ""
    error_message = "Custom IAM role should be created with a valid ID"
  }

  assert {
    condition     = can(regex("^projects/.+/roles/", google_project_iam_custom_role.test_write_permission.id))
    error_message = "Role ID should be a valid GCP IAM role path"
  }
}
