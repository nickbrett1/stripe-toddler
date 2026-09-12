# Stripe Toddler — Implementation Plan

## Goal

Build and ship the Stripe Toddler iPad POS system: a toddler-friendly point-of-sale app on iPad backed by a Rust Cloudflare Worker, connecting to a Tera barcode scanner and Stripe Reader M2 via Bluetooth. The plan maps directly to the ESDD dependency graph's three `job.*` nodes and five `expectation.*` success criteria.

> [!IMPORTANT]
> This plan is designed for execution by a **human developer and/or an AI agent workflow**. Every step is self-contained with explicit tooling, success conditions, and dependency ordering. Steps are tagged `[MANUAL]`, `[AGENT]`, or `[MANUAL + AGENT]`.

## User Review Required

> [!IMPORTANT]
> **Admin Portal (job.admin-portal) is out-of-scope for this implementation plan.** Per `description.md`, the admin frontend will be built separately as part of fintechnick.com. This plan implements only the **admin backend API routes** (`/api/admin/*`) that the future frontend will call. The admin wireframe exists to verify the API interface, not to be built here.

---

## ESDD Mapping

The plan maps to the dependency graph as follows:

| ESDD Node | Plan Coverage |
|-----------|--------------|
| `job.payments-backend` | **Phase 2** — Full Rust Worker implementation |
| `job.ipad-pos-client` | **Phase 3 + 4** — Full iPad SwiftUI app |
| `job.admin-portal` | **Phase 2** (backend routes only) — Frontend deferred |
| `expectation.scan-item-success` | Phase 3 Step 3.6 + Phase 4 Step 4.2 |
| `expectation.checkout-success` | Phase 4 Steps 4.3–4.5 |
| `expectation.celebration-success` | Phase 3 Step 3.9 |
| `expectation.inventory-success` | Phase 2 Steps 2.9 and 2.10 (API only) |
| `expectation.analytics-api-success` | Phase 2 Step 2.11 |

---

# Phase 0: Prerequisites

All manual. Must complete before any code is written.

---

### Step 0.1 — Create Stripe Terminal Location **[MANUAL]**

**Action**: In the Stripe Dashboard:
1. Navigate to **Terminal → Locations**.
2. Create a new location (e.g. "Home Studio").
3. Copy the Location ID (starts with `tml_`).

**Tool**: [Stripe Dashboard → Terminal](https://dashboard.stripe.com/test/terminal/locations)

**Success**: A `tml_xxxxx` Location ID exists and is saved for Step 0.3.

**Ref**: `implementation-considerations.md` §7

---

### Step 0.2 — Generate ADMIN_API_KEY **[AGENT]**

**Action**: Generate a cryptographically random 64-character hex string to serve as the admin API key.

**Tool**: `run_command` — `openssl rand -hex 32`

**Success**: A 64-character hex string is generated and saved for Step 0.3.

---

### Step 0.3 — Create Doppler Project and Set Secrets **[MANUAL + AGENT]**

**Action**: Create the Doppler project and populate project-specific secrets.

**Tool**: `run_command` — Doppler CLI

**Commands** (agent executes in devcontainer):
```bash
# Verify auth
doppler me

# Create project
doppler projects create stripe-toddler

# Set secrets (values provided by developer)
doppler secrets set STRIPE_SECRET_KEY="sk_test_xxxxx" \
                    STRIPE_PUBLISHABLE_KEY="pk_test_xxxxx" \
                    STRIPE_WEBHOOK_SECRET="whsec_xxxxx" \
                    STRIPE_TERMINAL_LOCATION_ID="tml_xxxxx" \
                    ADMIN_API_KEY="<from step 0.2>" \
  --project stripe-toddler --config dev
```

**Manual part**: Developer must provide the Stripe key values from the Stripe Dashboard. The `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are inherited from the Doppler `common` project via genproj scripts — no action needed.

**Success**: `doppler secrets --project stripe-toddler --config dev` lists all 5 secrets.

**Ref**: `implementation-considerations.md` §5

---

# Phase 1: Repository Bootstrap

---

### Step 1.1 — Scaffold Repo via genproj **[AGENT]**

**Action**: Use the `fintechnick` MCP to generate the starter repository with all necessary capabilities, automatically creating the remote GitHub repository.

**Tool**: `fintechnick` MCP → `generate_project`

**Arguments**:
```json
{
  "name": "stripe-toddler",
  "description": "iPad POS + Rust Cloudflare Worker for toddler shop",
  "capabilities": [
    "coding-agents",
    "devcontainer-rust",
    "circleci",
    "doppler",
    "cloudflare-wrangler",
    "dependabot",
    "editor-tools",
    "gitguardian",
    "sonarcloud"
  ],
  "configuration": {
    "cloudflare-wrangler": {
      "workerType": "rust"
    }
  }
}
```

**Success**: The MCP creates the GitHub repository and returns a generated project structure. The initial working directory is pushed to the new remote repository.

**Ref**: `implementation-considerations.md` §1, §2

---

### Step 1.2 — Customize Repo Structure **[AGENT]**

**Action**: After genproj scaffold, create the `ios/` and `worker/` directory structure matching the agreed layout:

```
stripe-toddler/
├── ios/                     # (empty, Xcode will create project here)
├── worker/
│   ├── src/
│   │   └── lib.rs
│   ├── migrations/
│   │   └── 0001_initial.sql
│   ├── scripts/
│   │   └── seed-local.sh
│   ├── Cargo.toml
│   └── wrangler.toml
├── specs/                   # Copy spec artifacts from ftn repo
```

**Tool**: `write_to_file`, `run_command` (mkdir, cp)

**Files to create**:
- `worker/Cargo.toml` — Rust project with `worker`, `serde`, `serde_json`, `uuid`, `chrono` dependencies
- `worker/src/lib.rs` — Minimal worker entry point that compiles
- `worker/wrangler.toml` — Configure worker name, compatibility date, D1/KV bindings (placeholder IDs)
- `worker/migrations/0001_initial.sql` — Copy from `spec/data-architecture/d1-schema.sql`
- `ios/.gitkeep` — Placeholder until Xcode project is created

**Success**: `cargo check` passes inside the `worker/` directory. The directory structure matches the proposal.

**Depends on**: Step 1.1

---

### Step 1.3 — Create Cloudflare D1 Database **[AGENT]**

**Action**: Create the production D1 database and record its ID.

**Tool**: `run_command`

```bash
cd worker
wrangler d1 create stripe_toddler_analytics
# Output: Created D1 database 'stripe_toddler_analytics' with id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Post-action**: Update `worker/wrangler.toml` with the returned `database_id`.

**Success**: `wrangler d1 list` shows `stripe_toddler_analytics`.

---

### Step 1.4 — Create Cloudflare KV Namespace **[AGENT]**

**Action**: Create the production KV namespace.

**Tool**: `run_command`

```bash
cd worker
wrangler kv:namespace create STRIPE_TODDLER_INVENTORY
# Output: Add the following to your wrangler.toml: kv_namespaces = [{ binding = "STRIPE_TODDLER_INVENTORY", id = "xxxxx" }]
```

**Post-action**: Update `worker/wrangler.toml` with the returned namespace `id`.

**Success**: `wrangler kv:namespace list` shows `STRIPE_TODDLER_INVENTORY`.

---

### Step 1.5 — (Removed) Cloudflare R2 Bucket **[AGENT]**

**Status**: Dropped. Inventory photos are stored inline in the KV item record as
a `data:image/...;base64,` URI (the `image_url` field), not in a separate object
store. There is no R2 bucket and no `[[r2_buckets]]` binding — see
`capacity/load-model.md` §2.2.

---

### Step 1.6 — Run D1 Migration (Production + Local) **[AGENT]**

**Action**: Apply the initial schema migration to both production D1 and local Miniflare.

**Tool**: `run_command`

```bash
cd worker

# Production
wrangler d1 execute stripe_toddler_analytics --file ./migrations/0001_initial.sql

# Local Miniflare
wrangler d1 execute stripe_toddler_analytics --local --file ./migrations/0001_initial.sql
```

**Success**: Both commands complete without error. `wrangler d1 execute stripe_toddler_analytics --local --command "SELECT name FROM sqlite_master WHERE type='table'"` returns `transactions` and `transaction_items`.

**Ref**: `implementation-considerations.md` §6 (Miniflare section), `d1-schema.sql`

---

### Step 1.7 — Create Local Seed Script **[AGENT]**

**Action**: Create `worker/scripts/seed-local.sh` — a shell script that seeds the local Miniflare KV with test inventory items and verifies D1 tables.

**Tool**: `write_to_file`

**File**: `worker/scripts/seed-local.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "=== Seeding local Miniflare D1 ==="
wrangler d1 execute stripe_toddler_analytics --local --file ./migrations/0001_initial.sql 2>/dev/null || true

echo "=== Seeding local KV with test inventory ==="
wrangler kv:key put --local --binding=STRIPE_TODDLER_INVENTORY \
  "item:TEST001" '{"barcode":"TEST001","name":"Red Fire Truck","price_cents":500,"image_url":"https://placehold.co/400","created_at":1700000000}'

wrangler kv:key put --local --binding=STRIPE_TODDLER_INVENTORY \
  "item:TEST002" '{"barcode":"TEST002","name":"Stuffed Teddy Bear","price_cents":300,"image_url":"https://placehold.co/400","created_at":1700000000}'

wrangler kv:key put --local --binding=STRIPE_TODDLER_INVENTORY \
  "item:TEST003" '{"barcode":"TEST003","name":"Yellow Rubber Duck","price_cents":100,"image_url":"https://placehold.co/400","created_at":1700000000}'

echo "=== Local seed complete ==="
```

**Post-action**: `chmod +x worker/scripts/seed-local.sh`

**Success**: Running `./scripts/seed-local.sh` from the `worker/` directory succeeds. `wrangler kv:key get --local --binding=STRIPE_TODDLER_INVENTORY "item:TEST001"` returns the JSON.

---

### Step 1.8 — Push Initial Scaffold + Commit **[AGENT]**

**Action**: Commit all generated and customized files to `main` and push.

**Tool**: `run_command` (git)

**Success**: GitHub shows the initial commit with the full directory structure.

---

### Step 1.9 — Clone to Mac Studio **[MANUAL]**

**Action**: On the Mac Studio:
1. `git clone git@github.com:nickbrett1/stripe-toddler.git`
2. Open the repo folder in VS Code — the devcontainer will build and launch automatically.
3. Verify `wrangler whoami` works inside the devcontainer (cloud_login.sh should have authenticated).

**Success**: The devcontainer is running, `wrangler whoami` returns the Cloudflare account, and `cargo check` passes in `worker/`.

---

### Step 1.10 — Create Xcode Project on Mac Host **[MANUAL]**

**Action**: On the Mac Studio with Xcode open:
1. Xcode → Settings → Accounts → add Apple ID (if not already signed in).
2. File → New → Project → App.
3. Product Name: `StripeToddlerPOS`.
4. Team: Your personal team (free Apple ID).
5. Interface: SwiftUI.
6. Language: Swift.
7. **Save location**: Navigate to the repo's `ios/` subfolder.
8. Ensure "Create Git repository" is **unchecked** (the repo already exists).
9. Set deployment target to **iPadOS 16.0**.
10. Set Supported Destinations to **iPad** only.

**Success**: `ios/StripeToddlerPOS/StripeToddlerPOS.xcodeproj` exists. Xcode can build and run the default "Hello World" template on the iPad Simulator.

**Ref**: `implementation-considerations.md` §4, `deployment-targets.md` §1

---

### Step 1.11 — Add SPM Dependencies in Xcode **[MANUAL]**

**Action**: In Xcode, add Swift Package dependencies:
1. File → Add Package Dependencies...
2. Add: `https://github.com/stripe/stripe-terminal-ios` (StripeTerminal, latest 3.x)

**Success**: Xcode resolves packages and builds without errors.

---

### Step 1.12 — Verify xcode-native MCP Connection **[MANUAL + AGENT]**

**Action**: With Xcode open and the StripeToddlerPOS project loaded:
1. Ensure the Xcode bridge daemon is running on the Mac.
2. From the agent, call `xcode-native` MCP → `XcodeLS` to list the project files.

**Tool**: `xcode-native` MCP → `XcodeLS`

**Success**: `XcodeLS` returns the Xcode project file tree including the default SwiftUI files.

**Depends on**: Step 1.10

---

### Step 1.13 — Commit Xcode Project **[AGENT]**

**Action**: Add the Xcode project files to Git and commit.

**Tool**: `run_command` (git add, git commit)

**Pre-check**: Ensure `.gitignore` includes Xcode-specific entries:
```
# Xcode
*.xcuserstate
xcuserdata/
DerivedData/
*.xcworkspace/xcshareddata/swiftpm/
```

**Success**: Clean commit containing the Xcode project. `git status` shows no untracked files.

---

# Phase 2: Rust Worker Backend

Implements `job.payments-backend`. All steps run inside the devcontainer unless noted.

---

### Step 2.1 — Domain Model Structs **[AGENT]**

**Action**: Create `worker/src/models.rs` with all domain structs.

**Tool**: `write_to_file`

**Content**: Transcribe from `spec/data-architecture/domain-models.rs`:
- `InventoryItem` (KV)
- `TransactionRecord`, `TransactionItemRecord` (D1)
- `AttestChallengeResponse`, `VerifyAttestRequest`, `DeviceAttestationRecord`
- `CreatePaymentIntentRequest`, `CreatePaymentIntentResponse`
- `CaptureTransactionRequest`, `LineItem`, `CaptureTransactionResponse`

**Success**: `cargo check` passes.

**Ref**: `domain-models.rs`

---

### Step 2.2 — Worker Router Skeleton **[AGENT]**

**Action**: Implement the main worker entry point in `worker/src/lib.rs` with route matching for all endpoints from the OpenAPI spec.

**Tool**: `write_to_file`

**Routes to implement** (returning stub 501 responses initially):

| Method | Path | Handler Function | Auth |
|--------|------|-----------------|------|
| POST | `/api/attest/challenge` | `handle_attest_challenge` | None |
| POST | `/api/attest/verify` | `handle_attest_verify` | None |
| GET | `/api/pos/inventory/{barcode}` | `handle_pos_inventory_lookup` | AppAttest |
| POST | `/api/terminal/connection-token` | `handle_terminal_connection_token` | AppAttest |
| POST | `/api/terminal/payment-intent` | `handle_create_payment_intent` | AppAttest |
| POST | `/api/terminal/capture` | `handle_capture_transaction` | AppAttest |
| GET | `/api/admin/inventory` | `handle_admin_list_inventory` | AdminApiKey |
| POST | `/api/admin/inventory` | `handle_admin_update_inventory` | AdminApiKey |
| GET | `/api/admin/analytics` | `handle_admin_analytics` | AdminApiKey |

**Success**: `cargo build --target wasm32-unknown-unknown` compiles. `wrangler dev` starts and responds to requests (with 501).

**Ref**: `worker-openapi.yaml`

---

### Step 2.3 — Auth Middleware **[AGENT]**

**Action**: Implement two auth mechanisms:

1. **AdminApiKey**: Extract `X-Admin-API-Key` header, compare against `ADMIN_API_KEY` env var (from Doppler). Return 401 on mismatch.
2. **AppAttest Assertion**: Extract `X-App-Attest-Assertion` header. For the initial implementation, validate that the header is present and non-empty. Full CBOR attestation verification is complex and can be stubbed with a TODO — the important thing is the middleware structure exists and the KV lookup pattern for `attest:device:<device_id>` is in place.

**Tool**: `write_to_file` — `worker/src/auth.rs`

**Success**: Requests to `/api/admin/*` without `X-Admin-API-Key` return 401. Requests to `/api/pos/*` without `X-App-Attest-Assertion` return 401.

**Ref**: `worker-openapi.yaml` security schemes, `kv-layout.json` (attest:device pattern)

---

### Step 2.4 — Inventory Lookup Endpoint **[AGENT]**

**Action**: Implement `GET /api/pos/inventory/{barcode}`.

**Tool**: `write_to_file` — update `worker/src/lib.rs` or create `worker/src/handlers/pos.rs`

**Logic**:
1. Extract `barcode` from path.
2. Read from KV: key = `item:<barcode>`.
3. Deserialize as `InventoryItem`.
4. Return 200 with JSON, or 404 if not found.

**Test**: `wrangler dev` + local seed data from Step 1.7. `curl http://localhost:8787/api/pos/inventory/TEST001` returns the seeded item JSON.

**Success**: Correct JSON response matching the `InventoryItem` schema from `kv-layout.json`.

**Ref**: `worker-openapi.yaml` (`lookupPosItem`), `kv-layout.json` (`item:<barcode>` pattern)

---

### Step 2.5 — Stripe Connection Token Endpoint **[AGENT]**

**Action**: Implement `POST /api/terminal/connection-token`.

**Tool**: `write_to_file`

**Logic**:
1. Make HTTP POST to `https://api.stripe.com/v1/terminal/connection_tokens` with the `STRIPE_SECRET_KEY` as Bearer auth.
2. Parse response for `secret` field.
3. Return 200 with `{ "secret": "<token>" }`.

**Success**: Calling the endpoint returns a valid connection token string from Stripe (test mode).

**Ref**: `worker-openapi.yaml` (`getTerminalToken`)

---

### Step 2.6 — Payment Intent Creation Endpoint **[AGENT]**

**Action**: Implement `POST /api/terminal/payment-intent`.

**Tool**: `write_to_file`

**Logic**:
1. Parse `CreatePaymentIntentRequest` from JSON body.
2. HTTP POST to `https://api.stripe.com/v1/payment_intents` with:
   - `amount` = `amount_cents`
   - `currency` = `usd`
   - `payment_method_types[]` = `card_present`
   - `capture_method` = `manual` (so the Worker captures after authorization)
3. Parse Stripe response for `id` and `client_secret`.
4. Return `CreatePaymentIntentResponse`.

**Success**: Calling the endpoint with `{"amount_cents": 500, "barcodes": ["TEST001"]}` returns a valid `pi_xxxxx` ID and client secret.

**Ref**: `worker-openapi.yaml` (`createPaymentIntent`), `checkout-sequence.md` (Step 2)

---

### Step 2.7 — Capture and Log Transaction Endpoint **[AGENT]**

**Action**: Implement `POST /api/terminal/capture`.

**Tool**: `write_to_file`

**Logic**:
1. Parse `CaptureTransactionRequest`.
2. HTTP POST to `https://api.stripe.com/v1/payment_intents/{payment_intent_id}/capture`.
3. Generate a UUID for `transaction_id`.
4. Insert into D1 `transactions` table.
5. Insert each line item into D1 `transaction_items` table.
6. Return `CaptureTransactionResponse`.

**Success**: After calling the endpoint, `wrangler d1 execute stripe_toddler_analytics --local --command "SELECT * FROM transactions"` shows the logged transaction.

**Ref**: `worker-openapi.yaml` (`captureTransaction`), `d1-schema.sql`, `checkout-sequence.md` (Step 4)

---

### Step 2.8 — App Attest Challenge/Verify Endpoints **[AGENT]**

**Action**: Implement `POST /api/attest/challenge` and `POST /api/attest/verify`.

**Tool**: `write_to_file`

**Logic for challenge**:
1. Generate 32 random bytes, base64-encode.
2. Set expiry to now + 300 seconds.
3. Store challenge in KV with TTL (key: `challenge:<base64>`, value: timestamp, expiration: 300s).
4. Return `AttestChallengeResponse`.

**Logic for verify** (simplified for initial implementation):
1. Parse `VerifyAttestRequest`.
2. Verify challenge exists in KV and hasn't expired.
3. Store device registration in KV: `attest:device:<device_id>` → `DeviceAttestationRecord`.
4. Return 200.

> [!NOTE]
> Full CBOR attestation verification against Apple's attestation certificate chain is complex. The initial implementation stores the key but does not cryptographically verify the attestation object. This is acceptable for a personal-use app with device-restricted access. A TODO comment should mark where full verification would go.

**Success**: Challenge endpoint returns base64 challenge. Verify endpoint with a valid challenge stores a device record in KV.

**Ref**: `worker-openapi.yaml` (`getAttestChallenge`, `verifyAttest`), `kv-layout.json` (`attest:device:` pattern)

---

### Step 2.9 — Admin Inventory Endpoints **[AGENT]**

**Action**: Implement `GET /api/admin/inventory` and `POST /api/admin/inventory`.

**Tool**: `write_to_file`

**Logic for GET (list)**:
1. List all KV keys with prefix `item:`.
2. Fetch each value and deserialize as `InventoryItem`.
3. Return as JSON array.

**Logic for POST (create/update)**:
1. Parse `InventoryItem` from body.
2. Write to KV: key = `item:<barcode>`, value = serialized JSON.
3. Return 200.

**Success**: POST creates an item, GET returns it in the list.

**Ref**: `worker-openapi.yaml` (`listInventory`, `updateInventoryItem`)

**Expectation**: `expectation.inventory-success` (API portion — "Catalog is updated at edge")

---

### Step 2.10 — Admin Image Handling (KV-Embedded, No Upload Endpoint) **[AGENT]**

**Action**: No dedicated image-upload endpoint. A photo reaches the backend as
part of the inventory item itself: the admin UI encodes it as a
`data:image/...;base64,` URI and sends it as the `image_url` field of the
`POST /api/admin/inventory` payload.

**Tool**: none — handled by `handle_admin_update_inventory`

**Logic**:
1. The `image_url` string is stored verbatim with the item in `STRIPE_TODDLER_INVENTORY` under `item:<barcode>`.
2. Size limits are Cloudflare KV's per-value ceiling (25 MiB), not a separate upload endpoint's 5 MB multipart limit.

**Success**: Creating an inventory item with a base64 `image_url` returns it unchanged from `GET /api/admin/inventory`, and the POS renders the photo.

**Ref**: `worker-openapi.yaml` (`InventoryItem.image_url`), `capacity/load-model.md` §2.2

**Expectation**: `expectation.inventory-success` ("photos stored with the item in KV")

---

### Step 2.11 — Admin Analytics Endpoint **[AGENT]**

**Action**: Implement `GET /api/admin/analytics`.

**Tool**: `write_to_file`

**Logic**:
1. Parse `limit` and `offset` query params (defaults: 100, 0).
2. Query D1: `SELECT * FROM transactions ORDER BY created_at DESC LIMIT ? OFFSET ?`.
3. For each transaction, query `transaction_items WHERE transaction_id = ?`.
4. Assemble `TransactionRecord` with nested items array.
5. Return as JSON array.

**Success**: After seeding a test transaction via the capture endpoint, GET returns it with correct line items.

**Ref**: `worker-openapi.yaml` (`getSalesAnalytics`), `d1-schema.sql`

**Expectation**: `expectation.analytics-api-success`

---

### Step 2.12 — Unit Tests **[AGENT]**

**Action**: Write Rust unit tests in `worker/src/lib.rs` or separate test modules.

**Tool**: `write_to_file`

**Tests to write**:
- `test_inventory_item_serialization` — Round-trip `InventoryItem` through serde.
- `test_payment_intent_request_validation` — `amount_cents` must be ≥ 100.
- `test_admin_api_key_auth` — Requests without `X-Admin-API-Key` return 401.
- `test_capture_request_serialization` — Round-trip `CaptureTransactionRequest`.

**Success**: `cargo test` passes all tests.

---

### Step 2.13 — CircleCI Pipeline Configuration **[AGENT]**

**Action**: Update the genproj-generated `.circleci/config.yml` to include:
- `cargo clippy -- -D warnings` (lint)
- `cargo test` (unit tests)
- `cargo build --target wasm32-unknown-unknown` (WASM build verification)
- `wrangler deploy` (production deploy, only on `main` branch merge)

**Tool**: `write_to_file` — `.circleci/config.yml`

**Success**: Push to a branch triggers lint + test + build. Merge to `main` triggers deploy.

**Ref**: `implementation-considerations.md` §8 (CircleCI-only deploy)

---

### Step 2.14 — Phase 2 Integration Test **[AGENT]**

**Action**: Run `wrangler dev` locally and execute the full API flow:

```bash
# 1. Create an item
curl -X POST http://localhost:8787/api/admin/inventory \
  -H "X-Admin-API-Key: $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"barcode":"CURL01","name":"Test Duck","price_cents":200,"image_url":"https://placehold.co/400","created_at":1700000000}'

# 2. Look it up (skip attest for local testing)
curl http://localhost:8787/api/pos/inventory/CURL01

# 3. Create a payment intent
curl -X POST http://localhost:8787/api/terminal/payment-intent \
  -H "Content-Type: application/json" \
  -d '{"amount_cents":200,"barcodes":["CURL01"]}'

# 4. List analytics
curl http://localhost:8787/api/admin/analytics \
  -H "X-Admin-API-Key: $ADMIN_API_KEY"
```

**Success**: All endpoints return expected responses. No 500 errors.

---

# Phase 3: iOS App Foundation

Implements `job.ipad-pos-client`. All iOS coding steps use the `xcode-native` MCP from within the devcontainer. **Xcode must be open on the Mac host** with the StripeToddlerPOS project loaded.

> [!IMPORTANT]
> All SwiftUI code in this phase **must** conform to [design-system.md](file:///workspaces/ftn/specs/stripe-toddler/spec/ui/design-system.md). This means: 120×120pt minimum touch targets, iconography over text, toddler color palette tokens, `ToddlerButtonStyle` with squish animations, SF Pro Rounded typography, 8pt grid, and all 10 forbidden patterns listed in Rule 10.

---

### Step 3.1 — Create Source Group Structure **[AGENT]**

**Action**: Create the folder structure for the iOS app source code.

**Tool**: `xcode-native` MCP → `XcodeMakeDir`

**Folders**:
```
StripeToddlerPOS/
├── App/                    # App entry point
├── DesignSystem/           # Color tokens, button styles, typography
├── Models/                 # Codable data models
├── Services/               # Network client, scanner service, terminal manager
├── ViewModels/             # POSViewModel
├── Views/                  # SwiftUI views
│   ├── Checkout/          # Cart, item cards, scanner display
│   └── Celebration/       # Success animation views
└── Resources/             # Audio, video assets
```

**Success**: `XcodeLS` shows all directories.

---

### Step 3.2 — Design System Tokens **[AGENT]**

**Action**: Create `DesignSystem/ToddlerDesignSystem.swift` with all color, typography, layout, and animation constants from the design system spec.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Content** (key excerpts):
```swift
import SwiftUI

// MARK: - Color Tokens (Rule 3)
enum ToddlerColors {
    static let green = Color(hex: "#2ECC40")      // Confirm/Pay
    static let red = Color(hex: "#FF4136")         // Cancel/Remove
    static let blue = Color(hex: "#0074D9")        // Active/Interactive
    static let yellow = Color(hex: "#FFDC00")      // Highlight/Attention
    static let background = Color(hex: "#1A1A2E")  // Deep navy
    static let surface = Color(hex: "#16213E")     // Card backgrounds
    static let textPrimary = Color.white
    static let disabled = Color(hex: "#4A4A5A")
    static let disabledText = Color(hex: "#7A7A8A")
}

// MARK: - Touch Targets (Rule 1)
enum ToddlerLayout {
    static let minTouchTarget: CGFloat = 120
    static let primaryCTAHeight: CGFloat = 120
    static let primaryCTAMinWidth: CGFloat = 200
    static let gridUnit: CGFloat = 8
    static let targetSpacing: CGFloat = 24
    static let cornerRadiusButton: CGFloat = 20
    static let cornerRadiusCard: CGFloat = 24
    static let cornerRadiusModal: CGFloat = 32
}

// MARK: - Button Style (Rule 4)
struct ToddlerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55),
                       value: configuration.isPressed)
    }
}
```

**Success**: `BuildProject` compiles with no errors.

**Ref**: `design-system.md` Rules 1–4

---

### Step 3.3 — Data Models (Swift) **[AGENT]**

**Action**: Create `Models/POSModels.swift` with Swift Codable structs matching the API contract.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Content**: Transcribe from `swift-protocols.md` §3:
- `POSInventoryItem: Codable, Identifiable`
- `PaymentIntentResponse: Codable`
- `CaptureResponse: Codable`

**Success**: `BuildProject` compiles.

**Ref**: `swift-protocols.md` §3

---

### Step 3.4 — Backend API Client **[AGENT]**

**Action**: Create `Services/BackendAPIClient.swift` implementing the `BackendAPIClientProtocol`.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Logic**:
- Base URL configurable (pointing to the Worker endpoint).
- Methods: `fetchItem(barcode:)`, `fetchTerminalConnectionToken()`, `createPaymentIntent(amountCents:barcodes:)`, `captureTransaction(...)`.
- All methods use `URLSession` with `async/await`.
- App Attest assertion header generation (stubbed initially — `X-App-Attest-Assertion: placeholder`).

**Success**: `BuildProject` compiles.

**Ref**: `swift-protocols.md` §3, `worker-openapi.yaml`

---

### Step 3.5 — Barcode Scanner Service **[AGENT]**

**Action**: Create `Services/BarcodeScannerService.swift` implementing `BarcodeScannerServiceProtocol`.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Logic**:
- Uses a hidden `UITextField` or `UIKeyCommand` approach to intercept global keyboard events.
- Aggregates characters into a buffer.
- On `\r` or `\n`, fires `didScanBarcode` delegate callback with the accumulated string.
- Timeout: if no character received within 500ms, clear buffer (prevents stale partial scans).

**Success**: `BuildProject` compiles. Unit test with mock keyboard input validates barcode aggregation.

**Ref**: `swift-protocols.md` §1, `deployment-targets.md` §2.1

---

### Step 3.6 — POS View Model **[AGENT]**

**Action**: Create `ViewModels/POSViewModel.swift` implementing `POSViewModelProtocol`.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Logic**:
- Published `state: POSFlowState` (from `swift-protocols.md` §4).
- `handleBarcodeScanned(_ barcode:)` → calls `BackendAPIClient.fetchItem()` → transitions to `.cartActive`.
- `removeItem(at:)` → removes item, recalculates total, transitions to `.waitingForScan` if empty.
- `startCheckout()` → transitions through `.readerSyncing` → `.awaitingCardTap` → `.processingPayment` → `.celebrating`.
- `resetPOS()` → transitions to `.waitingForScan`.

**Success**: `BuildProject` compiles.

**Ref**: `swift-protocols.md` §4, `payment-state-machine.md` (iPad POS states)

---

### Step 3.7 — Stripe Terminal Manager **[AGENT]**

**Action**: Create `Services/StripeTerminalManager.swift` implementing `StripeTerminalManagerProtocol`.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Logic**:
- Configures Stripe Terminal SDK with a `ConnectionTokenProvider` that calls the backend.
- `connectToReader()` → discovers and connects to Reader M2 via BLE (or simulated reader in dev).
- `collectPayment(amount:clientSecret:)` → triggers `Terminal.shared.collectPaymentMethod()` then `Terminal.shared.confirmPaymentIntent()`.
- Fires delegate callbacks for state transitions.

**Initial development**: Use simulated discovery:
```swift
let config = DiscoveryConfiguration(
    discoveryMethod: .bluetoothScan,
    simulated: true
)
```

**Success**: `BuildProject` compiles.

**Ref**: `swift-protocols.md` §2, `deployment-targets.md` §2.2

---

### Step 3.8 — Checkout Screen UI **[AGENT]**

**Action**: Create SwiftUI views for the main POS checkout screen:

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Files**:
- `Views/Checkout/CheckoutView.swift` — Main view, switches on `POSFlowState`
- `Views/Checkout/WaitingForScanView.swift` — Pulsing barcode icon, "Scan an item!" with toddler colors
- `Views/Checkout/CartView.swift` — List of scanned items with photos, names, prices
- `Views/Checkout/ItemCardView.swift` — Individual item card (120pt min height, toddler design)
- `Views/Checkout/PaymentPromptView.swift` — "Tap Card" prompt with reader status

**All views must**:
- Use `ToddlerButtonStyle` for all buttons
- Use `ToddlerColors` exclusively — no raw hex in view code
- Use SF Symbols from the approved catalog (Rule 2)
- Meet 120×120pt touch targets (Rule 1)
- Apply `.fontDesign(.rounded)` on root (Rule 6)

**Success**: `BuildProject` compiles. `RenderPreview` renders the WaitingForScanView correctly.

**Ref**: `design-system.md` (all rules), `checkout-screen.excalidraw` (wireframe reference)

---

### Step 3.9 — Celebration View **[AGENT]**

**Action**: Create the celebration/success screen.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Files**:
- `Views/Celebration/CelebrationView.swift` — Full-screen celebration overlay
- `Views/Celebration/FireworksEffect.swift` — Particle/animation effect

**Logic**:
- Displays purchased item images bouncing with spring animations.
- Plays fireworks particle effect (can use SwiftUI Canvas + TimelineView).
- Plays celebratory sound (add audio file to Resources).
- Large "Go Again!" button (200pt+ width, green, ToddlerButtonStyle).
- `SuccessOverlay` with pulse animation per Rule 4.

**Success**: `BuildProject` compiles. `RenderPreview` renders the celebration view.

**Ref**: `design-system.md` Rule 4 (exaggerated success states), `payment-state-machine.md` (Celebrating state)

**Expectation**: `expectation.celebration-success`

---

### Step 3.10 — Error View **[AGENT]**

**Action**: Create `Views/ErrorView.swift` — full-screen modal error display.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Logic**:
- Full-screen overlay with semi-opaque background.
- Oversized SF Symbol error icon (`exclamationmark.triangle.fill`, 80pt+).
- Simple message text (minimal — toddler can't read, but parent can).
- Single "Dismiss" button (green, 200pt width, ToddlerButtonStyle).
- Conforms to Rule 9 (full-screen modal errors only, 2-button max).

**Success**: `BuildProject` compiles.

**Ref**: `design-system.md` Rule 9

---

### Step 3.11 — App Entry Point **[AGENT]**

**Action**: Update `App/StripeToddlerPOSApp.swift` to wire everything together.

**Tool**: `xcode-native` MCP → `XcodeUpdate`

**Logic**:
- Create and inject `POSViewModel` as `@StateObject`.
- Initialize `BarcodeScannerService`, `StripeTerminalManager`, `BackendAPIClient`.
- Set root view to `CheckoutView`.
- Apply `.fontDesign(.rounded)` on root view.
- Lock to landscape orientation.
- Set status bar to hidden.

**Success**: `BuildProject` succeeds. App launches on iPad Simulator showing the WaitingForScan screen.

**Ref**: `design-system.md` Rule 5 (landscape lock), Rule 6 (.fontDesign(.rounded))

---

### Step 3.12 — XCTest Suite **[AGENT]**

**Action**: Write XCTests for the iOS app.

**Tool**: `xcode-native` MCP → `XcodeWrite`

**Tests**:
- `POSViewModelTests` — Test state transitions: waitingForScan → cartActive → celebrating → waitingForScan.
- `BarcodeScannerTests` — Mock keyboard input, verify barcode aggregation and carriage return detection.
- `BackendAPIClientTests` — Mock URLSession, verify request formation for each endpoint.
- `DesignSystemTests` — Verify color token hex values, layout constants.

**Success**: `RunAllTests` passes all tests.

---

### Step 3.13 — Phase 3 Build Verification **[MANUAL + AGENT]**

**Action**: Full build and test cycle.

**Tool**: `xcode-native` MCP → `BuildProject` then `RunAllTests`

**Success**:
- Zero compiler errors.
- Zero test failures.
- App runs on iPad Simulator.
- WaitingForScan → CartActive transition works with simulated keyboard barcode input.

---

# Phase 4: Integration

Connect the iOS app to the live Worker backend and verify end-to-end flows.

---

### Step 4.1 — Deploy Worker to Production **[AGENT]**

**Action**: Merge the worker code to `main` and let CircleCI deploy.

**Tool**: `run_command` (git push, then verify CircleCI pipeline)

**Success**: The worker is live at `https://stripe-toddler.fintechnick.workers.dev`. `curl https://stripe-toddler.fintechnick.workers.dev/api/admin/inventory -H "X-Admin-API-Key: ..."` returns `[]`.

**Depends on**: Phase 2 complete, Step 2.13 CircleCI config

---

### Step 4.2 — Point iOS App to Live Worker **[AGENT]**

**Action**: Update `BackendAPIClient` base URL to the production worker endpoint.

**Tool**: `xcode-native` MCP → `XcodeUpdate`

**Change**: Set `baseURL` to `https://stripe-toddler.fintechnick.workers.dev`.

**Success**: `BuildProject` succeeds.

---

### Step 4.3 — Seed Production Inventory **[AGENT]**

**Action**: Create a few real inventory items in the production KV via the admin API.

**Tool**: `run_command` (curl)

```bash
curl -X POST https://stripe-toddler.fintechnick.workers.dev/api/admin/inventory \
  -H "X-Admin-API-Key: $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"barcode":"TOY001","name":"Red Fire Truck","price_cents":500,"image_url":"https://placehold.co/400","created_at":1700000000}'
```

**Success**: GET list endpoint returns the created items.

---

### Step 4.4 — End-to-End Simulator Test **[MANUAL + AGENT]**

**Action**: On the iPad Simulator:
1. Launch the app.
2. Type a barcode string (e.g. `TOY001`) + Enter via the Mac keyboard (simulates barcode scanner).
3. Verify item appears in the cart with correct name and price.
4. Tap Pay.
5. With simulated Stripe reader: verify payment flow completes.
6. Verify celebration screen appears.
7. Tap "Go Again".

**Tool**: Manual interaction on Simulator

**Success**: Full flow from scan → cart → pay → celebrate → reset completes without errors.

**Expectation**: `expectation.scan-item-success`, `expectation.checkout-success`

---

### Step 4.5 — Verify Transaction Logged in D1 **[AGENT]**

**Action**: After the simulator test, verify the transaction was logged.

**Tool**: `run_command` (curl)

```bash
curl https://stripe-toddler.fintechnick.workers.dev/api/admin/analytics \
  -H "X-Admin-API-Key: $ADMIN_API_KEY"
```

**Success**: Response includes the transaction from Step 4.4 with correct amount, items, and timestamp.

---

### Step 4.6 — App Attest Integration **[AGENT]**

**Action**: Implement the full App Attest flow in the iOS app:

1. On first launch, call `DCAppAttestService.shared.generateKey()`.
2. Request challenge from backend (`POST /api/attest/challenge`).
3. Call `DCAppAttestService.shared.attestKey(keyId, clientDataHash:)`.
4. Send attestation to backend (`POST /api/attest/verify`).
5. Store the key ID in Keychain for subsequent assertions.
6. On each API request, sign the request body with `DCAppAttestService.shared.generateAssertion(keyId, clientDataHash:)` and include the assertion in `X-App-Attest-Assertion` header.

**Tool**: `xcode-native` MCP → `XcodeWrite` / `XcodeUpdate`

> [!NOTE]
> App Attest only works on real devices, not the Simulator. During Simulator development, the assertion header should fall back to a placeholder value. The backend should accept this placeholder in dev/test mode.

**Success**: `BuildProject` compiles. On a real device, the attestation flow registers the device key in KV.

---

### Step 4.7 — Haptic Feedback Integration **[AGENT]**

**Action**: Add haptic feedback to all interactive elements per the design system Rule 8.

**Tool**: `xcode-native` MCP → `XcodeUpdate`

**Haptics to add**:
- Item scanned → `.impact(.medium)`
- Item removed → `.impact(.light)`
- Pay button tap → `.impact(.heavy)`
- Card tap detected → `.notification(.success)`
- Transaction captured → `.notification(.success)`
- Error → `.notification(.error)`

**Success**: `BuildProject` compiles.

**Ref**: `design-system.md` Rule 8

---

### Step 4.8 — Final Build + Full Test Suite **[MANUAL + AGENT]**

**Action**: Complete build and test verification.

**Tool**: `xcode-native` MCP → `BuildProject`, `RunAllTests`

**Checks**:
- Zero compiler errors
- Zero warnings from `XcodeListNavigatorIssues`
- All XCTests pass
- Commit all iOS changes

**Success**: Clean build, green tests, committed to Git.

---

# Phase 5: Hardware Validation

All steps are manual testing sessions on the Mac Studio with physical hardware.

---

### Step 5.1 — Pair Tera Barcode Scanner **[MANUAL]**

**Action**:
1. Put the Tera Mini scanner into Bluetooth pairing mode.
2. On the iPad: Settings → Bluetooth → pair the scanner.
3. Verify it appears as a keyboard input device.

**Success**: Scanning a barcode with the physical scanner types the barcode string into any text field on the iPad.

---

### Step 5.2 — Validate Barcode Scan-to-Cart Flow **[MANUAL]**

**Action**:
1. Deploy the app to the iPad via Xcode (Run on device).
2. Scan a physical barcode sticker with the Tera scanner.
3. Verify the item appears in the cart with correct photo, name, and price.
4. Scan a second item. Verify quantities and totals update.
5. Remove an item. Verify the total recalculates.

**Success**: Physical barcode scans trigger the same flow as keyboard simulation.

**Expectation**: `expectation.scan-item-success`

---

### Step 5.3 — Power and Pair Stripe Reader M2 **[MANUAL]**

**Action**:
1. Power on the Stripe Reader M2.
2. In the app, trigger checkout to start the Stripe Terminal discovery flow.
3. The SDK will discover and pair the reader via BLE.
4. Register the reader to the Terminal location (first-time only).

**Pre-requisite**: Step 0.1 (Terminal location exists).

**Success**: The app shows "Connected" status for the reader. Reader LEDs indicate successful pairing.

**Ref**: `deployment-targets.md` §2.2

---

### Step 5.4 — End-to-End Live Payment Test **[MANUAL]**

**Action**:
1. Scan 2–3 items with the Tera barcode scanner.
2. Tap the Pay button.
3. Tap a Stripe Terminal test card on the Reader M2.
4. Verify the payment is captured.
5. Verify the celebration animation plays.
6. Verify the transaction appears in the analytics API.
7. Tap "Go Again" and repeat.

**Success**: Money appears in the Stripe Dashboard (test mode). D1 contains the transaction. The toddler is happy.

**Expectation**: `expectation.checkout-success`, `expectation.celebration-success`

---

### Step 5.5 — Sideload to iPad for Standalone Use **[MANUAL]**

**Action**:
1. Connect iPad via USB to the Mac Studio.
2. In Xcode, select the iPad as the run destination.
3. Build and run — Xcode will sideload the app.
4. On the iPad: Settings → General → VPN & Device Management → Trust the developer certificate.
5. Disconnect from the Mac. Verify the app launches independently.

**Success**: The app runs standalone on the iPad without being tethered to the Mac.

> [!NOTE]
> The free Apple ID signing certificate expires after 7 days. After that, repeat this step to re-sign. If this becomes annoying, consider enrolling in the paid Apple Developer Program ($99/year) for a 365-day certificate.

**Ref**: `implementation-considerations.md` §4

---

## Verification Plan

### Automated Tests

**Rust Worker**:
```bash
cd worker
cargo clippy -- -D warnings    # Lint
cargo test                       # Unit tests
cargo build --target wasm32-unknown-unknown  # WASM build
```

**iOS App** (via xcode-native MCP):
- `RunAllTests` — Executes the full XCTest suite

**CI**:
- CircleCI pipeline runs lint + test + build on every push (worker only).

### Manual Verification

| Verification | How | Phase |
|-------------|-----|-------|
| Worker endpoints respond correctly | curl against `wrangler dev` | Phase 2 |
| iPad Simulator scan-to-checkout flow | Keyboard-simulated barcodes | Phase 4 |
| Physical barcode scanner works | Tera Mini + real iPad | Phase 5 |
| Stripe Reader M2 payment | Test card tap on real reader | Phase 5 |
| Transaction logged in D1 | Analytics API query | Phase 4/5 |
| Celebration animation quality | Visual inspection on device | Phase 5 |
| 7-day re-signing cycle | Wait 7 days and check | Post-Phase 5 |
