# Kubernetes Cluster (AKS)
# This module creates an Azure Kubernetes Service cluster with node pools and monitoring

locals {
  # Route every Prometheus alert rule without an explicit action to day-2's action group.
  prometheus_alert_default_action = { action_group_id = azurerm_monitor_action_group.aks_alerts.id }

  prometheus_node_alert_rules = var.prometheus_node_alert_rules == null ? null : [
    for r in var.prometheus_node_alert_rules : merge(r, { action = r.action != null ? r.action : local.prometheus_alert_default_action })
  ]
  prometheus_cluster_alert_rules = var.prometheus_cluster_alert_rules == null ? null : [
    for r in var.prometheus_cluster_alert_rules : merge(r, { action = r.action != null ? r.action : local.prometheus_alert_default_action })
  ]
  prometheus_pod_alert_rules = var.prometheus_pod_alert_rules == null ? null : [
    for r in var.prometheus_pod_alert_rules : merge(r, { action = r.action != null ? r.action : local.prometheus_alert_default_action })
  ]
}

module "kubernetes_cluster" {
  source = "github.com/Unique-AG/terraform-modules.git//modules/azure-kubernetes-service?ref=73369958885f06c85f4561be024a1c543429f3cf" # azure-kubernetes-service-9.2.0

  kubernetes_version                      = var.kubernetes_version
  application_gateway_id                  = module.application_gateway.appgw_id
  segregated_node_and_pod_subnets_enabled = var.aks_segregated_node_and_pod_subnets_enabled
  private_cluster_enabled                 = var.aks_private_cluster_enabled
  # Authorized IP ranges exist only for a public API server, so they are dropped when the cluster is private.
  api_server_authorized_ip_ranges = var.aks_private_cluster_enabled ? null : var.aks_api_server_authorized_ip_ranges
  # Private-cluster-only settings: Azure rejects them on a public cluster (InvalidPrivateDNSZoneMode),
  # so send null/false when public. Private clusters keep the module defaults ("None" / true).
  private_dns_zone_id                   = var.aks_private_cluster_enabled ? "None" : null
  private_cluster_public_fqdn_enabled   = var.aks_private_cluster_enabled
  cluster_name                          = local.cluster_name
  node_rg_name                          = var.node_resource_group_name
  resource_group_location               = data.azurerm_resource_group.core.location
  resource_group_name                   = data.azurerm_resource_group.core.name
  default_subnet_nodes_id               = data.azurerm_subnet.aks_nodes.id
  default_subnet_pods_id                = data.azurerm_subnet.aks_pods.id
  tags                                  = var.tags
  tenant_id                             = data.azurerm_client_config.current.tenant_id
  defender_log_analytics_workspace_id   = data.azurerm_log_analytics_workspace.log_analytics.id
  prometheus_node_recording_rules       = var.prometheus_node_recording_rules
  prometheus_kubernetes_recording_rules = var.prometheus_kubernetes_recording_rules
  prometheus_ux_recording_rules         = var.prometheus_ux_recording_rules
  # Alert rules notify day-2's own action group (24-aks-action-group.tf). The module's action group is
  # disabled (email_receiver = null) because it would use the same name, "<cluster>-alerts", and collide.
  # alert_configuration must still be a non-null object: the module reads .email_receiver without a null check.
  prometheus_node_alert_rules    = local.prometheus_node_alert_rules
  prometheus_cluster_alert_rules = local.prometheus_cluster_alert_rules
  prometheus_pod_alert_rules     = local.prometheus_pod_alert_rules
  alert_configuration            = { email_receiver = null, action_group = null }

  # Same values as the 5.7.1 defaults; passing the object drops the module's min/max defaults.
  default_node_pool = {
    vm_size   = var.kubernetes_default_node_size
    zones     = var.kubernetes_default_node_zones
    min_count = 2
    max_count = 5
  }

  # 7.0.0+ turns Container Insights off and keeps one control-plane category by default; keep today's behaviour.
  data_plane_logs = { enabled = true }
  control_plane_logs = {
    categories = [
      "cloud-controller-manager",
      "cluster-autoscaler",
      "csi-azuredisk-controller",
      "csi-azurefile-controller",
      "csi-snapshot-controller",
      "kube-audit-admin",
      "kube-scheduler",
    ]
  }

  log_analytics_workspace = {
    id                  = data.azurerm_log_analytics_workspace.log_analytics.id
    location            = data.azurerm_resource_group.core.location
    resource_group_name = data.azurerm_resource_group.core.name
  }

  azure_prometheus_grafana_monitor = {
    azure_monitor_location = data.azurerm_resource_group.core.location
    azure_monitor_rg_name  = data.azurerm_resource_group.core.name
    enabled                = var.grafana_monitor_enabled
    grafana_major_version  = var.grafana_major_version
    identity = {
      type         = var.grafana_identity_type
      identity_ids = [data.azurerm_user_assigned_identity.grafana_identity.id]
    }
  }

  # Azure CNI powered by Cilium with Advanced Container Networking Services (ACNS). Conduct's sandbox
  # isolation relies on CiliumNetworkPolicy; switching the data plane re-images every node pool once.
  network_profile = {
    network_data_plane          = "cilium"
    network_policy              = "cilium"
    advanced_networking_enabled = true
    idle_timeout_in_minutes     = var.aks_network_profile_idle_timeout_in_minutes
    outbound_ip_address_ids     = [data.azurerm_public_ip.aks_public_ip.id]
  }

  node_pool_settings = {
    for k, v in var.kubernetes_node_pool_settings : k => {
      auto_scaling_enabled = v.auto_scaling_enabled
      max_count            = v.max_count
      min_count            = v.min_count
      mode                 = v.mode
      node_count           = v.node_count
      node_labels          = v.node_labels
      node_taints          = v.node_taints
      os_disk_size_gb      = v.os_disk_size_gb
      os_sku               = v.os_sku
      upgrade_settings     = v.upgrade_settings
      vm_size              = v.vm_size
      zones                = v.zones
    }
  }

  # Kata node pool for Conduct sandboxes. The module sets workload_runtime = KataVmIsolation, Azure Linux,
  # the label workload-runtime=kata and the taint workload-runtime=kata:NoSchedule on its own.
  kata_node_pool_settings = var.kubernetes_kata_enabled ? {
    kata = {
      auto_scaling_enabled = true
      max_count            = var.kubernetes_kata_max_count
      max_pods             = var.kubernetes_kata_max_pods
      min_count            = var.kubernetes_kata_min_count
      os_disk_size_gb      = 100
      vm_size              = var.kubernetes_kata_node_size
      zones                = var.kubernetes_kata_zones
      upgrade_settings = {
        max_surge                 = var.kubernetes_kata_max_surge
        drain_timeout_in_minutes  = var.kubernetes_kata_drain_timeout_in_minutes
        undrainable_node_behavior = var.kubernetes_kata_undrainable_node_behavior
      }
    }
  } : {}

  # Default activity-log alerts use this list; keeps aks_agent_pool_write_error actionable.
  default_action_group_ids = [azurerm_monitor_action_group.aks_alerts.id]
}
