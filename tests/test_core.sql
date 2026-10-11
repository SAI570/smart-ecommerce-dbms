-- =====================================================================
-- Automated tests for the database logic.  Everything runs inside one
-- transaction that is ROLLED BACK at the end, so the data is left untouched.
-- Run:  psql -d smart_ecommerce -f test_core.sql      (look for "ALL TESTS PASSED")
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_sql TEXT, p_label TEXT) RETURNS VOID LANGUAGE plpgsql AS $f$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'PASS  %  (rejected: %)', p_label, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL  %: statement should have been rejected', p_label;
END $f$;

-- T1 reserved stock always equals the open (PLACED/CONFIRMED) order lines ----
DO $$ DECLARE bad INT; BEGIN
  SELECT COUNT(*) INTO bad FROM inventory i
   WHERE i.quantity_reserved <> COALESCE((SELECT SUM(oi.quantity) FROM order_item oi JOIN orders o USING (order_id)
          WHERE oi.product_id=i.product_id AND oi.warehouse_id=i.warehouse_id
            AND o.order_status IN ('PLACED','CONFIRMED')),0);
  IF bad > 0 THEN RAISE EXCEPTION 'FAIL T1: % inventory rows with wrong reserved qty', bad; END IF;
  RAISE WARNING 'PASS  T1 reserved stock matches open orders';
END $$;

-- T2 stored order totals equal get_order_total() ----------------------------
DO $$ DECLARE bad INT; BEGIN
  SELECT COUNT(*) INTO bad FROM orders WHERE total_amount <> get_order_total(order_id);
  IF bad > 0 THEN RAISE EXCEPTION 'FAIL T2: % orders with wrong total', bad; END IF;
  RAISE WARNING 'PASS  T2 order totals consistent';
END $$;

-- T3 stock conservation: stock + sold units == opening stock + received POs - ...
-- (every unit sold left available stock; shipped units left reserved too)
DO $$ DECLARE v INT; a1 INT; a2 INT; r2 INT; o1 INT; o2 INT; BEGIN
  a1 := get_total_stock(1);
  CALL place_order(1, '[{"product_id":1,"quantity":7}]', v);
  a2 := get_total_stock(1);
  IF a1 - a2 <> 7 THEN RAISE EXCEPTION 'FAIL T3: stock fell by % not 7', a1 - a2; END IF;
  IF (SELECT total_amount FROM orders WHERE order_id=v) <> 7*799 THEN RAISE EXCEPTION 'FAIL T3 total'; END IF;
  RAISE WARNING 'PASS  T3 place_order reduces stock by quantity and sets total';
END $$;

-- T4 insufficient stock: rejected, nothing left behind ------------------------
DO $$ DECLARE n1 INT; n2 INT; s1 INT; s2 INT; v INT; BEGIN
  SELECT COUNT(*) INTO n1 FROM orders; s1 := get_total_stock(2);
  BEGIN
    CALL place_order(1, '[{"product_id":2,"quantity":5},{"product_id":3,"quantity":9999}]', v);
    RAISE EXCEPTION 'FAIL T4: oversell accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Insufficient stock%' THEN RAISE; END IF;
  END;
  SELECT COUNT(*) INTO n2 FROM orders; s2 := get_total_stock(2);
  IF n1 <> n2 OR s1 <> s2 THEN RAISE EXCEPTION 'FAIL T4: partial order left behind'; END IF;
  RAISE WARNING 'PASS  T4 oversell rejected and whole order rolled back';
END $$;

-- T5 a line is split over warehouses when one cannot cover it --------------------
DO $$ DECLARE v INT; n INT; q INT; BEGIN
  CALL place_order(2, '[{"product_id":5,"quantity":150}]', v);   -- biggest warehouse holds 76
  SELECT COUNT(*), SUM(quantity) INTO n, q FROM order_item WHERE order_id = v;
  IF n < 2 OR q <> 150 THEN RAISE EXCEPTION 'FAIL T5: expected split lines totalling 150, got % lines / %', n, q; END IF;
  RAISE WARNING 'PASS  T5 order line split across % warehouses', n;
END $$;

-- T6 cancel restores stock exactly -------------------------------------------------
DO $$ DECLARE v INT; before INT; mid INT; after INT; res INT; BEGIN
  before := get_total_stock(4);
  CALL place_order(3, '[{"product_id":4,"quantity":12}]', v);
  mid := get_total_stock(4);
  CALL cancel_order(v);
  after := get_total_stock(4);
  SELECT SUM(quantity_reserved) INTO res FROM inventory WHERE product_id = 4;
  IF mid <> before - 12 OR after <> before THEN RAISE EXCEPTION 'FAIL T6: % / % / %', before, mid, after; END IF;
  IF (SELECT order_status FROM orders WHERE order_id=v) <> 'CANCELLED' THEN RAISE EXCEPTION 'FAIL T6 status'; END IF;
  RAISE WARNING 'PASS  T6 cancel_order restores stock (% -> % -> %)', before, mid, after;
END $$;

SELECT pg_temp.expect_error($$CALL cancel_order(1)$$, 'T7 cancelling a DELIVERED order');
SELECT pg_temp.expect_error($$CALL place_order(13, '[{"product_id":1,"quantity":1}]', NULL)$$, 'T8 INACTIVE customer cannot order');
SELECT pg_temp.expect_error($$CALL place_order(1, '[]', NULL)$$, 'T9 empty order');
SELECT pg_temp.expect_error($$CALL place_order(1, '[{"product_id":999,"quantity":1}]', NULL)$$, 'T10 unknown product');

-- T11 payments: failed -> retry -> success; COD; double payment ---------------------
DO $$ DECLARE v INT; r VARCHAR; BEGIN
  CALL place_order(4, '[{"product_id":1,"quantity":1}]', v);
  CALL record_payment(v, 'CARD', false, r);
  IF r <> 'FAILED' OR (SELECT order_status FROM orders WHERE order_id=v) <> 'PLACED' THEN RAISE EXCEPTION 'FAIL T11a'; END IF;
  CALL record_payment(v, 'UPI', true, r);
  IF r <> 'SUCCESS' OR (SELECT order_status FROM orders WHERE order_id=v) <> 'CONFIRMED' THEN RAISE EXCEPTION 'FAIL T11b'; END IF;
  IF (SELECT COUNT(*) FROM payment WHERE order_id=v) <> 1 THEN RAISE EXCEPTION 'FAIL T11c one payment row'; END IF;
  BEGIN CALL record_payment(v, 'UPI', true, r); RAISE EXCEPTION 'FAIL T11d double pay'; EXCEPTION WHEN raise_exception THEN
     IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  RAISE WARNING 'PASS  T11 payment fail/retry/success and double-payment guard';

  CALL place_order(4, '[{"product_id":1,"quantity":1}]', v);
  CALL record_payment(v, 'COD', true, r);
  IF r <> 'PENDING' OR (SELECT order_status FROM orders WHERE order_id=v) <> 'CONFIRMED' THEN RAISE EXCEPTION 'FAIL T11e COD'; END IF;
  CALL update_order_status(v, 'SHIPPED'); CALL update_order_status(v, 'DELIVERED');
  IF (SELECT payment_status FROM payment WHERE order_id=v) <> 'SUCCESS' THEN RAISE EXCEPTION 'FAIL T11f COD settle'; END IF;
  RAISE WARNING 'PASS  T12 COD: PENDING -> SUCCESS on delivery';
END $$;

-- T13 shipping releases the reserved stock ----------------------------------------------
DO $$ DECLARE v INT; r VARCHAR; res1 INT; res2 INT; BEGIN
  CALL place_order(5, '[{"product_id":19,"quantity":3}]', v);
  CALL record_payment(v, 'UPI', true, r);
  SELECT SUM(quantity_reserved) INTO res1 FROM inventory WHERE product_id=19;
  CALL update_order_status(v, 'SHIPPED');
  SELECT SUM(quantity_reserved) INTO res2 FROM inventory WHERE product_id=19;
  IF res1 - res2 <> 3 THEN RAISE EXCEPTION 'FAIL T13'; END IF;
  RAISE WARNING 'PASS  T13 SHIPPED releases reserved stock';
END $$;

SELECT pg_temp.expect_error($$UPDATE orders SET order_status='DELIVERED' WHERE order_id=18$$, 'T14 PLACED -> DELIVERED skip is blocked');
SELECT pg_temp.expect_error($$UPDATE orders SET order_status='PLACED' WHERE order_id=1$$, 'T15 DELIVERED -> PLACED is blocked');

-- T16 TRIGGER 2: falling below reorder level raises exactly one PO --------------------------
DO $$ DECLARE v INT; npo1 INT; npo2 INT; npo3 INT; po RECORD; BEGIN
  -- product 9 (Running Shoes) has 37, reorder level 15, no open PO
  SELECT COUNT(*) INTO npo1 FROM purchase_order WHERE product_id=9 AND po_status='CREATED';
  CALL place_order(6, '[{"product_id":9,"quantity":10}]', v);     -- 37 -> 27, still fine
  SELECT COUNT(*) INTO npo2 FROM purchase_order WHERE product_id=9 AND po_status='CREATED';
  IF npo2 <> npo1 THEN RAISE EXCEPTION 'FAIL T16a PO raised too early'; END IF;
  CALL place_order(6, '[{"product_id":9,"quantity":15}]', v);     -- 27 -> 12  (< 15)
  SELECT COUNT(*) INTO npo2 FROM purchase_order WHERE product_id=9 AND po_status='CREATED';
  IF npo2 <> 1 THEN RAISE EXCEPTION 'FAIL T16b expected 1 PO, got %', npo2; END IF;
  CALL place_order(6, '[{"product_id":9,"quantity":2}]', v);      -- still below: no duplicate PO
  SELECT COUNT(*) INTO npo3 FROM purchase_order WHERE product_id=9 AND po_status='CREATED';
  IF npo3 <> 1 THEN RAISE EXCEPTION 'FAIL T16c duplicate PO'; END IF;
  SELECT * INTO po FROM purchase_order WHERE product_id=9 AND po_status='CREATED';
  IF po.supplier_id <> 3 OR po.expected_delivery <> CURRENT_DATE + 8 OR po.quantity_ordered <> 45 - 12 THEN
     RAISE EXCEPTION 'FAIL T16d PO details % % %', po.supplier_id, po.expected_delivery, po.quantity_ordered; END IF;
  RAISE WARNING 'PASS  T16 trigger raised one PO to the right supplier (qty %, due %)', po.quantity_ordered, po.expected_delivery;
END $$;

-- T17 receiving the PO adds stock and cannot be repeated ------------------------------------
DO $$ DECLARE po INT; before INT; after INT; BEGIN
  SELECT po_id INTO po FROM purchase_order WHERE product_id=9 AND po_status='CREATED';
  before := get_total_stock(9);
  CALL receive_purchase_order(po);
  after := get_total_stock(9);
  IF after - before <> 33 THEN RAISE EXCEPTION 'FAIL T17 stock % -> %', before, after; END IF;
  IF (SELECT po_status FROM purchase_order WHERE po_id=po) <> 'RECEIVED' THEN RAISE EXCEPTION 'FAIL T17 status'; END IF;
  BEGIN CALL receive_purchase_order(po); RAISE EXCEPTION 'FAIL T17 twice'; EXCEPTION WHEN raise_exception THEN
     IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  RAISE WARNING 'PASS  T17 receive_purchase_order adds % units, second receive rejected', after - before;
END $$;

-- T18 CURSOR procedure finds low products without an open PO -----------------------------------
DO $$ DECLARE n INT; BEGIN
  UPDATE purchase_order SET po_status='CANCELLED' WHERE po_status='CREATED';  -- clear open POs (3 low products remain low)
  CALL check_reorder_levels(n);
  IF n < 3 THEN RAISE EXCEPTION 'FAIL T18 expected >=3 POs, got %', n; END IF;
  CALL check_reorder_levels(n);
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL T18 second run should create 0, got %', n; END IF;
  RAISE WARNING 'PASS  T18 cursor created POs, and a second run creates none';
END $$;

-- T19 warehouse capacity guard -----------------------------------------------------------------
SELECT pg_temp.expect_error($$CALL set_stock(1, 4, 5000)$$, 'T19 stock above warehouse capacity');
SELECT pg_temp.expect_error($$CALL create_purchase_order(1, 4, 0, NULL)$$, 'T20 PO with quantity 0');

-- T21+ constraints ------------------------------------------------------------------------------
SELECT pg_temp.expect_error($$UPDATE inventory SET quantity_available = -1 WHERE inventory_id = 1$$, 'T21 negative stock (CHECK)');
SELECT pg_temp.expect_error($$INSERT INTO customer(name,email) VALUES ('Dup','aarav.reddy@mail.com')$$, 'T22 duplicate e-mail (UNIQUE)');
SELECT pg_temp.expect_error($$INSERT INTO customer(name,email) VALUES ('Bad','not-an-email')$$, 'T23 malformed e-mail (CHECK)');
SELECT pg_temp.expect_error($$INSERT INTO orders(customer_id) VALUES (999)$$, 'T24 order without customer (FK)');
SELECT pg_temp.expect_error($$INSERT INTO product(product_name,unit_price,supplier_id) VALUES ('Free',0,1)$$, 'T25 price 0 (CHECK)');
SELECT pg_temp.expect_error($$INSERT INTO payment(order_id,payment_method,amount) VALUES (1,'UPI',10)$$, 'T26 second payment for an order (UNIQUE)');
SELECT pg_temp.expect_error($$INSERT INTO payment(order_id,payment_method,amount) VALUES (18,'BITCOIN',10)$$, 'T27 invalid payment method (CHECK)');
SELECT pg_temp.expect_error($$DELETE FROM customer WHERE customer_id = 1$$, 'T28 delete customer who has orders (FK)');
SELECT pg_temp.expect_error($$INSERT INTO inventory(product_id,warehouse_id,quantity_available) VALUES (1,1,5)$$, 'T29 duplicate product+warehouse (UNIQUE)');

-- T30 default values ------------------------------------------------------------------------------
DO $$ DECLARE id INT; BEGIN
  INSERT INTO customer(name,email) VALUES ('Default Test','default.test@mail.com') RETURNING customer_id INTO id;
  IF (SELECT status FROM customer WHERE customer_id=id) <> 'ACTIVE'
     OR (SELECT registered_date FROM customer WHERE customer_id=id) <> CURRENT_DATE THEN RAISE EXCEPTION 'FAIL T30'; END IF;
  RAISE WARNING 'PASS  T30 DEFAULT values (status ACTIVE, registered today)';
END $$;

-- T31 role-based security ----------------------------------------------------------------------------
DO $$ DECLARE v INT; BEGIN
  SET LOCAL ROLE customer_role;
  CALL place_order(1, '[{"product_id":20,"quantity":1}]', v);                  -- allowed through the procedure
  BEGIN PERFORM 1 FROM payment; RAISE EXCEPTION 'FAIL T31 customer read PAYMENT';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE inventory SET quantity_available = 9999; RAISE EXCEPTION 'FAIL T31 customer wrote INVENTORY';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  SET LOCAL ROLE warehouse_role;
  CALL set_stock(20, 1, 140);
  BEGIN PERFORM 1 FROM customer; RAISE EXCEPTION 'FAIL T31 warehouse read CUSTOMER';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  RAISE WARNING 'PASS  T31 role privileges (customer/warehouse) enforced';
END $$;

ROLLBACK;
\echo
\echo '=== ALL TESTS PASSED ==='
