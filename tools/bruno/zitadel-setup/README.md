# Zitadel setup (Bruno collection)

Sets up Zitadel on a new hello-azure cluster through the Zitadel Management API instead of the console:
project, web application, project roles and the authorization for your user. It automates section 3 of the
Unique guide [IAM (Zitadel) Initial Setup on New Cluster](https://docs.unique.ai/it-operators/identity-and-access-management-iam/iam-zitadel-initial-setup-on-new-cluster).

Open the folder in [Bruno](https://www.usebruno.com/): **Open Collection** → `tools/bruno/zitadel-setup`.

## Before you start

You need **a service user with the instance role IAM Owner and its PAT.** Section 4.1 of the guide (the
`scope-management` service user) gives you exactly that, and its PAT is in Key Vault.

This is the one manual step. Every API call needs a token, so the first token has to come from the
console. The Zitadel chart (8.13.1) can create a service user on first install (`FirstInstance.Org.Machine`),
but it only writes a machine key, not a PAT, and only when the Zitadel database is empty.

### Create the service user and its PAT in the console

1. **Log in.** Open `https://id.<domain>/ui/console` (e.g. `https://id.sb-trilaksono.unique.dev/ui/console`)
   as the root user from `03_applications/test/values/zitadel/zitadel.yaml` (`FirstInstance.Org.Human`).
   The first login forces a password change. Check that the organization switcher at the top left shows
   **Cluster IAM**.
2. **Create the service user.** **Users** → **Service Users** tab → **+ New**:
   - User Name: `scope-management`
   - Name: `scope-management`
   - Access Token Type: **Bearer**

   Click **Create**. The user needs no project roles.
3. **Create the PAT.** On the user's page, open **Personal Access Tokens** → **+ New**. An expiration
   date is optional; without one the token never expires. Click **Add** and **copy the token now**:
   Zitadel shows it only once. If you lose it, create a new one and delete the old one.
4. **Make it IAM Owner.** This is an *instance* role, not an organization role:
   1. Click **Default settings** at the top right. The page title changes to the instance (`UNIQUE`).
   2. Click the managers icon at the top right (the avatars with **+**), then **+ Add a Manager**.
   3. Search for `scope-management`, select role **IAM_OWNER** and click **Add**.

   If the dialog only offers `ORG_OWNER`, `ORG_USER_MANAGER` and so on, you are on the organization's
   managers page, not the instance's: click **Default settings** first.
5. **Store the PAT in Key Vault** (secret `manual-zitadel-scope-mgmt-pat`, created empty by Terraform in
   `02_infrastructure/day-2/34-secrets.tf`). In zsh:

   ```zsh
   read -rs "PAT?PAT: "; echo
   az keyvault secret set --vault-name hakv1anto -n manual-zitadel-scope-mgmt-pat --value "$PAT" -o none
   unset PAT
   ```

6. **Redeploy the consumers.** External Secrets copies the new value into the cluster on its next refresh.
   Then restart `scope-management` (the `user-sync` CronJob picks the value up on its next run):

   ```bash
   kubectl -n unique get deploy -o name | grep scope-management | xargs kubectl -n unique rollout restart
   ```

7. **Check it.** Copy the PAT into the Bruno `pat` secret and run request 01: HTTP 200 means the PAT is
   valid and has IAM Owner.

## Configure the environment

`Note:` You may not have all of the values at first and will be guided to fill them accordingly when running each step, please read docs section in Bruno for more info.

Select the `sandbox` environment and check the variables:

| Variable | Meaning |
|---|---|
| `zitadelUrl` | Zitadel URL, `https://id.<domain>` |
| `baseUrl` | Domain of the web apps, used for the redirect URIs |
| `orgName` | Name of the organization to set up (`Cluster IAM`) |
| `orgId` | Its ID, filled in by request 01 (sent as `x-zitadel-orgid`) |
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
| 01 | Check token and find org | Confirms the PAT has IAM Owner; `orgId` |
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
