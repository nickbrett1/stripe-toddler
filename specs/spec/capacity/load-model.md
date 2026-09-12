# Capacity & Load Model

This document outlines the expected capacity requirements, data footprint sizing, write IOPS, retention plans, and edge latency tolerances for the Stripe Toddler shop platform.

---

## 1. Workload Scale & Assumptions

The target audience for this application is a single 3-year-old toddler. This results in highly unique scale dynamics: extremely low overall volume, but extremely high sensitivity to latency and system errors.

### Key Usage Metrics
*   **Daily Transaction Volume**: 5 to 20 checkout events per active play session.
*   **Item Scans Per Session**: 10 to 50 items scanned.
*   **Active Inventory Size**: ~100 unique toys.
*   **Concurrent Users**: 1 (the toddler on the iPad) plus 1 (the administrator updating inventory).

---

## 2. Storage Sizing & Data Footprint

### 2.1 Cloudflare KV (Inventory Catalog)
*   **Record Size**: ~340 KB per inventory object — the item metadata (barcode string, name, price integer, timestamp) plus the photo encoded inline as a `data:image/...;base64,` URI. The image dominates the record: a ~250 KB JPEG inflates to ~333 KB once base64-encoded.
*   **Device Attestation Key Size**: ~300 bytes per registered key.
*   **Inventory Capacity Calculation**:
    $$\text{100 items} \times 340\text{ KB} \approx 34\text{ MB}$$
    $$\text{5 devices} \times 300\text{ bytes} \approx 1.5\text{ KB}$$
*   **Total KV Storage**: < 35 MB (well within Cloudflare KV's free tier of 1 GB).

### 2.2 Photo Storage
*   Photos are **not** kept in a separate object store. Each photo is embedded in its KV item record as a base64 `data:` URI (the `image_url` field in §2.1), so there is no Cloudflare R2 bucket and no separate storage footprint to size.
*   **Per-value ceiling**: Cloudflare KV caps a single value at 25 MiB. Because base64 inflates by ~33%, one photo must stay under roughly 18 MB to fit alongside its metadata. Toy photos are ~250 KB, so this is not a practical constraint.

### 2.3 Cloudflare D1 Relational DB (Sales Analytics)
*   **Transaction Table Row Size**: ~150 bytes (UUID, Payment Intent, Amount, Status, Timestamp).
*   **Transaction Items Row Size**: ~120 bytes (Line ID, Transaction ID, Barcode, Name, Price, Qty).
*   **Yearly Footprint Projection**:
    Assuming 20 transactions per day, with an average of 3 items per transaction:
    $$\text{Transactions per Year} = 20 \times 365 = 7,300\text{ rows}$$
    $$\text{Transaction Items per Year} = 7,300 \times 3 = 21,900\text{ rows}$$
    $$\text{Transaction Data Weight} = 7,300 \times 150\text{ bytes} \approx 1.1\text{ MB}$$
    $$\text{Line Item Data Weight} = 21,900 \times 120\text{ bytes} \approx 2.6\text{ MB}$$
*   **Total D1 Storage (per year)**: ~3.7 MB (including database indexes, total sizing is < 10 MB per year).

---

## 3. Operations & IOPS Model

Because play sessions are sporadic, transactions occur in bursts followed by long periods of zero load.

### 3.1 Peak IOPS (Play Session)
*   **Item Scan Reads**: Max 2 operations per second (limited by human physical capability to scan toy barcodes).
*   **D1 Writes (Captures)**: Max 1 write operation per 30 seconds (checkout process delay).
*   **Cloudflare Workers Executions**:
    $$\text{Lookup calls} \approx 10\text{ to }50\text{ per session}$$
    $$\text{Checkout calls} \approx 5\text{ to }20\text{ per session}$$

### 3.2 Key-Value Access Pattern Ratio
*   **Read / Write Ratio**: 100:1 (Read-heavy for catalog checks; writes occur only during admin addition of toys).

---

## 4. Latency Budget & SLA Targets

Toddlers exhibit high levels of frustration if UI feedback is delayed. The system is designed to meet strict latency thresholds.

| Operation | SLA Target (P95) | Bottleneck Component | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Barcode Lookup** | < 100 ms | KV Read / Edge network | Cache lookup response locally in iPad RAM once retrieved. |
| **Connection Token** | < 800 ms | Stripe API roundtrip | Prefetch connection tokens when iPad detects Bluetooth scanner connection. |
| **Payment Intent Create** | < 1500 ms | Stripe API roundtrip | Parallelize validation and creation requests on backend. |
| **Capture & Log Transaction** | < 1200 ms | Stripe Capture + D1 SQLite Write | Execute D1 log and Stripe capture concurrently, or return success to iPad on Stripe capture and write to D1 asynchronously. |
