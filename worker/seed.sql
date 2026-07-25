INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at) VALUES ('t1', 'pi_1', 1000, 'captured', 100);
INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at) VALUES ('t2', 'pi_2', 2000, 'captured', 200);
INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at) VALUES ('t3', 'pi_3', 3000, 'captured', 300);
INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at) VALUES ('t4', 'pi_4', 4000, 'captured', 400);
INSERT INTO transactions (transaction_id, payment_intent_id, amount_cents, status, created_at) VALUES ('t5', 'pi_5', 5000, 'captured', 500);

INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity) VALUES ('t1', 'b1', 'Item 1', 1000, 1);
INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity) VALUES ('t2', 'b2', 'Item 2', 2000, 1);
INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity) VALUES ('t3', 'b3', 'Item 3', 3000, 1);
INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity) VALUES ('t4', 'b4', 'Item 4', 4000, 1);
INSERT INTO transaction_items (transaction_id, barcode, name, price_cents, quantity) VALUES ('t5', 'b5', 'Item 5', 5000, 1);
