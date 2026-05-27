# Mailcart (Real Outlook Graph Mode)

This project can run against live Outlook mail when `make run` can resolve a valid Microsoft Graph bearer token from `1psa`.

## Prerequisites

1. Run bootstrap once:
   - `./01_install_prerequisites.sh`
2. Confirm `1psa` can read your service-account vault:
   - `1psa -l`
3. Confirm `1psa` exists on your `PATH`:
   - `which 1psa`

## Step 1: Configure Azure App Registration

1. Open [Azure Portal](https://portal.azure.com/).
2. Go to **Microsoft Entra ID** -> **App registrations** -> **New registration**.
3. Set:
   - **Name**: `mailcart-local-graph-reader` (or similar)
   - **Supported account types**: Single tenant is fine for local use
   - **Redirect URI**: leave empty for now
4. Click **Register**.
5. Save the **Application (client) ID** as `CLIENT_ID`.
6. Open **Authentication**:
   - Click **Add a platform** -> **Mobile and desktop applications**
   - Add redirect URI: `https://localhost`
   - Save
7. Open **API permissions**:
   - Click **Add a permission** -> **Microsoft Graph** -> **Delegated permissions**
   - Add `Mail.Read`
   - Add `Mail.ReadWrite` (required for moving matched mailcarts to folder `matchy`)
   - Click **Grant admin consent** if your tenant requires admin approval.

## Step 2: Obtain an Outlook Graph Access Token (Device Code Flow)

Use your app registration `CLIENT_ID` from Step 1.

1. Request a device code:
```bash
export CLIENT_ID="<your-app-client-id>"
DEVICE_RESPONSE="$(curl -sS -X POST "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID}&scope=openid profile offline_access https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/Mail.ReadWrite")"
```
2. Print the verification URL and user code:
```bash
python3 - <<'PY'
import json, os
r = json.loads(os.environ["DEVICE_RESPONSE"])
print("Visit:", r["verification_uri"])
print("Code :", r["user_code"])
print("Device code saved for polling.")
PY
```
3. Complete sign-in/consent in browser using the printed code.
4. Poll token endpoint until you get an access token:
```bash
DEVICE_CODE="$(python3 - <<'PY'
import json, os
print(json.loads(os.environ["DEVICE_RESPONSE"])["device_code"])
PY
)"
TOKEN_RESPONSE="$(curl -sS -X POST "https://login.microsoftonline.com/common/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=${CLIENT_ID}&device_code=${DEVICE_CODE}")"
```
5. Extract tokens and client id:
```bash
OUTLOOK_GRAPH_TOKEN="$(python3 - <<'PY'
import json, os
r = json.loads(os.environ["TOKEN_RESPONSE"])
print(r.get("access_token", ""))
PY
)"
OUTLOOK_GRAPH_REFRESH_TOKEN="$(python3 - <<'PY'
import json, os
r = json.loads(os.environ["TOKEN_RESPONSE"])
print(r.get("refresh_token", ""))
PY
)"
export OUTLOOK_GRAPH_CLIENT_ID="${CLIENT_ID}"
```
6. Validate tokens are non-empty:
```bash
[ -n "${OUTLOOK_GRAPH_TOKEN}" ] && echo "access token acquired" || echo "access token missing"
[ -n "${OUTLOOK_GRAPH_REFRESH_TOKEN}" ] && echo "refresh token acquired" || echo "refresh token missing"
```

## Step 3: Store Tokens in 1Password for 1psa

`1psa` is read-only for item fields. Create/update the item in 1Password UI, then read it with `1psa`.

1. In 1Password, open a vault accessible to the same service account used by `~/.1psa`.
2. Create or update an item named:
   - `OUTLOOK_GRAPH_API`
3. Add text fields named:
   - `token` (default access token field expected by `make run`)
   - `refresh_token` (required for automatic token refresh)
   - `application_client_id` (optional if `OUTLOOK_GRAPH_CLIENT_ID` is already exported)
   - or keep custom field names and override `OUTLOOK_GRAPH_TOKEN_PSA_FIELD` / `OUTLOOK_GRAPH_TOKEN_PSA_REFRESH_FIELD`
4. Paste `${OUTLOOK_GRAPH_TOKEN}` into `token` and `${OUTLOOK_GRAPH_REFRESH_TOKEN}` into `refresh_token`, and paste `${CLIENT_ID}` into `application_client_id`, then save.
5. Export your Azure app client id for runtime refresh:
   - `export OUTLOOK_GRAPH_CLIENT_ID="${CLIENT_ID}"`
   - Add the same value to your shell profile for `make run` / `make run-api`.

## Step 4: Verify 1psa Reads the Tokens

1. Verify item/field discovery:
   - `1psa -l OUTLOOK_GRAPH_API`
2. Verify field retrieval:
   - `1psa -f OUTLOOK_GRAPH_API token`
   - `1psa -f OUTLOOK_GRAPH_API refresh_token`
   - `1psa -f OUTLOOK_GRAPH_API application_client_id`
3. Warm the shared token cache:
   - `python3 scripts/refresh_graph_token.py`

If you use different names, set:

- `OUTLOOK_GRAPH_TOKEN_PSA_ITEM`
- `OUTLOOK_GRAPH_TOKEN_PSA_FIELD`
- `OUTLOOK_GRAPH_TOKEN_PSA_REFRESH_FIELD`
- `OUTLOOK_GRAPH_TOKEN_PSA_CLIENT_ID_FIELD`

Example:

- `OUTLOOK_GRAPH_CLIENT_ID=<client-id> OUTLOOK_GRAPH_TOKEN_PSA_ITEM=my_graph_item make run-api`

## Step 5: Run Against Real Mailcarts

1. Build and launch with token resolution:
   - `make run`
2. The run target:
   - Refreshes the shared token cache when `OUTLOOK_GRAPH_CLIENT_ID` is set
   - Reads token using `1psa -f "$OUTLOOK_GRAPH_TOKEN_PSA_ITEM" "$OUTLOOK_GRAPH_TOKEN_PSA_FIELD"`
   - Exports `OUTLOOK_GRAPH_TOKEN`, `OUTLOOK_GRAPH_CLIENT_ID`, and `MAILCART_REPO_ROOT` to the app process
   - Launches the app executable

## Crash Reporting (PLCrashReporter)

The macOS app initializes `PLCrashReporter` on startup. If a previous run crashed, the next launch persists the pending binary crash payload and metadata under:

- `~/Library/Application Support/<bundle-id>/CrashReports/*.plcrash`
- `~/Library/Application Support/<bundle-id>/CrashReports/*.json`

Use `OUTLOOK_MACOS_FORCE_CRASH_ON_LAUNCH=1` to intentionally crash for local verification of capture and replay behavior.

Run the dedicated smoke verifier from repo root:

- `./scripts/verify_macos_crash_reporter.sh`
- `make crash-reporter-smoke`

To include this smoke lane in `make ui-test` runs:

- `RUN_CRASH_REPORTER_SMOKE_TEST=true make ui-test`

## Security and Quality Checks

Use the consolidated SAST lane before opening PRs:

- `make sast`
- `make lint` (blocking clang-tidy, SwiftLint, and Ruff diagnostics)
- `make clam` (ClamAV recursive repository scan)

`make sast` runs:

- `ShellCheck` for repository shell scripts.
- `Semgrep` (`auto` plus `.semgrep.yml`) for semantic/static security rules.
- `Bandit` for Python security checks.
- `detect-secrets` for secret-pattern scanning with finding-based failure.
- `gitleaks` for secret scanning with `.gitleaks.toml`.

`make lint` runs blocking `clang-tidy` checks for C++/bridge Objective-C(++), `swiftlint` for Swift sources, and `ruff` as the Python-equivalent lint lane. Any finding fails the target.

Recommended local verification sequence:

1. `make build`
2. `make sast`
3. `make test`
4. `make ui-test`

If CI is added later, use the same sequence to keep local and CI checks aligned.

## Troubleshooting

- `Unable to read Outlook Graph token from 1psa...`
  - Verify item/field names and service-account vault permissions.
  - Default lookup is item `OUTLOOK_GRAPH_API` and field `token`.
- Empty mailbox results with valid login
  - Re-check Graph permission consent for `Mail.Read` and `Mail.ReadWrite`.
- `401`/`403` behavior in Graph calls
  - Token expired or missing scope; verify `refresh_token` is stored in 1Password and `OUTLOOK_GRAPH_CLIENT_ID` is exported, then run `python3 scripts/refresh_graph_token.py`.
  - Restart `make run-api` if the HTTPS API process on port 8788 was started before refresh credentials were configured.
- TLS startup failures for `make run-api`
  - Run `./05_install_matchy_api_tls.sh` to generate local cert/key material.
  - Verify `MAILCART_MATCHY_TLS_CERT_FILE` and `MAILCART_MATCHY_TLS_KEY_FILE` point to existing files.
- `1psa` not found
  - Re-run `./01_install_prerequisites.sh`.

## Matchy Mailcart API

To provide Matchy-compatible endpoints for search and move:

- Install local API TLS materials first: `./05_install_matchy_api_tls.sh`
- Run `python3 scripts/matchy_mailcart_api.py`
- Or run `make run-api`
- API transport is HTTPS-only on `https://127.0.0.1:8788`
- Endpoints:
  - `GET /v1/messages/search?query=...&limit=...`
  - `POST /v1/messages/{message_id}/move` with `{ "folder_name": "matchy" }`

## GLOBAL ARCHITECTURE: TELLER → MATCHY ← MAILCART
```text
┌───────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                            SYSTEM LANDSCAPE                                           │
│                                                                                                       │
│  ┌────────────────────────────────┐      HTTPS (search/move)      ┌────────────────────────────────┐  │
│  │             MATCHY             │ ────────────────────────────► │            MAILCART            │  │
│  │                                │ ◄──────────────────────────── │                                │  │
│  │ - FastAPI service              │        message candidates     │ - Outlook/Graph integration    │  │
│  │ - Runs transaction↔email match │                               │ - Search endpoint for emails   │  │
│  │ - Combines scoring + AI ranker │                               │ - Move endpoint to folder      │  │
│  │ - Writes run/candidate/match   │                               │   `matchy`                     │  │
│  │   records to Teller DB         │                               └────────────────────────────────┘  │
│  └───────────────┬────────────────┘                                                                   │
│                  │ SQL read/write                                                                     │
│                  ▼                                                                                    │
│  ┌──────────────────────────────────────────────────────────┐                                         │
│  │                      TELLER DB                           │                                         │
│  │                                                          │                                         │
│  │ - Source transactions: `teller.transaction`              │                                         │
│  │ - Match run table: `teller.transaction_email_match_run`  │                                         │
│  │ - Candidates table: `teller.transaction_email_candidate` │                                         │
│  │ - Match table: `teller.transaction_email_match`          │                                         │
│  └──────────────────────────────────────────────────────────┘                                         │
│                                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘

TRIGGER FLOW
┌─────────────────────────────┐      POST /v1/matchy/runs       ┌────────────────────────────┐
│ Caller (manual/auto/retry)  │───────────────────────────────► │ Matchy API                 │
│ (operator/job in ecosystem) │                                 │ validates ids + starts run │
└───────────────────────────√─┘                                 └────────────────────────────┘
```