-- =====================================================================
-- File 09: Transaction (ACID) demonstration.  Run manually in psql, e.g.
--     psql -d smart_ecommerce -f 09_transaction_demo.sql
-- Everything is rolled back at the end, so the data is left unchanged.
-- =====================================================================
\set ON_ERROR_STOP off
\echo '== Atomicity: an order with one bad line leaves NOTHING behind'
BEGIN;
SELECT COUNT(*) AS orders_before, get_total_stock(1) AS mouse_stock_before FROM orders;   -- note numbers
SAVEPOINT before_order;
DO $$ DECLARE v INT; BEGIN
   CALL place_order(1, '[{"product_id":1,"quantity":2},{"product_id":2,"quantity":99999}]', v);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'order failed -> %', SQLERRM;
END $$;
SELECT COUNT(*) AS orders_after, get_total_stock(1) AS mouse_stock_after FROM orders;     -- unchanged
ROLLBACK;

\echo '== Consistency: constraints stop an impossible state'
BEGIN;
UPDATE inventory SET quantity_available = -5 WHERE inventory_id = 1;                      -- fails: CHECK
ROLLBACK;

\echo '== Isolation (try in two psql windows)'
\echo '   Window A:  BEGIN; CALL place_order(1, ''[{"product_id":13,"quantity":9}]'', NULL);   -- do not COMMIT yet'
\echo '   Window B:  CALL place_order(2, ''[{"product_id":13,"quantity":9}]'', NULL);          -- waits on the row lock'
\echo '   Window A:  COMMIT;   -> B resumes and is REJECTED (only 9 units existed): no overselling.'

\echo '== Durability: committed work survives a restart (write-ahead log)'
BEGIN;
CALL place_order(3, '[{"product_id":20,"quantity":1}]', NULL);
SAVEPOINT s1;
DO $$ BEGIN CALL cancel_order((SELECT MAX(order_id) FROM orders)); END $$;
ROLLBACK TO SAVEPOINT s1;          -- undo only the cancellation
SELECT order_id, order_status FROM orders ORDER BY order_id DESC LIMIT 1;                 -- still PLACED
ROLLBACK;                          -- a real run would COMMIT here
