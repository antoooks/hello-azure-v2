# Infrastructure Configuration

This directory contains the infrastructure Terraform configurations organized by deployment phase (day-1, day-2, day-3) and environment-specific variables.

## Structure

```
02_infrastructure/
├── day-1/          # Foundational infrastructure (resource groups, networking, managed identities, custom roles)
├── day-2/          # Identity/governance resources (Azure AD groups, application registration, federated credentials)
├── day-3/          # OPTIONAL: secure access resources (Azure Bastion host for secure RDP/SSH access)
├── environments/test/           # Test environment-specific variables
│   ├── 00-config-day-1.auto.tfvars      # Day-1 provider & backend configuration
│   ├── 00-config-day-2.auto.tfvars      # Day-2 provider & backend configuration
│   ├── 00-config-day-3.auto.tfvars      # Day-3 provider & backend configuration
│   ├── 00-parameters-day-1.auto.tfvars  # Day-1 environment-specific parameters
│   ├── 00-parameters-day-2.auto.tfvars  # Day-2 environment-specific parameters
│   ├── 00-parameters-day-3.auto.tfvars  # Day-3 environment-specific parameters
│   ├── prometheus-rules.auto.tfvars     # Prometheus alert and recording rules for day-2
│   ├── backend-config-day-1.hcl         # Backend config for day-1 terraform init
│   ├── backend-config-day-2.hcl         # Backend config for day-2 terraform init
│   └── backend-config-day-3.hcl         # Backend config for day-3 terraform init
```

## Usage

### Considerations When Using Terraform Cloud

In case of using Terraform Cloud, when creating Terraform Cloud workspace, you should take into account the following:
- Workspace execution mode should be configured for "Agent" instead of "Remote". Specifying the "Remote" execution mode instructs HCP Terraform to perform Terraform runs on its own disposable virtual machines, so "Agent" execution mode is requred for Terraform Cloud to have access to the Azure subscription.
- Workspace variables should be configured for the environment-specific variables and point to the correct backend configuration file f.e. `/environments/<env>/00-config-day-1.auto.tfvars` and `/environments/<env>/00-parameters-day-1.auto.tfvars` for both day-1 and day-2 respectively.
- You will probably need to remove use_oidc and client_id from the 91-providers.tf file as they are not needed for Terraform Cloud and add organization and workspaces block to the terraform block in the 90-backend.tf file.

### Initializing Terraform Backend

Each day-X configuration uses a **separate state file** to avoid conflicts. The backend configuration must be passed via `-backend-config` flags during `terraform init`.

**Day-1 Initialization:**
```bash
cd day-1
terraform init -backend-config=../environments/test/backend-config-day-1.hcl
```

**Day-2 Initialization:**
```bash
cd day-2
terraform init -backend-config=../environments/test/backend-config-day-2.hcl
```

**Day-3 Initialization:**
```bash
cd day-3
terraform init -backend-config=../environments/test/backend-config-day-3.hcl
```

**Note:** Each day-X has its own state file:
- day-1: `terraform-infra-v2-day-1.tfstate`
- day-2: `terraform-infra-v2-day-2.tfstate`
- day-3: `terraform-infra-v2-day-3.tfstate`

This ensures state isolation and prevents conflicts between different deployment phases.

### Running Terraform Plan/Apply

Use `-var-file` to load environment-specific variables. Each day-X has its own parameters file:

**Day-1 (Foundational Infrastructure):**
```bash
cd day-1
terraform plan \
  -var-file=../environments/test/00-config-day-1.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-1.auto.tfvars

terraform apply \
  -var-file=../environments/test/00-config-day-1.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-1.auto.tfvars
```

**Day-2 (Identity/Governance):**
```bash
cd day-2
terraform plan \
  -var-file=../environments/test/00-config-day-2.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-2.auto.tfvars \
  -var-file=../environments/test/prometheus-rules.auto.tfvars

terraform apply \
  -var-file=../environments/test/00-config-day-2.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-2.auto.tfvars \
  -var-file=../environments/test/prometheus-rules.auto.tfvars
```

**Day-3 (Secure Access - Azure Bastion), optional:** skip this unless you need Bastion. See [Day-3: Azure Bastion (optional)](#day-3-azure-bastion-optional).
```bash
cd day-3
terraform plan \
  -var-file=../environments/test/00-config-day-3.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-3.auto.tfvars

terraform apply \
  -var-file=../environments/test/00-config-day-3.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-3.auto.tfvars
```

**Important:** 
- Day-2 must be deployed **after** day-1, as it references resources created in day-1 using data sources (by name and resource group).
- Day-3 is **optional**. If you deploy it, deploy it **after** day-1, because it requires the VNET and AzureBastionSubnet created in day-1, as well as the Log Analytics workspace for diagnostics.

### Environment-Specific Files

- **00-config-day-1.auto.tfvars**: Contains day-1 provider and backend configuration (subscription_id, tenant_id, client_id, use_oidc, backend settings)
- **00-config-day-2.auto.tfvars**: Contains day-2 provider and backend configuration (subscription_id, tenant_id, client_id, use_oidc, backend settings)
- **00-config-day-3.auto.tfvars**: Contains day-3 provider and backend configuration (subscription_id, tenant_id, client_id, use_oidc, backend settings)
- **00-parameters-day-1.auto.tfvars**: Contains day-1 environment-specific parameters (resource names, locations, user IDs, etc.)
- **00-parameters-day-2.auto.tfvars**: Contains day-2 environment-specific parameters (references to day-1 resources by name)
- **00-parameters-day-3.auto.tfvars**: Contains day-3 environment-specific parameters (references to day-1 resources by name, bastion configuration)
- **prometheus-rules.auto.tfvars**: Contains Prometheus alert rules and recording rules for AKS monitoring (used by day-2). Must be passed explicitly via `-var-file` as it resides outside the day-2 working directory.
- **backend-config-day-1.hcl**: Backend configuration for day-1 terraform init (contains only backend settings, used with `-backend-config` flag)
- **backend-config-day-2.hcl**: Backend configuration for day-2 terraform init (contains only backend settings, used with `-backend-config` flag)
- **backend-config-day-3.hcl**: Backend configuration for day-3 terraform init (contains only backend settings, used with `-backend-config` flag)

> :warning: **`env` must be unique per sandbox and identical across day-1, day-2 and day-3.** Most resource names are built from `env`. Many of them must be unique across all of Azure (Key Vault, storage, ACR, Redis, Cognitive Services subdomains) and the custom roles across the tenant, so two sandboxes with the same `env` clash. Choose it before the first day-1 apply: changing it later replaces most resources. This `env` is separate from the day-0 `env`, which should stay unchanged. See [How `env` works in day-0 and day-N](../01_bootstrap/README.md#how-env-works-in-day-0-and-day-n-and-in-sandbox-subscriptions).

## Deployment Order

1. **day-1**: Deploy foundational infrastructure first
   - Creates resource groups, key vaults, networking (including AzureBastionSubnet), managed identities, Log Analytics workspace, etc.
   - State stored in: `terraform-infra-v2-day-1.tfstate`

2. **day-2**: Deploy identity/governance resources (depends on resources from day-1)
   - Uses data sources to look up day-1 resources by name and resource group
   - Creates Azure AD groups, application registrations, federated credentials
   - State stored in: `terraform-infra-v2-day-2.tfstate`

3. **day-3 (optional)**: Deploy secure access resources (depends on resources from day-1)
   - Nothing else depends on it: day-1, day-2, `03_applications` and the application deployment work without it. Deploy it only when you need Bastion. See [Day-3: Azure Bastion (optional)](#day-3-azure-bastion-optional).
   - Uses data sources to look up day-1 resources by name and resource group
   - Creates Azure Bastion host with Standard SKU, tunneling, and native client support
   - Configures diagnostic logging to Log Analytics workspace
   - State stored in: `terraform-infra-v2-day-3.tfstate`

## Cross-Day Dependencies

Day-2 does **not** use `terraform_remote_state` to reference day-1. Instead, it uses **data sources** to look up resources by name:

```hcl
# Day-2 looks up resources created in day-1
data "azurerm_key_vault" "key_vault_sensitive" {
  name                = var.key_vault_sensitive.name
  resource_group_name = var.key_vault_sensitive.resource_group_name
}

# Day-3 looks up resources created in day-1
data "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name_vnet
}

data "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name_vnet
}

data "azurerm_log_analytics_workspace" "this" {
  name                = local.log_analytics_workspace_name
  resource_group_name = var.resource_group_core_name
}
```

This approach provides:
- **Loose coupling**: Day-2 and Day-3 don't depend on day-1 state
- **Independent deployment**: Day-2 and Day-3 can be deployed once resources exist
- **Resilience**: Works even if day-1 state is lost/recreated

## Importing Existing Resources

If you have existing resources in Azure that need to be imported into Terraform state, use the import scripts. The import process is split across day-1, day-2, and day-3 to match the separate state files.
Please note that you need to initialize terraform state before running the import scripts.
e.g.

for test environment:
```bash
cd day-1
terraform init -backend-config=../environments/test/backend-config-day-1.hcl
cd day-2
terraform init -backend-config=../environments/test/backend-config-day-2.hcl
cd day-3
terraform init -backend-config=../environments/test/backend-config-day-3.hcl
```

## Import scripts:
- day-1/import_azure_resources.sh
- day-2/import_azure_resources.sh
- day-3/import_azure_resources.sh (if needed)

for test environment:
```bash
cd day-1
terraform init -backend-config=../environments/test/backend-config-day-1.hcl
./import_azure_resources.sh
```

```bash
cd day-2
terraform init -backend-config=../environments/test/backend-config-day-2.hcl
./import_azure_resources.sh
```

```bash
cd day-3
terraform init -backend-config=../environments/test/backend-config-day-3.hcl
# Import script would go here if needed
```

### Important Notes

- **Day-1 must be imported before day-2 and day-3**: Day-2 and Day-3 resources depend on resources created in day-1 (e.g., key vaults, resource groups, VNET, Log Analytics workspace)
- **Separate state files**: Each day-X uses its own state file:
  - Day-1: `terraform-infra-v2-day-1.tfstate`
  - Day-2: `terraform-infra-v2-day-2.tfstate`
  - Day-3: `terraform-infra-v2-day-3.tfstate`
- **Idempotent**: The import scripts will skip resources that are already in state
- **Expected drifts**: After import, running `terraform plan` will show cosmetic drifts (API version differences, module-internal changes). These are safe and documented in the script output

## Day-3: Azure Bastion (optional)

Day-3 deploys Azure Bastion, a fully managed PaaS service that provides secure RDP/SSH connectivity to your virtual machines directly through the Azure Portal without exposing them to the internet.

> :information_source: **Day-3 is optional.** No other stage depends on it. Day-1 and day-2 do not reference any day-3 resource or output, and the Helm values in `03_applications` do not use Bastion. In CI, `test.infrastructure.tf.plan.yaml` only runs `terraform plan` for day-3. It is never applied automatically.

### When you need it

- You need SSH or RDP access to machines in the VNet that have no public IP, for example a jumpbox to reach the private endpoints (PostgreSQL, Redis, Key Vault, storage) from inside the network.
- You want a tunnel into the VNet with `az network bastion ssh` or `az network bastion tunnel`.

You do **not** need it to use the deployed applications, which are published through the Application Gateway.

**Reaching the AKS API (`kubectl`, `helm`):** the AKS cluster is **private**. The `azure-kubernetes-service` module defaults to `private_cluster_enabled = true`, and day-2 does not override it. Its API server is only reachable from inside the VNet, so `kubectl` from a laptop does not work directly. Use one of these instead:

| Option | Needs day-3? | Notes |
|---|---|---|
| `az aks command invoke -g resource-group-core -n aks-<env> --command "kubectl get pods -A"` | No | Runs the command in the cluster through the Azure API. Good for occasional commands. Use `--file` to send manifests or values files. |
| GitHub runners inside the VNet (`gh-test`) | No | This is how CI reaches the cluster: the workflows run on the `ha.uq.test` runner group. Requires the GitHub organization setup described under `gh-test`. |
| Bastion (day-3) + a jumpbox VM in the VNet | Yes | For interactive work. This repository does not create the jumpbox VM. See [Connecting to AKS via Azure Bastion](#usage-example-connecting-to-aks-via-azure-bastion). |

### Cost

Bastion with the Standard SKU, which `00-parameters-day-3.auto.tfvars` sets, is billed **per hour for as long as it exists, whether or not anyone uses it**, plus its Standard public IP. It is one of the more expensive items in this setup. In sandbox subscriptions, deploy it only when you need it and destroy it afterwards.

### Skipping, adding and removing it

- **To skip it:** do not run `terraform init` or `terraform apply` in `day-3`.
- **Keep the empty `AzureBastionSubnet` that day-1 creates.** An empty subnet costs nothing, and day-3 needs it if you deploy Bastion later. You can remove it from `day-1/02-locals.tf` (`snet-bastion`) if you never want Bastion, but that requires another day-1 apply.
- **To add it later:** run `terraform init` and `terraform apply` in `day-3`, using the commands in [Running Terraform Plan/Apply](#running-terraform-planapply).
- **To remove it:** run `terraform destroy` in `day-3` with the same var files. This only removes the Bastion host, its public IP, its NSG and the diagnostic setting, and leaves everything else alone.

### Features

- **Standard SKU**: Required for production use and native client support
- **Tunneling Enabled**: Allows kubectl port forwarding and secure port forwarding to other services
- **Native Client Support (IP Connect)**: Enables direct SSH/RDP connections from native clients without browser
- **Diagnostic Logging**: All connection attempts and sessions are logged to Log Analytics workspace for audit and security monitoring
- **Azure RBAC**: Access control is managed through Azure RBAC roles (Azure Bastion Reader, Azure Bastion Contributor)

### Security Considerations

- **NSG on AzureBastionSubnet**: day-3 creates the Bastion NSG and attaches it to the subnet (`day-3/33-bastion-nsg.tf`). day-1 ignores the subnet's `networkSecurityGroup`, so a day-1 apply does not detach it. Use Azure RBAC for access control.
- **Subnet Requirements**: The subnet must be named exactly `AzureBastionSubnet` (case-sensitive) and be at least `/26` in size (64 IP addresses).
- **Public IP**: Standard SKU public IP is required for Standard Bastion SKU.

### Prerequisites

- Day-1 must be deployed first, as it creates:
  - The VNET with AzureBastionSubnet
  - Resource groups
  - Log Analytics workspace for diagnostics

### Usage Example: Connecting to AKS via Azure Bastion

Azure Bastion provides secure access to resources in your VNET, including the ability to run `kubectl` commands against your AKS cluster. The most common approach is to use a jumpbox VM, but port forwarding is also possible.

#### Prerequisites for kubectl Access

1. **Azure CLI** installed and authenticated:
   ```bash
   az login
   ```

2. **Azure Bastion** deployed (day-3) with tunneling enabled

3. **AKS cluster** deployed and accessible from within the VNET

4. **Jumpbox VM** (optional but recommended) - A Linux VM in the same VNET as your AKS cluster

#### Method 1: Using a Jumpbox VM (Recommended)

This is the simplest and most common approach. Connect to a jumpbox VM via Azure Bastion and run kubectl commands directly from the VM.

1. **Connect to your jumpbox VM via Azure Bastion**:
   
   **Via Azure Portal**:
   - Navigate to your VM in the Azure Portal
   - Click "Connect" → "Bastion"
   - Enter your credentials and connect
   
   **Via Azure CLI** (if native client support is enabled):
   ```bash
   az network bastion ssh \
     --name bastion-ha-test \
     --resource-group resource-group-core \
     --target-resource-id <VM_RESOURCE_ID> \
     --auth-type password \
     --username azureuser
   ```

2. **Install kubectl and Azure CLI on the VM** (if not already installed):
   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Install kubectl
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/
   ```

3. **Authenticate with Azure** (on the VM):
   ```bash
   az login
   ```

4. **Get AKS cluster credentials**:
   ```bash
   # For test environment
   az aks get-credentials \
     --resource-group resource-group-core \
     --name aks-test \
     --admin
   ```

5. **Run kubectl commands**:
   ```bash
   kubectl get nodes
   ```

#### Method 2: Port Forwarding via Azure Bastion (Advanced)

If you need to run kubectl from your local machine, you can set up port forwarding through Azure Bastion. This requires a VM in the VNET to act as a jump host.

1. **Get the AKS cluster credentials** (on your local machine):
   ```bash
   az aks get-credentials \
     --resource-group resource-group-core \
     --name aks-test \
     --admin
   ```

2. **Get the AKS API server address**:
   ```bash
   AKS_API_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||')
   echo "AKS API Server: ${AKS_API_SERVER}"
   ```

3. **Set up port forwarding through a VM via Azure Bastion**:
   ```bash
   # Connect to VM via Bastion and set up port forwarding
   az network bastion ssh \
     --name bastion-ha-test \
     --resource-group resource-group-core \
     --target-resource-id <VM_RESOURCE_ID> \
     --auth-type password \
     --username azureuser \
     --ssh-command "ssh -L 8443:${AKS_API_SERVER}:443 -N localhost"
   ```

4. **Update kubeconfig to use the tunnel**:
   ```bash
   kubectl config set-cluster $(kubectl config current-context) \
     --server https://127.0.0.1:8443 \
     --insecure-skip-tls-verify=true
   ```

5. **Run kubectl commands**:
   ```bash
   kubectl get nodes
   ```

#### Important Notes

- The SSH tunnel must remain active while using kubectl. Keep the terminal session open.
- Replace `bastion-ha-test` with your actual bastion name (format: `{bastion_name}-{name_prefix}-{env}`)
- Replace `aks-test` with your actual cluster name (format: `{cluster_name}-{env}`)
- The `--insecure-skip-tls-verify` flag is used for the tunnel; the actual connection to AKS is still secure through Bastion
- For production, consider using Azure RBAC integration with AKS for better security
- Ensure your user has the necessary Azure RBAC permissions: `Azure Bastion Reader` role to connect, and appropriate AKS permissions to access the cluster

## GitOps (Argo CD) RBAC after Entra app-registration v4

`azure-entra-app-registration` **4.0.0** removes the legacy Entra app role **`maintain`** (`value = maintain`). GitOps maintainers are assigned **`application_support`** via `application_support_object_ids` in `02_infrastructure/day-2/11-application-registration.tf`.

Argo CD OIDC is configured with `scopes: '[roles]'`. The Casbin group binding in `03_applications/test/values/argo/argo.yaml` must map the **new** role claim:

```yaml
g, application_support, role:admin
```

Do **not** leave `g, maintain, role:admin` after the Entra module bump — maintainers will authenticate but lose Argo admin until Helm values are synced.

Typical day-2 plan after the bump (if v4 roles are already in state): **1 in-place WAF policy update**, **6 destroys** of legacy `maintainers` Entra resources, **0 adds**. Apply Terraform, then sync the Argo application so RBAC picks up the YAML change.

The generic module was later deleted from terraform-modules; the app now comes from its successor `azure-entra-app-registration-argocd` (2.2.0). The `application_support` role mapping above is unchanged, admin consent stays off (`admin_consent_enabled = false`), and the `explicit_*` inputs keep the Key Vault secret names Argo CD reads.

Since 2.2.0 the module keeps two overlapping client secrets (`<display name>-YYYYMMDD`) and creates a new one every 12 months on the next apply; Key Vault always serves the current one. When a secret is replaced, new Argo CD SSO logins can fail for a few minutes until the CSI driver re-syncs the Key Vault secret and `argocd-server` reloads it (restart the `keeper` pod, then `argocd-server`, if it takes longer).

