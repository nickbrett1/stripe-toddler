DELETE FROM transaction_items;
DELETE FROM transactions;

WITH RECURSIVE
  cnt(x) AS (
     SELECT 1
     UNION ALL
     SELECT x+1 FROM cnt
      LIMIT 1000
  )
INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at)
SELECT
  'tx_' || x,
  'pi_' || x,
  x * 100,
  'captured',
  x * 1000
FROM cnt;

WITH RECURSIVE
  cnt(x) AS (
     SELECT 1
     UNION ALL
     SELECT x+1 FROM cnt
      LIMIT 1000
  )
INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity)
SELECT
  'tx_' || x,
  'bc_' || x,
  'Item ' || x,
  x * 100,
  1
FROM cnt;
