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

## Argo CD login mode

The login mode is set by `argoAuth` in [argo-bootstrap.yaml.gotmpl](argo-bootstrap.yaml.gotmpl):

| `argoAuth` | Login | Values overlay | Also required |
|---|---|---|---|
| `admin` (default) | Built-in `admin` account, username/password | [argo-auth-admin.yaml](test/values/argo/argo-auth-admin.yaml) | nothing |
| `oidc` | Entra ID (Azure AD) | [argo-auth-oidc.yaml](test/values/argo/argo-auth-oidc.yaml) | `gitops_app_registration_enabled = true` in `02_infrastructure` day-2; tenant ID in the overlay; Key Vault values in [argo-azure-entra-secret.yaml](test/values/argo/argo-azure-entra-secret.yaml) |

To switch modes:

1. Set `argoAuth` in `argo-bootstrap.yaml.gotmpl`.
2. Make [apps/system/argo.yaml](test/apps/system/argo.yaml) match, because Argo CD manages itself from that file: use the matching `argo-auth-<mode>.yaml` in the `argo-cd` valueFiles, and uncomment the `sscsid-keeper` source for `oidc` (keep it commented out for `admin`). `helmfile` stops with an error that says what to change if the two disagree.
3. Run `helmfile apply -e test -f argo-bootstrap.yaml.gotmpl`.

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
   - DNS for the test cluster is in place: `sb-trilaksono-001.unique.dev`, `api.sb-trilaksono-001.unique.dev`, `id.sb-trilaksono-001.unique.dev`.
   - TLS certificates are issued (cert-manager + Kong ingress).

2. **Open the chat UI**
   - In a browser go to: **https://sb-trilaksono-001.unique.dev/chat**
   - You will be redirected to Zitadel (IdP) at **https://id.sb-trilaksono-001.unique.dev** to sign in.
   - After login you are redirected back to the chat app.

3. **Optional: check API and pods**
   - Chat API base: `https://api.sb-trilaksono-001.unique.dev/chat`
   - With `kubectl` (context set to the test cluster):
     - `kubectl get pods -n unique -l app.kubernetes.io/name=backend-service-ingestion-worker-chat`
     - `kubectl get pods -n unique -l app.kubernetes.io/name=backend-service-chat`
   - Quick API reachability (no auth): `curl -sI https://api.sb-trilaksono-001.unique.dev/chat` (may return 401/403 without a token).

## Troubleshooting

### "no active client not found" when opening the chat app

This error appears when the chat web app tries to restore the session (silent sign-in / refresh token) but the **OIDC client** it uses is not registered or does not match the **test** Zitadel instance. The values in the repo (`ZITADEL_CLIENT_ID`, `ZITADEL_PROJECT_ID`) are placeholders and must match an application created in the **test** Zitadel.

**Steps to fix:**

1. **Open Zitadel Console (test)**  
   Go to **https://id.sb-trilaksono-001.unique.dev** and sign in with the Zitadel admin user (e.g. the FirstInstance user from your Zitadel config).

2. **Get the correct IDs**
   - In Zitadel: go to your **Project** (e.g. "Cluster IAM" or "unique") and note the **Project ID** (numeric).
   - Open the **Application** used by the chat web app (e.g. "unique-app" or "chat"). Note the **Client ID** (numeric).
   - If the application does not exist, create a **User Agent** (or **Web**) application and set:
     - **Redirect URIs**: `https://sb-trilaksono-001.unique.dev/chat`, `https://sb-trilaksono-001.unique.dev/chat/` (and add any callback path your app uses, e.g. `/chat/callback` if applicable).
     - **Post-logout redirect URI** if needed (e.g. `https://sb-trilaksono-001.unique.dev/chat`).
     - **Auth Method**: PKCE is typical for SPAs; no client secret.

3. **Update the repo with the real IDs**
   - In `03_applications/test/values/web-apps/_all.yaml` set:
     - `ZITADEL_CLIENT_ID` to the Application **Client ID** from Zitadel.
     - `ZITADEL_PROJECT_ID` to the **Project ID** from Zitadel.
   - Keep `ZITADEL_ISSUER` as `https://id.sb-trilaksono-001.unique.dev`.
   - If Kong or other services use the same project for JWT validation, update `ZITADEL_PROJECT_ID` in:
     - `03_applications/test/values/backend-services/_all.yaml`
     - `03_applications/test/values/kong/kong-cluster-plugins.yaml` (e.g. `zitadel_project_id`)
     - `03_applications/test/values/ai-services/assistants-core.yaml`
     so they all match the same Zitadel project.

4. **Redeploy and retry**
   - Commit, push, and sync the chat web app (and any apps that use the updated Kong/backend config).
   - Clear site data for `sb-trilaksono-001.unique.dev` or use a private/incognito window, then open **https://sb-trilaksono-001.unique.dev/chat** again.
