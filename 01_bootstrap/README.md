# Bootstrap Configuration

This directory contains the bootstrap Terraform configuration for initializing the tenant and setting up the remote Terraform state storage. This is the foundational step (day-0) that must be completed before deploying infrastructure.

## Structure

```
01_bootstrap/
├── day-0/          # Shared Terraform code (resource groups, storage account, Azure AD application, federated credentials, service principals, role assignments)
└── environments/   # Environment-specific variables
    └── test/       # Test environment-specific variables
        ├── 00-config.auto.tfvars           # Provider configuration (subscription_id, tenant_id, client_id, use_oidc)
        ├── 00-parameters.auto.tfvars       # Environment-specific parameters
        └── backend-config-day-0.hcl        # Backend config for day-0 state file
```

## What is the purpose of this step

> :information_source: **Note:** In this step, a remote Terraform state is being set up in Azure. This setup may not align with your specific requirements, so be prepared to make any necessary adjustments.

This step will allow us to automate all the further deployments. In a high overview, in this init the following are created:
- Storage account for Terraform state (`tfstate`)
- Azure Application
- [Federated credentials](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-apps-methods-azp) that will allow Terraform to [authenticate to Azure using a Service Principal with Open ID Connect](https://registry.terraform.io/providers/hashicorp/Azurerm/latest/docs/guides/service_principal_oidc). It allows GitHub Actions workflows running in this repository's GitHub environments (`00-init`, `10-pm`, `20-wl`) to deploy and manage resources for this subscription. [More about Federated identity credentials](https://learn.microsoft.com/en-us/graph/api/resources/federatedidentitycredentials-overview?view=graph-rest-1.0)
- Service principal and role mapping

With this setup, GitHub Actions workflows running in the `00-init`, `10-pm` and `20-wl` GitHub environments have the right to access the tenant with `Contributor` role without defining any credentials in the repository. The OIDC token (JWT) that is created in the GitHub actions will be exchanged for an Azure access token. Only tokens issued for those environments will be allowed to be exchanged based on the [subject of the generated token](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect#filtering-for-a-specific-environment)

E.g.:
```
resource "azuread_application_federated_identity_credential" "github_actions_terraform" {
  ...
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:Unique-AG/hello-azure-v2:environment:20-wl"
}
```

## Prerequisites

Before proceeding, ensure you have the following:
- Tenant
- Subscription
- Terraform `>= 1.5` and the Azure CLI (`az login --tenant <TENANT_ID>`)
- Admin rights on the GitHub repository, to create the `00-init`, `10-pm` and `20-wl` environments

### Required permissions

Two identities run the Terraform code, and they need different permissions:

1. **The bootstrap operator**: the person who runs `day-0` once from their machine.
2. **The Terraform identity**: the `Terraform` app registration that `day-0` creates. GitHub Actions uses it, through OIDC, to run `02_infrastructure` (`day-1`, `day-2`, `day-3`, `gh-test`).

#### 1. Bootstrap operator (`01_bootstrap/day-0`)

| Scope | Permission | Needed for |
|---|---|---|
| Azure RBAC, subscription | `Owner` | Creating the state resource group and storage account. Assigning `Owner` and `User Access Administrator` to the Terraform identity (`60-role-assignments.tf`). |
| Entra ID role | `Application Developer`, or the tenant setting *Users can register applications* | Creating the `Terraform` app registration and its service principal (`30-`, `50-service-principals.tf`). Adding federated credentials to it (`40-federated-credentials.tf`). |
| Entra ID role | `Cloud Application Administrator` or `Application Administrator` | Adopting the built-in Microsoft Graph service principal (`azuread_service_principal.msgraph` in `50-service-principals.tf`) |
| Entra ID role | `Privileged Role Administrator` | Granting Microsoft Graph **application** permissions to the Terraform identity (`70-app-role-assignments.tf`) |

> **Shortcut:** `Global Administrator` + subscription `Owner` covers everything above.
> Without the Entra ID roles, `day-0` fails with `403 Authorization_RequestDenied` on `azuread_application_registration.terraform`.

#### 2. Terraform identity (`02_infrastructure`)

`day-0` grants all of these. The table lists why each one is needed.

**Azure RBAC**

| Scope | Permission | Needed for |
|---|---|---|
| Subscription | `Owner` (+ `User Access Administrator`) | Creating all resources. Managing access, which `Contributor` cannot do: 6 custom role definitions (`day-1/22-custom-roles.tf`), around 35 role assignments (`day-1`, `day-2`, and modules), and the PostgreSQL management lock (`azure-postgresql` module). Registering resource providers: `Microsoft.Dashboard`, `Microsoft.Monitor`, `Microsoft.AlertsManagement`, `GitHub.Network`. |
| Both Key Vaults (data plane) | `Key Vault Crypto Officer`, `Key Vault Secrets Officer`, `Key Vault Data Access Administrator` | Writing secrets and customer-managed keys in `day-2` (PostgreSQL, Redis, OpenAI, Speech, Document Intelligence, storage, ArgoCD app). The identity grants these roles to itself in `day-1/38-role-assignments.tf`, based on `terraform_service_principal_object_id`. |

**Microsoft Graph application permissions**

| Permission | Needed for |
|---|---|
| `User.Read.All` | `data "azuread_user"` lookups in `day-1` and `day-2` (GitOps maintainers, Key Vault writers, telemetry observers) |
| `Group.ReadWrite.All` | Creating the 6 security groups in `day-2/10-azuread-groups.tf` |
| `Application.ReadWrite.All` | Creating the ArgoCD app registration in `day-2/11-application-registration.tf`, with its service principal, app roles, client secret and user role assignments. Also used for `data "azuread_service_principal"` lookups. |
| `RoleManagement.ReadWrite.Directory` | Granted by `day-0`, but no resource in this repository uses it at the moment (there are no Entra ID directory role assignments). This permission effectively equals Global Administrator, so consider removing it. |

> **Not granted:** `DelegatedPermissionGrant.ReadWrite.All`. For that reason `day-2` sets `admin_consent_enabled = false`. After `day-2`, an admin must grant consent manually for the ArgoCD app's delegated Microsoft Graph scopes (`openid`, `profile`, `email`, `User.Read`). Do this under *Enterprise applications → \<app\> → Permissions*.

#### Other requirements

- **`gh-test`**: a GitHub organization admin must set up Azure private networking for hosted runners and provide `github_org_id`. The `GitHub.Network/networkSettings` resource links to that GitHub organization.

#### Running everything locally instead of through GitHub Actions

If you skip the Terraform identity and run all stages as your own user, that user needs the union of both tables:
- Subscription `Owner`.
- Entra ID roles that can create security groups and app registrations and assign users to app roles. `Groups Administrator` + `Cloud Application Administrator` is enough.

Reading users needs no extra role, because member users can read the directory by default. `day-1` and `day-2` look up the Terraform identity with `data "azuread_service_principal"` (`terraform_service_principal_object_id`). Change that code to target your user, or the Key Vault data-plane roles will not be assigned.

# Usage


## Manual actions

The process consists of 2 phases - (1) initialization with local state file and (2) migrating the local state file to remote storage

### Phase 1: Initial Setup with Local State

First Terraform has to be run with local state file, since there is no remote storage for the state. For this, you need to temporarily modify `day-0/90-backend.tf` to use local backend:

```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }

  # backend "azurerm" {
  #   # The backend configuration gets loaded from backend-config-day-0.hcl
  # }
}
```

Login manually to your tenant:
```bash
az login --tenant <<TENANT_ID>>
```

Navigate to day-0 and apply the Terraform changes:
```bash
cd day-0
terraform init
terraform apply \
  -var-file=../environments/test/00-config-day-0.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-0.auto.tfvars
```

Next, populate the `client_id` in the environment's `00-config.auto.tfvars` from the newly created application:
```bash
# Test environment example
cd day-0
var_value=$(terraform output client_id)
# MacOS
sed -i '' "s/\(client_id.*=\s*\).*/\1 $var_value/" ../environments/test/00-config-day-0.auto.tfvars
sed -i '' "s/\(client_id.*=\s*\).*/\1 $var_value/" ../../02_infrastructure/environments/test/00-config-day-1.auto.tfvars
sed -i '' "s/\(client_id.*=\s*\).*/\1 $var_value/" ../../02_infrastructure/environments/test/00-config-day-2.auto.tfvars
# Linux
sed -i "s/\(client_id.*=\s*\).*/\1 $var_value/" ../environments/test/00-config-day-0.auto.tfvars
sed -i "s/\(client_id.*=\s*\).*/\1 $var_value/" ../../02_infrastructure/environments/test/00-config-day-1.auto.tfvars
sed -i "s/\(client_id.*=\s*\).*/\1 $var_value/" ../../02_infrastructure/environments/test/00-config-day-2.auto.tfvars
# Windows
sed -i "s/\(client_id.*=\s*\).*/\1 $var_value/" ../environments/test/00-config-day-0.auto.tfvars
sed -i "s/\(client_id.*=\s*\).*/\1 $var_value/" ../../02_infrastructure/environments/test/00-config-day-1.auto.tfvars
sed -i "s/\(client_id.*=\s*\).*/\1 $var_value/" ../../02_infrastructure/environments/test/00-config-day-2.auto.tfvars
```

**Note:** The `client_id` must be consistent across all environment config files (day-0, day-1, and day-2) as they all authenticate using the same Azure AD Application created during bootstrap.

### Phase 2: Migrate to Remote State

Switch back to the `azurerm` backend in `day-0/90-backend.tf`:
```hcl
terraform {
  # backend "local" {
  #   path = "terraform.tfstate"
  # }

  backend "azurerm" {
    # The backend configuration gets loaded from backend-config-day-0.hcl
    # When running Terraform in GitHub Actions, the provider will detect the ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN environment variables set by the GitHub Actions runtime
    # https://registry.terraform.io/providers/hashicorp/Azurerm/latest/docs/guides/service_principal_oidc#oidc-token
  }
}
```

Now migrate the local state to the newly created storage in Azure:
```bash
cd day-0
terraform init -backend-config=../environments/test/backend-config-day-0.hcl -migrate-state
```
You will receive the message:
```bash
Initializing the backend...
Terraform detected that the backend type changed from "local" to "azurerm".

Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "azurerm" backend. No existing state was found in the newly
  configured "azurerm" backend. Do you want to copy this state to the new "azurerm"
  backend? Enter "yes" to copy and "no" to start with an empty state.
```

You should answer with "yes" to copy the state to the new backend.

Now you are ready to make all the changes from within CI pipelines.

### Initializing Terraform Backend

The backend configuration must be passed via `-backend-config` flag during `terraform init`.

**Day-0 Initialization:**
```bash
cd day-0
terraform init -backend-config=../environments/test/backend-config-day-0.hcl
```

**Note:** The state file is stored at:
- Test: `terraform-day-0-test.tfstate`

### Running Terraform Plan/Apply

Use `-var-file` to load environment-specific variables:

**Test Environment:**
```bash
cd day-0
terraform plan \
  -var-file=../environments/test/00-config-day-0.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-0.auto.tfvars

terraform apply \
  -var-file=../environments/test/00-config-day-0.auto.tfvars \
  -var-file=../environments/test/00-parameters-day-0.auto.tfvars
```

### Environment-Specific Files

- **00-config-day-0.auto.tfvars**: Contains provider configuration (subscription_id, tenant_id, client_id, use_oidc) and backend configuration (resource_group_name, storage_account_name, container_name, key)
- **00-parameters-day-0.auto.tfvars**: Contains environment-specific parameters (`env`, tfstate_location). Do not change `env` after day-0 has been applied. See [Changing `env` after day-0 is applied](#changing-env-after-day-0-is-applied).
- **backend-config-day-0.hcl**: Backend configuration for day-0 state file (resource_group_name, storage_account_name, container_name, key)


## Deployment Order

This bootstrap step (day-0) must be completed **before** deploying infrastructure:

1. **day-0 (Bootstrap)**: Initialize tenant and remote state storage
   - Creates storage account for Terraform state
   - Creates Azure AD application and service principal
   - Sets up federated credentials for GitHub Actions
   - Assigns necessary roles and permissions
   - State stored in: `terraform-init-test.tfstate`

2. **02_infrastructure/day-1**: Deploy foundational infrastructure (depends on day-0)
3. **02_infrastructure/day-2**: Deploy identity/governance resources (depends on day-1)

## Resources Created

This bootstrap creates the following resources:

- **Resource Group**: For storing the Terraform state storage account
- **Storage Account**: For storing Terraform state files
- **Azure AD Application**: For Terraform authentication
- **Federated Identity Credentials**: For GitHub Actions OIDC authentication
- **Service Principal**: For Terraform to authenticate to Azure
- **Role Assignments**: Owner and User Access Administrator roles for the service principal
- **App Role Assignments**: Microsoft Graph API permissions (User.Read.All, Group.ReadWrite.All, RoleManagement.ReadWrite.Directory, Application.ReadWrite.All)

## Important Notes

- **Day-0 must be completed first**: All subsequent infrastructure deployments depend on the remote state storage and service principal created here
- **Separate state files**: Each environment uses its own state file
- **Client ID**: After Phase 1, the `client_id` must be updated in the environment's `00-config.auto.tfvars` file
- **OIDC Authentication**: The setup uses OpenID Connect for secure authentication without storing credentials

### How `env` works in day-0 and day-N, and in sandbox subscriptions

The repository has **two independent `env` variables**, and they do very different things:

| | day-0 (`01_bootstrap`) | day-1, day-2, day-3 (`02_infrastructure`) |
|---|---|---|
| Set in | `01_bootstrap/environments/<env>/00-parameters-day-0.auto.tfvars` | `02_infrastructure/environments/<env>/00-parameters-day-{1,2,3}.auto.tfvars` |
| What it names | Only the state resource group: `rg-terraform-state-<env>` | A suffix on almost every resource: Key Vaults `hakv1<env>`/`hakv2<env>`, ACR `uqhacr<env>`, storage `uqhacache<env>`/`uqhastorage<env>`, Redis `uqharedis-<env>`, Cognitive Services subdomains `ha-<env>`/`di-ha-<env>`, custom roles `DevOps-<env>` etc., AKS `aks-<env>`, identities, Log Analytics, Bastion |
| Where the names must be unique | Within the subscription | Many across **all of Azure** (Key Vault, storage, ACR, Redis, Cognitive Services subdomains), custom roles across the **tenant**, the rest within the subscription |
| Several sandboxes in one tenant | No clash. Every sandbox can keep `test`. | **Clash.** Two sandboxes with the same `env` fail on the names that must be unique across Azure or the tenant, and the first one to deploy wins. |
| Changing it after apply | Destroys the state storage, see [below](#changing-env-after-day-0-is-applied) | Replaces most resources, losing the data in Key Vaults, storage and databases |

**Rules for sandbox subscriptions** (for example one subscription per engineer in a shared tenant):

- **day-0:** leave `env` as it is (`test`). The thing that has to be unique per sandbox is the **state storage account name**, which is not derived from `env`. Set it with `storage_account_name` in `00-config-day-0.auto.tfvars` and `backend-config-*.hcl`.
- **day-N:** give every sandbox its own `env`, and choose it **before the first day-1 apply**:
  - Use lowercase letters and digits only, at most about 10 characters. Storage account and ACR names allow no dashes, and `uqhastorage<env>` must fit in 24 characters.
  - Use the **same value in day-1, day-2 and day-3**. Day-2 and day-3 find day-1's resources (Key Vaults, Log Analytics, identities) by names derived from `env`, so a different value makes those lookups fail.
- **Names `env` does not cover.** Change these per sandbox by hand:
  - `audit_storage_sa_name` (defaults to `helloazureaudit`)
  - the Speech Service `custom_subdomain_name` in `00-parameters-day-2.auto.tfvars`
- **Helm values.** Anything in `03_applications` that refers to these names, such as `uqhacr<env>.azurecr.io`, must use the same `env`.
- **Name reservations after deletion.** Deleted Key Vaults keep their name reserved for up to 90 days and Cognitive Services accounts for 48 hours, unless they are purged. A name you tried once may stay unavailable even after you delete the resource.

### Changing `env` after day-0 is applied

> :warning: **Do not change `env` in `00-parameters-day-0.auto.tfvars` once day-0 has been applied.**
>
> `env` is part of the state resource group's name (`rg-terraform-state-<env>`), and Azure cannot rename a resource group. If you change it, Terraform plans to **destroy and recreate** the resource group, the storage account, the container and the management policy:
>
> ```
> # azurerm_resource_group.tfstate must be replaced
>     ~ name = "rg-terraform-state-test" -> "rg-terraform-state-<new>" # forces replacement
> Plan: 4 to add, 0 to change, 4 to destroy.
> ```
>
> That storage account holds the Terraform state of **every** stage (day-0, day-1, day-2, day-3). Applying this plan deletes all of them.

You don't need to change it to avoid clashes with other sandboxes. Resource group names only have to be unique within a subscription, so another subscription can use `rg-terraform-state-test` as well. To keep resources in different sandboxes apart, change `env` in `02_infrastructure` instead, where the names have to be unique across Azure (Key Vault, storage, ACR, Redis) or across the tenant (custom roles).

If you have already changed it, change it back and check that `terraform plan` reports `No changes`.

#### If you really need a different resource group name

Move the storage account into a new resource group instead of recreating it. The data and the state files move with it. Then point Terraform's state at the new location:

```bash
SUB=<subscription-id>
OLD_RG=rg-terraform-state-<old-env>
NEW_RG=rg-terraform-state-<new-env>
SA=<state-storage-account-name>
CONTAINER=<state-container-name>
SA_OLD=/subscriptions/$SUB/resourceGroups/$OLD_RG/providers/Microsoft.Storage/storageAccounts/$SA
SA_NEW=/subscriptions/$SUB/resourceGroups/$NEW_RG/providers/Microsoft.Storage/storageAccounts/$SA

# 1. Create the new resource group and move the storage account (name and data stay the same)
az group create -n $NEW_RG -l <tfstate_location>
az resource move --destination-group $NEW_RG --ids $SA_OLD

# 2. Set resource_group_name = "<NEW_RG>" in backend-config-day-0.hcl, then reconnect to the same state blob
cd day-0
terraform init -reconfigure -backend-config=../environments/<env>/backend-config-day-0.hcl

# 3. Re-link the state to the moved resources (changes Terraform state only, not Azure)
terraform state rm azurerm_resource_group.tfstate \
  module.tfstate_sa.azurerm_storage_account.storage_account \
  "module.tfstate_sa.azurerm_storage_container.container[\"$CONTAINER\"]" \
  'module.tfstate_sa.azurerm_storage_management_policy.default[0]'

V="-var-file=../environments/<env>/00-config-day-0.auto.tfvars -var-file=../environments/<env>/00-parameters-day-0.auto.tfvars"
terraform import $V azurerm_resource_group.tfstate /subscriptions/$SUB/resourceGroups/$NEW_RG
terraform import $V module.tfstate_sa.azurerm_storage_account.storage_account $SA_NEW
terraform import $V "module.tfstate_sa.azurerm_storage_container.container[\"$CONTAINER\"]" $SA_NEW/blobServices/default/containers/$CONTAINER
terraform import $V 'module.tfstate_sa.azurerm_storage_management_policy.default[0]' $SA_NEW/managementPolicies/default

# 4. Check: must report "No changes"
terraform plan $V

# 5. Delete the old, now-empty resource group
az group delete -n $OLD_RG
```

Afterwards:
- Change `resource_group_name` in every `02_infrastructure/environments/<env>/backend-config-*.hcl` and `00-config-day-*.auto.tfvars`.
- Run `terraform init -reconfigure -backend-config=...` in each of those roots.

Do not run any Terraform command while `az resource move` is in progress. Azure locks the source and target resource groups until the move has finished.

