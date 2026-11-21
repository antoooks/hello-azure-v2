# Environment-specific configuration
env = "anto"

# VNET configuration
vnet_name          = "vnet-001"
vnet_address_space = ["10.202.0.0/22"]

# Network configuration - VNET subnet CIDRs
subnet_aks_pods_name  = "snet-aks-pods"
subnet_aks_pods_cidr  = "10.202.0.0/23"
subnet_aks_nodes_name = "snet-aks-nodes"
subnet_aks_nodes_cidr = "10.202.2.0/24"
subnet_agw_name       = "snet-application-gateway"
subnet_agw_cidr       = "10.202.3.0/28"
subnet_cognitive_name = "snet-cognitive-services"
subnet_cognitive_cidr = "10.202.3.16/28"
subnet_kv_name        = "snet-key-vault"
subnet_kv_cidr        = "10.202.3.32/28"
subnet_psql_name      = "snet-postgres"
subnet_psql_cidr      = "10.202.3.48/28"
subnet_redis_name     = "snet-redis"
subnet_redis_cidr     = "10.202.3.64/28"
subnet_storage_name   = "snet-storage"
subnet_storage_cidr   = "10.202.3.80/28"
subnet_github_name    = "snet-github-runners"
subnet_github_cidr    = "10.202.3.96/28"
bastion_subnet_cidr   = "10.202.3.128/26"

# Budget configuration
budget_contact_emails = ["kurnianto.trilaksono@unique.ai"]

# Key Vault configuration
kv_sku = "premium"

# GitOps configuration
gitops_display_name = "GitOps"

# DNS subdomain records
dns_subdomain_records = {
  api = {
    name    = "api"
    records = [] # Will be populated dynamically
  }
  argo = {
    name    = "argo"
    records = [] # Will be populated dynamically
  }
  zitadel = {
    name    = "id"
    records = [] # Will be populated dynamically
  }
  reflector = {
    name    = "reflector"
    records = [] # Will be populated dynamically
  }
}

# Tags
tags = {
  app = "hello-azure"
}

# Resource locations
resource_audit_location           = "swedencentral"
resource_group_core_location      = "swedencentral"
resource_group_sensitive_location = "swedencentral"
resource_vnet_location            = "swedencentral"

# Resource Group IDs (will be set after resource groups are created)
resource_group_vnet_id = "" # Will be set to azurerm_resource_group.vnet.id after creation

# User permissions
cluster_admin_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]
gitops_maintainer_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]
# Empty: you already get Secrets/Crypto Officer on both vaults as the identity running Terraform
# (38-role-assignments.tf); listing yourself here too would create duplicate role assignments.
keyvault_secret_writer_user_ids = []
telemetry_observer_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]

# Speech Service configuration (private DNS zone name is not environment-specific)
speech_service_private_dns_zone_virtual_network_link_name = "speech-service-private-dns-zone-vnet-link-test"
azurerm_private_dns_zone_virtual_network_link_name        = "PsqlVnetZone.com"

# DNS Zone (created in day-1)
dns_zone_name = "sb-trilaksono-001.unique.dev"

# Application Registration
application_registration_gitops_display_name = "GitOps-anto"

# Terraform Service Principal (same as day-2)
# terraform_service_principal_object_id = "b5016fe4-421b-4dd3-bc65-c9abf3dfad8b"  # unused: Option A runs Terraform as the logged-in user
