use worker::*;
use wasm_bindgen::JsValue;

mod models;
use models::*;

fn cors_headers() -> Result<Headers> {
    let mut headers = Headers::new();
    headers.set("Access-Control-Allow-Origin", "*")?;
    headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")?;
    headers.set("Access-Control-Allow-Headers", "Content-Type, X-Admin-API-Key, X-App-Attest-Assertion")?;
    headers.set("Access-Control-Max-Age", "86400")?;
    Ok(headers)
}

fn cors_response() -> Result<Response> {
    let mut response = Response::empty()?;
    *response.headers_mut() = cors_headers()?;
    Ok(response)
}

fn error_response(msg: &str, status: u16) -> Result<Response> {
    let mut response = Response::error(msg, status)?;
    *response.headers_mut() = cors_headers()?;
    Ok(response)
}

fn json_response<T: serde::Serialize>(data: &T) -> Result<Response> {
    let mut response = Response::from_json(data)?;
    *response.headers_mut() = cors_headers()?;
    Ok(response)
}

// Authentication Helpers
fn validate_admin_auth(req: &Request, env: &Env) -> Result<bool> {
    let expected_key = match env.var("ADMIN_API_KEY") {
        Ok(k) => k.to_string(),
        Err(_) => return Ok(false),
    };
    let headers = req.headers();
    if let Ok(Some(provided_key)) = headers.get("X-Admin-API-Key") {
        return Ok(provided_key == expected_key);
    }
    Ok(false)
}

fn validate_app_attest_auth(req: &Request) -> Result<bool> {
    let headers = req.headers();
    if let Ok(Some(assertion)) = headers.get("X-App-Attest-Assertion") {
        return Ok(!assertion.trim().is_empty());
    }
    Ok(false)
}

#[event(fetch)]
pub async fn main(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    // Handle CORS preflight requests
    if req.method() == Method::Options {
        return cors_response();
    }

    let router = Router::new();
    router
        // 1. App Attest endpoints
        .post_async("/api/attest/challenge", |mut req, ctx| async move {
            let now = Date::now().as_millis() / 1000;
            let expires_at = now + 300;
            let challenge = uuid::Uuid::new_v4().to_string();

            let kv = match ctx.env.kv("STRIPE_TODDLER_INVENTORY") {
                Ok(k) => k,
                Err(e) => return error_response(&format!("KV Error: {:?}", e), 500),
            };

            if let Err(e) = kv.put(&format!("challenge:{}", challenge), now)
                .map_err(|e| e)?
                .expiration_ttl(300)
                .execute()
                .await 
            {
                return error_response(&format!("KV Put Error: {:?}", e), 500);
            }

            let resp = AttestChallengeResponse {
                challenge,
                expires_at,
            };
            json_response(&resp)
        })
        .post_async("/api/attest/verify", |mut req, ctx| async move {
            let req_body: VerifyAttestRequest = match req.json().await {
                Ok(b) => b,
                Err(_) => return error_response("Malformed JSON request", 400),
            };

            let kv = match ctx.env.kv("STRIPE_TODDLER_INVENTORY") {
                Ok(k) => k,
                Err(e) => return error_response(&format!("KV Error: {:?}", e), 500),
            };

            let challenge_key = format!("challenge:{}", req_body.challenge);
            let challenge_val: Option<String> = match kv.get(&challenge_key).text().await {
                Ok(v) => v,
                Err(e) => return error_response(&format!("KV Get Error: {:?}", e), 500),
            };

            if challenge_val.is_none() {
                return error_response("Invalid or expired challenge", 400);
            }

            // Remove challenge from KV to prevent replay
            let _ = kv.delete(&challenge_key).await;

            let now = Date::now().as_millis() / 1000;
            let record = DeviceAttestationRecord {
                device_id: req_body.device_id.clone(),
                key_id: req_body.key_id.clone(),
                registered_at: now,
                last_counter_value: 0,
            };

            let device_key = format!("attest:device:{}", req_body.device_id);
            let serialized = match serde_json::to_string(&record) {
                Ok(s) => s,
                Err(_) => return error_response("Serialization error", 500),
            };

            if let Err(e) = kv.put(&device_key, serialized).map_err(|e| e)?.execute().await {
                return error_response(&format!("KV Put Error: {:?}", e), 500);
            }

            json_response(&serde_json::json!({ "status": "success" }))
        })

        // 2. POS Client endpoints
        .get_async("/api/pos/inventory/:barcode", |req, ctx| async move {
            if !validate_app_attest_auth(&req)? {
                return error_response("Unauthorized: Missing App Attest assertion", 401);
            }

            let barcode = match ctx.param("barcode") {
                Some(b) => b,
                None => return error_response("Missing barcode parameter", 400),
            };

            let kv = match ctx.env.kv("STRIPE_TODDLER_INVENTORY") {
                Ok(k) => k,
                Err(e) => return error_response(&format!("KV Error: {:?}", e), 500),
            };

            let item_key = format!("item:{}", barcode);
            let item_str: Option<String> = match kv.get(&item_key).text().await {
                Ok(v) => v,
                Err(e) => return error_response(&format!("KV Get Error: {:?}", e), 500),
            };

            match item_str {
                Some(s) => {
                    let item: InventoryItem = match serde_json::from_str(&s) {
                        Ok(i) => i,
                        Err(_) => return error_response("Failed to deserialize inventory item", 500),
                    };
                    json_response(&item)
                }
                None => error_response("Item not found", 404),
            }
        })
        .post_async("/api/terminal/connection-token", |req, ctx| async move {
            if !validate_app_attest_auth(&req)? {
                return error_response("Unauthorized: Missing App Attest assertion", 401);
            }

            let stripe_key = match ctx.env.var("STRIPE_SECRET_KEY") {
                Ok(k) => k.to_string(),
                Err(_) => return error_response("Stripe API key not configured", 500),
            };

            let mut headers = Headers::new();
            headers.set("Authorization", &format!("Bearer {}", stripe_key))?;
            headers.set("Content-Type", "application/x-www-form-urlencoded")?;

            let request = match Request::new_with_init(
                "https://api.stripe.com/v1/terminal/connection_tokens",
                &RequestInit::new()
                    .with_method(Method::Post)
                    .with_headers(headers),
            ) {
                Ok(r) => r,
                Err(_) => return error_response("Failed to construct Stripe request", 500),
            };

            let mut stripe_response = match Fetch::Request(request).send().await {
                Ok(res) => res,
                Err(e) => return error_response(&format!("Stripe API Fetch Error: {:?}", e), 502),
            };

            let stripe_text = stripe_response.text().await?;
            let stripe_json: serde_json::Value = match serde_json::from_str(&stripe_text) {
                Ok(j) => j,
                Err(_) => return error_response("Failed to parse Stripe response", 502),
            };

            if let Some(secret) = stripe_json.get("secret").and_then(|s| s.as_str()) {
                json_response(&serde_json::json!({ "secret": secret }))
            } else {
                error_response(&format!("Invalid Stripe Token Response: {}", stripe_text), 502)
            }
        })
        .post_async("/api/terminal/payment-intent", |mut req, ctx| async move {
            if !validate_app_attest_auth(&req)? {
                return error_response("Unauthorized: Missing App Attest assertion", 401);
            }

            let req_data: CreatePaymentIntentRequest = match req.json().await {
                Ok(d) => d,
                Err(_) => return error_response("Malformed JSON payload", 400),
            };

            if req_data.amount_cents < 100 {
                return error_response("Amount must be at least 100 cents", 400);
            }

            let stripe_key = match ctx.env.var("STRIPE_SECRET_KEY") {
                Ok(k) => k.to_string(),
                Err(_) => return error_response("Stripe API key not configured", 500),
            };

            let mut headers = Headers::new();
            headers.set("Authorization", &format!("Bearer {}", stripe_key))?;
            headers.set("Content-Type", "application/x-www-form-urlencoded")?;

            let body = format!(
                "amount={}&currency=usd&payment_method_types[]=card_present&capture_method=manual",
                req_data.amount_cents
            );

            let request = match Request::new_with_init(
                "https://api.stripe.com/v1/payment_intents",
                &RequestInit::new()
                    .with_method(Method::Post)
                    .with_headers(headers)
                    .with_body(Some(body.into())),
            ) {
                Ok(r) => r,
                Err(_) => return error_response("Failed to construct Stripe request", 500),
            };

            let mut stripe_response = match Fetch::Request(request).send().await {
                Ok(res) => res,
                Err(e) => return error_response(&format!("Stripe API Fetch Error: {:?}", e), 502),
            };

            let stripe_text = stripe_response.text().await?;
            let stripe_json: serde_json::Value = match serde_json::from_str(&stripe_text) {
                Ok(j) => j,
                Err(_) => return error_response("Failed to parse Stripe response", 502),
            };

            let intent_id = stripe_json.get("id").and_then(|v| v.as_str());
            let client_secret = stripe_json.get("client_secret").and_then(|v| v.as_str());

            match (intent_id, client_secret) {
                (Some(id), Some(secret)) => {
                    let payload = CreatePaymentIntentResponse {
                        payment_intent_id: id.to_string(),
                        client_secret: secret.to_string(),
                    };
                    json_response(&payload)
                }
                _ => error_response(&format!("Stripe payment intent creation failed: {}", stripe_text), 502),
            }
        })
        .post_async("/api/terminal/capture", |mut req, ctx| async move {
            if !validate_app_attest_auth(&req)? {
                return error_response("Unauthorized: Missing App Attest assertion", 401);
            }

            let req_data: CaptureTransactionRequest = match req.json().await {
                Ok(d) => d,
                Err(_) => return error_response("Malformed JSON payload", 400),
            };

            let stripe_key = match ctx.env.var("STRIPE_SECRET_KEY") {
                Ok(k) => k.to_string(),
                Err(_) => return error_response("Stripe API key not configured", 500),
            };

            let mut headers = Headers::new();
            headers.set("Authorization", &format!("Bearer {}", stripe_key))?;
            headers.set("Content-Type", "application/x-www-form-urlencoded")?;

            let capture_url = format!(
                "https://api.stripe.com/v1/payment_intents/{}/capture",
                req_data.payment_intent_id
            );

            let request = match Request::new_with_init(
                &capture_url,
                &RequestInit::new()
                    .with_method(Method::Post)
                    .with_headers(headers),
            ) {
                Ok(r) => r,
                Err(_) => return error_response("Failed to construct Stripe request", 500),
            };

            let mut stripe_response = match Fetch::Request(request).send().await {
                Ok(res) => res,
                Err(e) => return error_response(&format!("Stripe API Fetch Error: {:?}", e), 502),
            };

            let stripe_text = stripe_response.text().await?;
            let stripe_json: serde_json::Value = match serde_json::from_str(&stripe_text) {
                Ok(j) => j,
                Err(_) => return error_response("Failed to parse Stripe response", 502),
            };

            let status = stripe_json.get("status").and_then(|v| v.as_str()).unwrap_or("");
            if status != "succeeded" {
                return error_response(&format!("Stripe payment intent capture failed. Status: {}. Response: {}", status, stripe_text), 400);
            }

            let db = match ctx.env.d1("DB") {
                Ok(d) => d,
                Err(e) => return error_response(&format!("D1 Error: {:?}", e), 500),
            };

            let tx_id = uuid::Uuid::new_v4().to_string();
            let now = Date::now().as_millis() / 1000;

            // Log Transaction in D1
            let tx_stmt = match db.prepare("INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at) VALUES (?, ?, ?, ?, ?)") {
                Ok(s) => s,
                Err(e) => return error_response(&format!("D1 SQL Preparation Error: {:?}", e), 500),
            };

            let bound_tx_stmt = match tx_stmt.bind(&[
                JsValue::from_str(&tx_id),
                JsValue::from_str(&req_data.payment_intent_id),
                JsValue::from_f64(req_data.amount_cents as f64),
                JsValue::from_str("captured"),
                JsValue::from_f64(now as f64),
            ]) {
                Ok(b) => b,
                Err(e) => return error_response(&format!("D1 SQL Binding Error: {:?}", e), 500),
            };

            if let Err(e) = bound_tx_stmt.run().await {
                return error_response(&format!("D1 Transaction Execution Error: {:?}", e), 500);
            }

            // Log Line Items
            for item in req_data.items {
                let item_stmt = match db.prepare("INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity) VALUES (?, ?, ?, ?, ?)") {
                    Ok(s) => s,
                    Err(e) => return error_response(&format!("D1 SQL Item Prep Error: {:?}", e), 500),
                };

                let bound_item_stmt = match item_stmt.bind(&[
                    JsValue::from_str(&tx_id),
                    JsValue::from_str(&item.barcode),
                    JsValue::from_str(&item.name),
                    JsValue::from_f64(item.price_cents as f64),
                    JsValue::from_f64(item.quantity as f64),
                ]) {
                    Ok(b) => b,
                    Err(e) => return error_response(&format!("D1 SQL Item Binding Error: {:?}", e), 500),
                };

                if let Err(e) = bound_item_stmt.run().await {
                    return error_response(&format!("D1 Item Insert Error: {:?}", e), 500);
                }
            }

            let resp = CaptureTransactionResponse {
                status: "captured".to_string(),
                transaction_id: tx_id,
            };
            json_response(&resp)
        })

        // 3. Admin Executive endpoints
        .get_async("/api/admin/inventory", |req, ctx| async move {
            if !validate_admin_auth(&req, &ctx.env)? {
                return error_response("Unauthorized: Invalid Admin API Key", 401);
            }

            let kv = match ctx.env.kv("STRIPE_TODDLER_INVENTORY") {
                Ok(k) => k,
                Err(e) => return error_response(&format!("KV Error: {:?}", e), 500),
            };

            let list_result = match kv.list().prefix("item:".to_string()).execute().await {
                Ok(r) => r,
                Err(e) => return error_response(&format!("KV List Error: {:?}", e), 500),
            };

            let mut items = Vec::new();
            for key in list_result.keys {
                if let Ok(Some(item_str)) = kv.get(&key.name).text().await {
                    if let Ok(item) = serde_json::from_str::<InventoryItem>(&item_str) {
                        items.push(item);
                    }
                }
            }

            json_response(&items)
        })
        .post_async("/api/admin/inventory", |mut req, ctx| async move {
            if !validate_admin_auth(&req, &ctx.env)? {
                return error_response("Unauthorized: Invalid Admin API Key", 401);
            }

            let item: InventoryItem = match req.json().await {
                Ok(i) => i,
                Err(_) => return error_response("Malformed InventoryItem JSON", 400),
            };

            let kv = match ctx.env.kv("STRIPE_TODDLER_INVENTORY") {
                Ok(k) => k,
                Err(e) => return error_response(&format!("KV Error: {:?}", e), 500),
            };

            let item_key = format!("item:{}", item.barcode);
            let serialized = match serde_json::to_string(&item) {
                Ok(s) => s,
                Err(_) => return error_response("Failed to serialize item", 500),
            };

            if let Err(e) = kv.put(&item_key, serialized).map_err(|e| e)?.execute().await {
                return error_response(&format!("KV Save Error: {:?}", e), 500);
            }

            json_response(&serde_json::json!({ "status": "success", "barcode": item.barcode }))
        })
        .post_async("/api/admin/inventory/upload", |mut req, ctx| async move {
            if !validate_admin_auth(&req, &ctx.env)? {
                return error_response("Unauthorized: Invalid Admin API Key", 401);
            }

            let form = match req.form_data().await {
                Ok(f) => f,
                Err(_) => return error_response("Malformed Multipart Form Payload", 400),
            };

            let barcode = match form.get("barcode") {
                Some(FormEntry::Field(s)) => s,
                _ => return error_response("Missing barcode field", 400),
            };

            let file = match form.get("image") {
                Some(FormEntry::File(f)) => f,
                _ => return error_response("Missing image file field", 400),
            };

            let bytes = match file.bytes().await {
                Ok(b) => b,
                Err(_) => return error_response("Failed to read image bytes", 400),
            };

            if bytes.len() > 5 * 1024 * 1024 {
                return error_response("Image file exceeds the 5 MB size limit", 413);
            }

            let bucket = match ctx.env.bucket("IMAGES") {
                Ok(b) => b,
                Err(e) => return error_response(&format!("R2 Bucket Binding Error: {:?}", e), 500),
            };

            let ext = match file.content_type().as_deref() {
                Some("image/png") => "png",
                _ => "jpg",
            };

            let key = format!("images/{}.{}", barcode, ext);
            if let Err(e) = bucket.put(&key, bytes).await {
                return error_response(&format!("R2 Upload Failed: {:?}", e), 500);
            }

            let account_id = match ctx.env.var("CLOUDFLARE_ACCOUNT_ID") {
                Ok(a) => a.to_string(),
                Err(_) => "default".to_string(),
            };

            let image_url = format!("https://stripe-toddler-images.{}.r2.dev/{}", account_id, key);
            let resp = ImageUploadResponse {
                image_url,
                barcode,
            };
            json_response(&resp)
        })
        .get_async("/api/admin/analytics", |req, ctx| async move {
            if !validate_admin_auth(&req, &ctx.env)? {
                return error_response("Unauthorized: Invalid Admin API Key", 401);
            }

            let limit = req.url()?.query_pairs()
                .find(|(k, _)| k == "limit")
                .map(|(_, v)| v.parse::<u32>().unwrap_or(100))
                .unwrap_or(100);

            let offset = req.url()?.query_pairs()
                .find(|(k, _)| k == "offset")
                .map(|(_, v)| v.parse::<u32>().unwrap_or(0))
                .unwrap_or(0);

            let db = match ctx.env.d1("DB") {
                Ok(d) => d,
                Err(e) => return error_response(&format!("D1 Error: {:?}", e), 500),
            };

            let tx_stmt = match db.prepare("SELECT * FROM transactions ORDER BY created_at DESC LIMIT ? OFFSET ?") {
                Ok(s) => s,
                Err(e) => return error_response(&format!("D1 Prep Error: {:?}", e), 500),
            };

            let bound_tx_stmt = match tx_stmt.bind(&[
                JsValue::from_f64(limit as f64),
                JsValue::from_f64(offset as f64),
            ]) {
                Ok(b) => b,
                Err(e) => return error_response(&format!("D1 Bind Error: {:?}", e), 500),
            };

            let tx_rows = match bound_tx_stmt.all().await {
                Ok(r) => r,
                Err(e) => return error_response(&format!("D1 Exec Error: {:?}", e), 500),
            };

            let tx_records: Vec<TransactionDbRecord> = match tx_rows.results() {
                Ok(r) => r,
                Err(e) => return error_response(&format!("D1 Parse Error: {:?}", e), 500),
            };

            let mut results = Vec::new();
            for tx in tx_records {
                let items_stmt = match db.prepare("SELECT * FROM transaction_items WHERE transaction_id = ?") {
                    Ok(s) => s,
                    Err(e) => return error_response(&format!("D1 Item Prep Error: {:?}", e), 500),
                };

                let bound_items_stmt = match items_stmt.bind(&[JsValue::from_str(&tx.transaction_id)]) {
                    Ok(b) => b,
                    Err(e) => return error_response(&format!("D1 Item Bind Error: {:?}", e), 500),
                };

                let items_rows = match bound_items_stmt.all().await {
                    Ok(r) => r,
                    Err(e) => return error_response(&format!("D1 Item Exec Error: {:?}", e), 500),
                };

                let items_records: Vec<TransactionItemRecord> = match items_rows.results() {
                    Ok(r) => r,
                    Err(e) => return error_response(&format!("D1 Item Parse Error: {:?}", e), 500),
                };

                let api_items: Vec<LineItem> = items_records.into_iter().map(|item| LineItem {
                    barcode: item.barcode,
                    name: item.name,
                    price_cents: item.price_cents,
                    quantity: item.quantity,
                }).collect();

                results.push(TransactionRecord {
                    transaction_id: tx.transaction_id,
                    payment_intent_id: tx.payment_intent_id,
                    amount_cents: tx.amount_cents,
                    status: tx.status,
                    created_at: tx.created_at,
                    items: api_items,
                });
            }

            json_response(&results)
        })
        .run(req, env)
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_inventory_item_serialization() {
        let item = InventoryItem {
            barcode: "TEST99".to_string(),
            name: "Magic Wand".to_string(),
            price_cents: 999,
            image_url: "https://placehold.co/400".to_string(),
            created_at: 123456789,
        };

        let serialized = serde_json::to_string(&item).unwrap();
        let deserialized: InventoryItem = serde_json::from_str(&serialized).unwrap();
        assert_eq!(item, deserialized);
    }

    #[test]
    fn test_payment_intent_request_validation() {
        let req = CreatePaymentIntentRequest {
            amount_cents: 50,
            barcodes: vec!["BARCODE".to_string()],
        };
        assert!(req.amount_cents < 100);
    }

    #[test]
    fn test_capture_request_serialization() {
        let req = CaptureTransactionRequest {
            payment_intent_id: "pi_123".to_string(),
            amount_cents: 1000,
            items: vec![LineItem {
                barcode: "BARCODE".to_string(),
                name: "Teddy".to_string(),
                price_cents: 1000,
                quantity: 1,
            }],
        };

        let serialized = serde_json::to_string(&req).unwrap();
        let deserialized: CaptureTransactionRequest = serde_json::from_str(&serialized).unwrap();
        assert_eq!(deserialized.payment_intent_id, "pi_123");
        assert_eq!(deserialized.items[0].name, "Teddy");
    }
}
