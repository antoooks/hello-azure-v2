# Day-2 specific parameters
env = "anto"

# Network configuration
subnet_agw_cidr = "10.202.3.0/28"

# AKS API server access
#   aks_private_cluster_enabled = true  -> private: reachable only from inside the VNet; the IP list below is ignored
#   aks_private_cluster_enabled = false -> public: reachable only from the IPs below (at least one is required)
# Get your IP with: curl -s -4 ifconfig.me
# WARNING: switching aks_private_cluster_enabled replaces (destroys and recreates) the cluster.
# Changing only the IP list updates the cluster in place.
aks_private_cluster_enabled         = false
aks_api_server_authorized_ip_ranges = ["116.86.198.35/32"]

# Application Gateway configuration
# Use explicit name to preserve existing gateway IP configuration name and avoid replacement
# Existing name is "ha-test-gwip", but default would be "gateway-ip-configuration"
application_gateway_gateway_ip_configuration_name = "ha-test-gwip"

# Budget configuration
budget_contact_emails = ["kurnianto.trilaksono@unique.ai"]

# Key Vault configuration
kv_sku = "premium"

# Terraform Service Principal (created in day-0/bootstrap)
# To get the object_id, run: az ad sp list --display-name "terraform" --query "[].{objectId:id,displayName:displayName}" -o table, or go to Azure Portal -> Enterprise Applications -> Terraform -> Object ID
# terraform_service_principal_object_id = "b5016fe4-421b-4dd3-bc65-c9abf3dfad8b"  # unused: Option A runs Terraform as the logged-in user

# Kubelet Identity Object ID (from AKS cluster)
# To get the object_id, run: az aks show -n aks-test -g resource-group-core --query 'identityProfile.kubeletidentity.objectId' -o tsv
# This is set explicitly to avoid drift when the AKS cluster data source returns a different value
# kubelet_identity_object_id = "776cc853-f337-48a2-a934-42fe4f342f7b"  # upstream value; null = use the cluster day-2 creates

# AKS Cluster ID (for role assignment scopes)
# To get the ID, run: az aks show -n aks-test -g resource-group-core --query 'id' -o tsv
# aks_cluster_id = "/subscriptions/782871a0-bcee-44fb-851f-ccd3e69ada2a/resourceGroups/resource-group-core/providers/Microsoft.ContainerService/managedClusters/aks-test"  # upstream value; null = use the cluster day-2 creates

# CSI Identity Object ID (Key Vault Secrets Provider identity from AKS cluster)
# To get the object_id, run: az aks show -n aks-test -g resource-group-core --query 'addonProfiles.azureKeyvaultSecretsProvider.identity.objectId' -o tsv
# csi_identity_object_id = "8f6d5aff-a056-4073-8b99-0dfdbe5e25dd"  # upstream value; null = use the cluster day-2 creates

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

# User permissions
cluster_admin_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]

keyvault_secret_writer_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]

telemetry_observer_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]

# Resource Group Names (created in day-0)
resource_group_core_name      = "resource-group-core"
resource_group_sensitive_name = "resource-group-sensitive"
resource_group_name_vnet      = "rg-vnet-002"

# Key Vaults, AKS, and DNS Zone objects are computed in locals from var.env
main_kv_name      = "hakv1"
sensitive_kv_name = "hakv2"

# DNS Zone
dns_zone_name = "sb-trilaksono-001.unique.dev"

# Entra ID objects: off in this sandbox. The deploying user cannot create groups or app registrations
# (403 Authorization_RequestDenied), and Argo CD does not use Entra ID (OIDC) login here.
# [ARGOCD-OIDC] gitops_app_registration_enabled is the OIDC switch. Keep it in line with argoAuth in
# 03_applications/argo-bootstrap.yaml.gotmpl (admin = false is fine, oidc needs true).
entra_groups_enabled            = false
gitops_app_registration_enabled = false

# [ARGOCD-OIDC] Application Registration (only used when gitops_app_registration_enabled = true)
application_registration_gitops_display_name = "GitOps-anto"

# User permissions
# [ARGOCD-OIDC] Only used by the OIDC app registration; no effect while gitops_app_registration_enabled = false.
gitops_maintainer_user_ids = [
  "8182113a-0dda-426d-9402-c317c71ae1c8",
]

# Azure AD Groups (tenant-wide: suffixed with env so sandboxes in the same tenant don't create same-named groups)
telemetry_observer_group_display_name          = "Telemetry Observer-anto"
sensitive_data_observer_group_display_name     = "Sensitive Data Observer-anto"
devops_group_display_name                      = "DevOps-anto"
emergency_admin_group_display_name             = "Emergency Admin-anto"
admin_kubernetes_cluster_group_display_name    = "Admin Kubernetes Cluster-anto"
main_keyvault_secret_writer_group_display_name = "Main KeyVault writer-anto"

# Audit storage account (globally unique; default "helloazureaudit" is taken and not derived from env)
audit_storage_sa_name = "helloazureauditanto"

# Federated Identity Credentials
cluster_workload_identities = {
  "backend-service-chat" = {
    name      = "backend-service-chat"
    namespace = "unique"
  }
  "backend-service-ingestion-worker-chat" = {
    name      = "backend-service-ingestion-worker-chat"
    namespace = "unique"
  }
  "backend-service-ingestion-worker" = {
    name      = "backend-service-ingestion-worker"
    namespace = "unique"
  }
  "backend-service-ingestion" = {
    name      = "backend-service-ingestion"
    namespace = "unique"
  }
  "assistants-core" = {
    name      = "assistants-core"
    namespace = "unique"
  }
  "backend-service-speech" = {
    name      = "backend-service-speech"
    namespace = "unique"
  }
}

# OpenAI Cognitive Accounts
openai_cognitive_accounts = {
  "cognitive-account-swedencentral" = {
    name                            = "cognitive-account-swedencentral"
    location                        = "swedencentral"
    local_auth_enabled              = false
    custom_subdomain_name           = "hello-azure-unique"
    openai_private_endpoint_enabled = false
    public_network_access_enabled   = true
    cognitive_deployments = [
      {
        name          = "text-embedding-ada-002"
        model_name    = "text-embedding-ada-002"
        model_version = "2"
        sku_name      = null
        sku_capacity  = 350
      },
      {
        name          = "gpt-4o-2024-11-20"
        model_name    = "gpt-4o"
        model_version = "2024-11-20"
        sku_name      = "Standard"
        sku_capacity  = 50
      },
      {
        name          = "gpt-5-2025-08-07"
        model_name    = "gpt-5"
        model_version = "2025-08-07"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-5.1-2025-11-13"
        model_name    = "gpt-5.1"
        model_version = "2025-11-13"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-5.5-2026-04-24"
        model_name    = "gpt-5.5"
        model_version = "2026-04-24"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-5.6-sol-2026-07-09"
        model_name    = "gpt-5.6-sol"
        model_version = "2026-07-09"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-5.6-terra-2026-07-09"
        model_name    = "gpt-5.6-terra"
        model_version = "2026-07-09"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-5.6-luna-2026-07-09"
        model_name    = "gpt-5.6-luna"
        model_version = "2026-07-09"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-6-luna-2026-09-22"
        model_name    = "gpt-6-luna"
        model_version = "2026-09-22"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      },
      {
        name          = "gpt-6-sol-2026-09-22"
        model_name    = "gpt-6-sol"
        model_version = "2026-09-22"
        sku_name      = "DataZoneStandard"
        sku_capacity  = 1000
      }
    ]
  }
}

# OpenAI Document Intelligence Accounts
document_intelligence_accounts = {
  "swedencentral-form-recognizer" = {
    location                      = "swedencentral"
    custom_subdomain_name         = "di-hello-azure-unique"
    public_network_access_enabled = true
    local_auth_enabled            = true
  }
}

# OpenAI Speech Service
speech_service_name = "speech-service"
speech_service_accounts = {
  "swedencentral-speech" = {
    location              = "swedencentral"
    account_kind          = "SpeechServices"
    account_sku_name      = "S0"
    custom_subdomain_name = "ss-hello-azure-anto" # globally unique; not derived from env
    private_endpoint      = true
  }
}

# DNS Zones 
dns_zones = {
  name_client_consented = "client-consented.sb-trilaksono-001.unique.dev"
  resource_group_name   = "rg-vnet-002"
  private_zones = {
    cognitive_services = {
      name = "privatelink.cognitiveservices.azure.com"
    }
    aoi = {
      name = "privatelink.openai.azure.com"
    }
    storage = {
      name = "privatelink.blob.core.windows.net"
    }
    psql = {
      name = "privatelink.postgres.database.azure.com"
    }
    redis = {
      name = "privatelink.redis.cache.windows.net"
    }
  }

}

# Secrets
rabbitmq_password_chat_secret_name        = "rabbitmq-password-chat"
zitadel_db_user_password_secret_name      = "zitadel-db-user-password"
zitadel_master_key_secret_name            = "zitadel-master-key"
encryption_key_app_repository_secret_name = "encryption-key-app-repository"
encryption_key_node_chat_lxm_secret_name  = "encryption-key-chat-lxm"
encryption_key_ingestion_secret_name      = "encryption-key-ingestion"
zitadel_pat_secret_name                   = "manual-zitadel-scope-mgmt-pat"

# Secret Generation Configuration
secret_password_length        = 32
rabbitmq_password_chat_length = 24
secret_expiration_date        = "2099-12-31T23:59:59Z"

# Kubernetes Configuration
kubernetes_node_pool_settings = {
  rapid = {
    max_count   = 3
    min_count   = 0
    node_count  = 0
    node_taints = ["scalability=rapid:NoSchedule", "lifecycle=ephemeral:NoSchedule"]
    node_labels = {
      lifecycle   = "ephemeral"
      scalability = "rapid"
    }
    vm_size = "Standard_D8s_v5" # Dsv4 is not offered in swedencentral (AvailabilityZoneNotSupported); same 8 vCPU / 32 GiB
  },
  steady = {
    max_count   = 4
    min_count   = 0
    node_count  = 2
    node_taints = []
    node_labels = {
      lifecycle   = "persistent"
      scalability = "steady"
    }
    upgrade_settings = {
      max_surge = "30%"
    }
    vm_size = "Standard_D8as_v5"
  }
}
