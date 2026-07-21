#!/bin/bash
set -euo pipefail

# Change to worker directory
cd "$(dirname "$0")/.."

echo "=== Seeding local Miniflare D1 ==="
npx -y wrangler d1 execute stripe_toddler_analytics --local --file ./migrations/0001_initial.sql 2>/dev/null || true

echo "=== Seeding local KV with test inventory ==="
npx -y wrangler kv key put --local --binding=STRIPE_TODDLER_INVENTORY \
  "item:TEST001" '{"barcode":"TEST001","name":"Red Fire Truck","price_cents":500,"image_url":"https://placehold.co/400","created_at":1700000000}'

npx -y wrangler kv key put --local --binding=STRIPE_TODDLER_INVENTORY \
  "item:TEST002" '{"barcode":"TEST002","name":"Stuffed Teddy Bear","price_cents":300,"image_url":"https://placehold.co/400","created_at":1700000000}'

npx -y wrangler kv key put --local --binding=STRIPE_TODDLER_INVENTORY \
  "item:TEST003" '{"barcode":"TEST003","name":"Yellow Rubber Duck","price_cents":100,"image_url":"https://placehold.co/400","created_at":1700000000}'

echo "=== Local seed complete ==="
