# Zitadel setup (Bruno collection)

Sets up Zitadel on a new hello-azure cluster through the Zitadel Management API instead of the console:
project, web application, project roles and the authorization for your user. It automates section 3 of the
Unique guide [IAM (Zitadel) Initial Setup on New Cluster](https://docs.unique.ai/it-operators/identity-and-access-management-iam/iam-zitadel-initial-setup-on-new-cluster).

Open the folder in [Bruno](https://www.usebruno.com/): **Open Collection** → `tools/bruno/zitadel-setup`.

## Before you start

1. **A service user with IAM Owner and its PAT.** Section 4.1 of the guide (the `scope-management` service
   user) gives you exactly that, and its PAT is in Key Vault. This step stays manual: creating the first
   token needs the console.
2. **The Cluster IAM organization ID.** In the console: Organization → Resource Id. It is already set in
   `environments/sandbox.bru` for `sb-trilaksono`.

## Configure the environment

Select the `sandbox` environment and check the variables:

| Variable | Meaning |
|---|---|
| `zitadelUrl` | Zitadel URL, `https://id.<domain>` |
| `baseUrl` | Domain of the web apps, used for the redirect URIs |
| `orgId` | Cluster IAM organization ID (sent as `x-zitadel-orgid`) |
| `projectName`, `appName` | Names to create (`unique`, `unique-app`) |
| `loginName` | Login name of the user who gets the roles (for request 06) |
| `projectId`, `appId`, `clientId`, `userId` | Filled in by the requests |
| `pat` (secret) | The PAT |

`pat` is a **secret** variable: Bruno stores its value only on your machine, never in the `.bru` files. Copy
it from Key Vault and paste it into the environment:

```bash
az keyvault secret show --vault-name hakv1anto -n manual-zitadel-scope-mgmt-pat --query value -o tsv | pbcopy
```

## Run the requests in order

| # | Request | Result |
|---|---|---|
| 01 | Check token (my org) | Confirms the PAT and `orgId` |
| 02 | Create project | `projectId` |
| 03 | Create web app (PKCE) | `appId`, `clientId` |
| 04 | Add project roles (bulk) | All 13 roles from "Understand Roles and Permissions" |
| 05 | List project roles | Test fails if a role is missing |
| 06 | Find user by login name | `userId` (set `loginName` first) |
| 07 | Grant roles to user | Authorization with all roles |
| 08 | List apps (find client ID) | Read-only; use when the app already exists |

Each request has a test (Tests tab) and a description (Docs tab). Requests that create something fail with
`ALREADY_EXISTS` when run twice; see their Docs tab.

## Afterwards

Put the IDs into the values files, then push and sync:

| Value | Files in `03_applications/test/values` |
|---|---|
| `clientId` | `web-apps/_all.yaml` (`ZITADEL_CLIENT_ID`) |
| `projectId` | `web-apps/_all.yaml`, `backend-services/_all.yaml`, `backend-services/unique-api.yaml`, `backend-services/chat-task-scheduler.yaml`, `ai-services/assistants-core.yaml` (`ZITADEL_PROJECT_ID`), `kong/kong-cluster-plugins.yaml` (`zitadel_project_id`) |
| `orgId` | `backend-services/scope-management.yaml`, `backend-services/ingestion.yaml` (`ZITADEL_ROOT_ORG_ID`) |

Not covered here (still in the console or in the guide): Zitadel Actions such as `addGrant` (guide section 5)
and SSO (section 6).
