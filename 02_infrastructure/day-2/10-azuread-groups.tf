# Azure AD Groups
# These groups are used for role-based access control (RBAC)
# Set entra_groups_enabled = false where you cannot create Entra ID groups (e.g. a sandbox without Groups Administrator).

resource "azuread_group" "telemetry_observer" {
  count            = var.entra_groups_enabled ? 1 : 0
  display_name     = var.telemetry_observer_group_display_name
  security_enabled = true
}

resource "azuread_group" "sensitive_data_observer" {
  count            = var.entra_groups_enabled ? 1 : 0
  display_name     = var.sensitive_data_observer_group_display_name
  security_enabled = true
}

resource "azuread_group" "devops" {
  count            = var.entra_groups_enabled ? 1 : 0
  display_name     = var.devops_group_display_name
  security_enabled = true
}

resource "azuread_group" "emergency_admin" {
  count            = var.entra_groups_enabled ? 1 : 0
  display_name     = var.emergency_admin_group_display_name
  security_enabled = true
}

resource "azuread_group" "admin_kubernetes_cluster" {
  count            = var.entra_groups_enabled ? 1 : 0
  display_name     = var.admin_kubernetes_cluster_group_display_name
  security_enabled = true
}

resource "azuread_group" "main_keyvault_secret_writer" {
  count            = var.entra_groups_enabled ? 1 : 0
  display_name     = var.main_keyvault_secret_writer_group_display_name
  security_enabled = true
}

