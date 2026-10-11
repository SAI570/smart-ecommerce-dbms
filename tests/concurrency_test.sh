#!/usr/bin/env bash
# Two sessions try to buy the last 9 Mixer Grinders at the same time.
# Expected: exactly one succeeds, the other is rejected, stock = 0, no empty order.
# Usage: DB_USER=postgres ./concurrency_test.sh   (run on a freshly loaded database)
DB=${DB_NAME:-smart_ecommerce}; U=${DB_USER:-postgres}
P="psql -q -U $U -d $DB"
$P -c "BEGIN; CALL place_order(1,'[{\"product_id\":13,\"quantity\":9}]'::jsonb,NULL); SELECT pg_sleep(3); COMMIT;" >/tmp/sessionA.out 2>&1 &
sleep 1
echo "Session B (waits for A's row lock, then must fail):"
$P -c "CALL place_order(2,'[{\"product_id\":13,\"quantity\":9}]'::jsonb,NULL);" 2>&1 | head -1
wait
$P -t -c "SELECT 'mixer stock = ' || get_total_stock(13); SELECT 'orders without items = ' || COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_item i WHERE i.order_id=o.order_id);"
