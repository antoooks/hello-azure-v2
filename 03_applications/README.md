# Applications

## Overview

This repository contains Kubernetes applications organized into two sections:

- **System**: Responsible for core infrastructure services including CRDs, operators, Kong, and Zitadel
- **Chat**: Contains all FinanceGPT-specific services including frontend and backend components

## Deployment

All applications are deployed in a Kubernetes cluster and managed through ArgoCD.

## Installation

Installation requires just a single step - launching the `argo-bootstrap.yaml`:

```bash
# test environment
helmfile apply -e test -f argo-bootstrap.yaml.gotmpl
```

Alternatively, in this repository, you can simply run the `[test][bootstrap ArgoCD] 🐙` workflow.

## Environment-specific names

The values files contain Azure resource names that end in the Terraform `env` value, such as `hakv2<env>`, `uqhacr<env>.azurecr.io` and `uqharedis-<env>-port`. After changing `env` in `02_infrastructure/environments/test/00-parameters-day-*.auto.tfvars`, rewrite them all and push:

```bash
./scripts/set-env.sh            # uses env from the day-2 tfvars; "test" if it is missing or null
./scripts/set-env.sh --check    # verify only
```

See [scripts/Readme.md](../scripts/Readme.md#set-envsh) for the exact patterns.

## Argo CD login mode

The login mode is set by `argoAuth` in [argo-bootstrap.yaml.gotmpl](argo-bootstrap.yaml.gotmpl):

| `argoAuth` | Login | Values overlay | Also required |
|---|---|---|---|
| `admin` (default) | Built-in `admin` account, username/password | [argo-auth-admin.yaml](test/values/argo/argo-auth-admin.yaml) | nothing |
| `oidc` | Entra ID (Azure AD) | [argo-auth-oidc.yaml](test/values/argo/argo-auth-oidc.yaml) | `gitops_app_registration_enabled = true` in `02_infrastructure` day-2; tenant ID in the overlay; Key Vault values in [argo-azure-entra-secret.yaml](test/values/argo/argo-azure-entra-secret.yaml) |

The mode is set in two places, and they must match:

- `argoAuth` in `argo-bootstrap.yaml.gotmpl`, which is used when you run `helmfile`.
- [apps/system/argo.yaml](test/apps/system/argo.yaml), which Argo CD uses to manage itself.

If the two disagree, `helmfile` stops with an error that says what to change.

> **Argo CD manages itself from GitHub `main`, not from your local checkout.** Push your changes **before** anyone syncs the `argocd` app. Otherwise the sync restores whatever login mode is on `main`. See [Fixing a login mode that doesn't match Git](#fixing-a-login-mode-that-doesnt-match-git).

### Switching to Entra ID (OIDC) login

1. **Create the Entra app (Terraform, `02_infrastructure` day-2).** In `environments/test/00-parameters-day-2.auto.tfvars`:
   - Set `gitops_app_registration_enabled = true`.
   - Put the users who should be Argo CD admins in `gitops_maintainer_user_ids`. Terraform gives them the `application_support` app role, which the Argo CD RBAC config maps to `role:admin` in [argo.yaml](test/values/argo/argo.yaml).

   Then apply day-2. The identity that runs Terraform must be allowed to create app registrations. In a sandbox where it can't (`403 Authorization_RequestDenied`), OIDC login isn't possible.

2. **Collect the values the cluster needs:**

   ```bash
   az account show --query tenantId -o tsv                                   # tenant ID
   az aks show -g resource-group-core -n aks-<env> \
     --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv   # Key Vault CSI identity (client ID)
   az keyvault secret list --vault-name <sensitive-kv> \
     --query "[?starts_with(name,'aad-app-')].name" -o tsv                   # client-id / client-secret secret names
   ```

   `<sensitive-kv>` is the sensitive Key Vault, `hakv2<env>`, for example `hakv2anto`.

3. **Fill in the values files:**
   - [argo-azure-entra-secret.yaml](test/values/argo/argo-azure-entra-secret.yaml): set `spc.kvName`, `spc.tenantId`, `spc.identityId` and the two `kvObjectName` entries (`...-client-id`, `...-client-secret`). Also check that `keeper.image.repository` points to your ACR.
   - [argo-auth-oidc.yaml](test/values/argo/argo-auth-oidc.yaml): check that the tenant ID in the `issuer` URL matches yours.

4. **Switch the mode in both places:**
   - `argo-bootstrap.yaml.gotmpl`: `argoAuth: oidc`
   - [apps/system/argo.yaml](test/apps/system/argo.yaml): uncomment the `sscsid-keeper` source, and change `argo-auth-admin.yaml` to `argo-auth-oidc.yaml` in the `argo-cd` valueFiles.

5. **Commit and push to `main`.**

6. **Apply:**

   ```bash
   helmfile apply -e test -f argo-bootstrap.yaml.gotmpl
   ```

   This installs the `argo-azure-entra-secret` release first, then upgrades `argo`.

7. **Check that it worked:**

   ```bash
   kubectl -n unique get cm argocd-cm -o jsonpath='{.data.admin\.enabled}{"\n"}'   # expect: false
   kubectl -n unique get pods | grep sscsid-keeper                                 # expect: Running
   kubectl -n unique get secret argo-azure-entra-secret-sscsid-keeper              # created from Key Vault
   ```

   The login page should now show **Log in via AzureAD**.

> With OIDC on, the `admin` account is **disabled**. If the Entra app, its Key Vault secrets or the keeper pod break, nobody can log in to the UI. To get back in, switch to admin login with `kubectl` and `helmfile` (next section).

### Switching back to admin login

1. In `argo-bootstrap.yaml.gotmpl`, set `argoAuth: admin`.
2. In [apps/system/argo.yaml](test/apps/system/argo.yaml), comment out the `sscsid-keeper` source and use `argo-auth-admin.yaml` in the `argo-cd` valueFiles.
3. Commit and push to `main`.
4. Run `helmfile apply -e test -f argo-bootstrap.yaml.gotmpl`, then do the cleanup in the next section. Helm leaves `oidc.config` and the keeper objects behind.
5. Optional: set `gitops_app_registration_enabled = false` in day-2 to remove the Entra app.

### Fixing a login mode that doesn't match Git

This happens when a change reaches the cluster outside of Helm, for example when the `argocd` app is synced from a `main` that has the other login mode. You'll see one of these:

- `helmfile apply` reports no changes, but the live `argocd-cm` is still in the old mode. Helm compares against its own record of the release, not against the cluster.
- `helmfile sync` fails with `conflict occurred while applying object ... conflicts with "argocd-controller"`. Helm 4 uses server-side apply, and Argo CD now owns those fields.

To fix it:

```bash
# 1. Make Helm reapply its manifest and take the conflicting fields back from Argo CD
helmfile -e test -f argo-bootstrap.yaml.gotmpl -l name=argo sync --args="--force-conflicts"

# 2. Admin mode only: remove leftover OIDC settings and Entra secret objects (Helm doesn't delete them)
kubectl -n unique patch cm argocd-cm --type=json -p='[{"op":"remove","path":"/data/oidc.config"}]'
kubectl -n unique delete deployment,poddisruptionbudget,secretproviderclass argo-azure-entra-secret-sscsid-keeper --ignore-not-found

# 3. Check
kubectl -n unique get cm argocd-cm -o jsonpath='{.data.admin\.enabled}{"\n"}{.data.oidc\.config}{"\n"}'
```

## Accessing the Argo CD UI

Argo CD is installed in the `unique` namespace. With `argoAuth: admin` (see above) you log in with the built-in `admin` account:

1. **Get the initial admin password** (username: `admin`):

   ```bash
   kubectl -n unique get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
   ```

   The secret is created once, on the first install. If it returns `NotFound`, it was already deleted; reset the password with `argocd account update-password` instead.

2. **Open the UI** with a port-forward:

   ```bash
   kubectl -n unique get svc | grep server                # confirm the server service name
   kubectl -n unique port-forward svc/argo-server 8080:443
   ```

   Then open https://localhost:8080 and accept the self-signed certificate warning.

3. **Change the password and delete the initial secret** (recommended by Argo CD). After logging in, go to *User Info → Update Password*, then:

   ```bash
   kubectl -n unique delete secret argocd-initial-admin-secret
   ```

> `kubectl` must be able to reach the AKS API server. If the cluster is private (`aks_private_cluster_enabled = true` in `02_infrastructure`), run these commands from inside the VNet (VPN or jumpbox).

## Testing the chat application (test environment)

1. **Prerequisites**
   - Argo CD has synced the chat apps (e.g. `backend-service-ingestion-worker-chat` is Healthy).
   - DNS for the test cluster is in place: `sb-trilaksono.unique.dev`, `api.sb-trilaksono.unique.dev`, `id.sb-trilaksono.unique.dev`.
   - TLS certificates are issued (cert-manager + Kong ingress).

2. **Open the chat UI**
   - In a browser go to: **https://sb-trilaksono.unique.dev/chat**
   - You will be redirected to Zitadel (IdP) at **https://id.sb-trilaksono.unique.dev** to sign in.
   - After login you are redirected back to the chat app.

3. **Optional: check API and pods**
   - Chat API base: `https://api.sb-trilaksono.unique.dev/chat`
   - With `kubectl` (context set to the test cluster):
     - `kubectl get pods -n unique -l app.kubernetes.io/name=backend-service-ingestion-worker-chat`
     - `kubectl get pods -n unique -l app.kubernetes.io/name=backend-service-chat`
   - Quick API reachability (no auth): `curl -sI https://api.sb-trilaksono.unique.dev/chat` (may return 401/403 without a token).

## Troubleshooting

### "no active client not found" when opening the chat app

This error appears when the chat web app tries to restore the session (silent sign-in / refresh token) but the **OIDC client** it uses is not registered or does not match the **test** Zitadel instance. The values in the repo (`ZITADEL_CLIENT_ID`, `ZITADEL_PROJECT_ID`) are placeholders and must match an application created in the **test** Zitadel.

**Steps to fix:**

1. **Open Zitadel Console (test)**  
   Go to **https://id.sb-trilaksono.unique.dev** and sign in with the Zitadel admin user (e.g. the FirstInstance user from your Zitadel config).

2. **Get the correct IDs**
   - In Zitadel: go to your **Project** (e.g. "Cluster IAM" or "unique") and note the **Project ID** (numeric).
   - Open the **Application** used by the chat web app (e.g. "unique-app" or "chat"). Note the **Client ID** (numeric).
   - If the application does not exist, create a **User Agent** (or **Web**) application and set:
     - **Redirect URIs**: `https://sb-trilaksono.unique.dev/chat`, `https://sb-trilaksono.unique.dev/chat/` (and add any callback path your app uses, e.g. `/chat/callback` if applicable).
     - **Post-logout redirect URI** if needed (e.g. `https://sb-trilaksono.unique.dev/chat`).
     - **Auth Method**: PKCE is typical for SPAs; no client secret.

3. **Update the repo with the real IDs**
   - In `03_applications/test/values/web-apps/_all.yaml` set:
     - `ZITADEL_CLIENT_ID` to the Application **Client ID** from Zitadel.
     - `ZITADEL_PROJECT_ID` to the **Project ID** from Zitadel.
   - Keep `ZITADEL_ISSUER` as `https://id.sb-trilaksono.unique.dev`.
   - If Kong or other services use the same project for JWT validation, update `ZITADEL_PROJECT_ID` in:
     - `03_applications/test/values/backend-services/_all.yaml`
     - `03_applications/test/values/kong/kong-cluster-plugins.yaml` (e.g. `zitadel_project_id`)
     - `03_applications/test/values/ai-services/assistants-core.yaml`
     so they all match the same Zitadel project.

4. **Redeploy and retry**
   - Commit, push, and sync the chat web app (and any apps that use the updated Kong/backend config).
   - Clear site data for `sb-trilaksono.unique.dev` or use a private/incognito window, then open **https://sb-trilaksono.unique.dev/chat** again.
