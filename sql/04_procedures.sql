-- =====================================================================
-- File 04: Stored procedures (each one runs as ONE transaction: if any
-- step raises an error, everything the procedure did is rolled back)
-- =====================================================================

-- ---------------------------------------------------------------------
-- PROCEDURE 1: place_order
--   p_items = JSON array, e.g. [{"product_id":1,"quantity":2},{"product_id":5,"quantity":1}]
--   Picks warehouses automatically (largest stock first, splitting a line
--   across warehouses if one warehouse cannot cover it). Trigger 1 reserves
--   stock; the total is maintained by trg_order_item_total.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE place_order(
    p_customer_id  INT,
    p_items        JSONB,
    INOUT p_order_id INT DEFAULT NULL,
    p_order_date   TIMESTAMP DEFAULT NOW())
LANGUAGE plpgsql AS $$
DECLARE
    v_status     VARCHAR;
    v_item       RECORD;
    v_inv        RECORD;
    v_price      NUMERIC;
    v_remaining  INT;
    v_take       INT;
    v_available  INT;
BEGIN
    SELECT status INTO v_status FROM customer WHERE customer_id = p_customer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % does not exist', p_customer_id;
    END IF;
    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Customer % is not ACTIVE', p_customer_id;
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'An order needs at least one item';
    END IF;

    INSERT INTO orders (customer_id, order_date)
    VALUES (p_customer_id, p_order_date)
    RETURNING order_id INTO p_order_id;

    FOR v_item IN
        SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id INT, quantity INT)
    LOOP
        IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
            RAISE EXCEPTION 'Quantity for product % must be positive', v_item.product_id;
        END IF;

        SELECT unit_price INTO v_price FROM product WHERE product_id = v_item.product_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % does not exist', v_item.product_id;
        END IF;

        v_available := get_total_stock(v_item.product_id);
        IF v_available < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product %: requested %, available %',
                            v_item.product_id, v_item.quantity, v_available;
        END IF;

        v_remaining := v_item.quantity;
        FOR v_inv IN
            SELECT warehouse_id, quantity_available
              FROM inventory
             WHERE product_id = v_item.product_id AND quantity_available > 0
             ORDER BY quantity_available DESC, warehouse_id
               FOR UPDATE
        LOOP
            v_take := LEAST(v_remaining, v_inv.quantity_available);
            INSERT INTO order_item (order_id, product_id, warehouse_id, quantity, unit_price)
            VALUES (p_order_id, v_item.product_id, v_inv.warehouse_id, v_take, v_price);
            v_remaining := v_remaining - v_take;
            EXIT WHEN v_remaining = 0;
        END LOOP;

        -- Another order may have taken the stock while we waited for the row lock
        IF v_remaining > 0 THEN
            RAISE EXCEPTION 'Insufficient stock for product %: stock was taken by a concurrent order',
                            v_item.product_id USING ERRCODE = 'check_violation';
        END IF;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 2: cancel_order  - restore stock and mark order CANCELLED
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_order(p_order_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_item   RECORD;
BEGIN
    SELECT order_status INTO v_status FROM orders WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % does not exist', p_order_id;
    END IF;
    IF v_status NOT IN ('PLACED','CONFIRMED') THEN
        RAISE EXCEPTION 'Order % is % and can no longer be cancelled', p_order_id, v_status;
    END IF;

    FOR v_item IN SELECT product_id, warehouse_id, quantity FROM order_item WHERE order_id = p_order_id
    LOOP
        UPDATE inventory
           SET quantity_available = quantity_available + v_item.quantity,
               quantity_reserved  = quantity_reserved  - v_item.quantity
         WHERE product_id = v_item.product_id AND warehouse_id = v_item.warehouse_id;
    END LOOP;

    UPDATE orders SET order_status = 'CANCELLED' WHERE order_id = p_order_id;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 3: record_payment
--   Online methods: SUCCESS -> order CONFIRMED; FAILED -> order stays PLACED
--   (a FAILED payment may be retried because there is one payment row per order).
--   COD: payment stays PENDING and the order is CONFIRMED; it becomes
--   SUCCESS when the order is DELIVERED.
--   Gateway is simulated by p_simulate_success.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE record_payment(
    p_order_id          INT,
    p_method            VARCHAR,
    p_simulate_success  BOOLEAN DEFAULT TRUE,
    INOUT p_result      VARCHAR DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status   VARCHAR;
    v_total    NUMERIC;
    v_pay      RECORD;
    v_new      VARCHAR;
BEGIN
    SELECT order_status, total_amount INTO v_status, v_total
      FROM orders WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % does not exist', p_order_id;
    END IF;
    IF v_status <> 'PLACED' THEN
        RAISE EXCEPTION 'Order % is % - payment is only taken for PLACED orders', p_order_id, v_status;
    END IF;
    IF v_total <= 0 THEN
        RAISE EXCEPTION 'Order % has no payable amount', p_order_id;
    END IF;

    IF p_method = 'COD' THEN
        v_new := 'PENDING';
    ELSIF p_simulate_success THEN
        v_new := 'SUCCESS';
    ELSE
        v_new := 'FAILED';
    END IF;

    SELECT * INTO v_pay FROM payment WHERE order_id = p_order_id;
    IF FOUND THEN
        IF v_pay.payment_status <> 'FAILED' THEN
            RAISE EXCEPTION 'Order % already has a % payment', p_order_id, v_pay.payment_status;
        END IF;
        UPDATE payment
           SET payment_method = p_method, payment_status = v_new,
               amount = v_total, payment_date = NOW()
         WHERE order_id = p_order_id;
    ELSE
        INSERT INTO payment (order_id, payment_method, payment_status, amount)
        VALUES (p_order_id, p_method, v_new, v_total);
    END IF;

    IF v_new IN ('SUCCESS','PENDING') THEN
        UPDATE orders SET order_status = 'CONFIRMED' WHERE order_id = p_order_id;
    END IF;
    p_result := v_new;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 4: update_order_status  (SHIPPED / DELIVERED, entered manually)
--   SHIPPED   : stock physically leaves, so RESERVED is released
--   DELIVERED : a pending COD payment becomes SUCCESS
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE update_order_status(p_order_id INT, p_new_status VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
    v_item RECORD;
BEGIN
    IF p_new_status NOT IN ('SHIPPED','DELIVERED') THEN
        RAISE EXCEPTION 'Use record_payment for CONFIRMED and cancel_order for CANCELLED';
    END IF;

    PERFORM 1 FROM orders WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % does not exist', p_order_id;
    END IF;

    UPDATE orders SET order_status = p_new_status WHERE order_id = p_order_id; -- trigger validates

    IF p_new_status = 'SHIPPED' THEN
        FOR v_item IN SELECT product_id, warehouse_id, quantity FROM order_item WHERE order_id = p_order_id
        LOOP
            UPDATE inventory
               SET quantity_reserved = quantity_reserved - v_item.quantity
             WHERE product_id = v_item.product_id AND warehouse_id = v_item.warehouse_id;
        END LOOP;
    ELSE
        UPDATE payment SET payment_status = 'SUCCESS', payment_date = NOW()
         WHERE order_id = p_order_id AND payment_status = 'PENDING';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 5: receive_purchase_order - add delivered quantity to stock
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE receive_purchase_order(
    p_po_id INT, p_received_date DATE DEFAULT CURRENT_DATE)
LANGUAGE plpgsql AS $$
DECLARE
    v_po RECORD;
    v_cap INT;
BEGIN
    SELECT * INTO v_po FROM purchase_order WHERE po_id = p_po_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase order % does not exist', p_po_id;
    END IF;
    IF v_po.po_status <> 'CREATED' THEN
        RAISE EXCEPTION 'Purchase order % is already %', p_po_id, v_po.po_status;
    END IF;
    IF p_received_date < v_po.po_date THEN
        RAISE EXCEPTION 'Delivery date cannot be before the PO date';
    END IF;

    SELECT capacity INTO v_cap FROM warehouse WHERE warehouse_id = v_po.warehouse_id;
    IF get_warehouse_load(v_po.warehouse_id) + v_po.quantity_ordered > v_cap THEN
        RAISE EXCEPTION 'Warehouse % lacks capacity: load % + incoming % exceeds %',
              v_po.warehouse_id, get_warehouse_load(v_po.warehouse_id), v_po.quantity_ordered, v_cap;
    END IF;

    INSERT INTO inventory (product_id, warehouse_id, quantity_available)
    VALUES (v_po.product_id, v_po.warehouse_id, v_po.quantity_ordered)
    ON CONFLICT (product_id, warehouse_id)
    DO UPDATE SET quantity_available = inventory.quantity_available + EXCLUDED.quantity_available;

    UPDATE purchase_order
       SET po_status = 'RECEIVED', actual_delivery = p_received_date
     WHERE po_id = p_po_id;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 6: cancel_purchase_order
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_purchase_order(p_po_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE purchase_order SET po_status = 'CANCELLED'
     WHERE po_id = p_po_id AND po_status = 'CREATED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase order % not found or not open', p_po_id;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 7: create_purchase_order (manual, by the procurement manager)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE create_purchase_order(
    p_product_id INT, p_warehouse_id INT, p_quantity INT, INOUT p_po_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_supplier INT;
    v_lead     INT;
BEGIN
    SELECT p.supplier_id, s.lead_time_days INTO v_supplier, v_lead
      FROM product p JOIN supplier s USING (supplier_id)
     WHERE p.product_id = p_product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % does not exist', p_product_id;
    END IF;

    INSERT INTO purchase_order (product_id, supplier_id, warehouse_id, quantity_ordered,
                                po_date, expected_delivery)
    VALUES (p_product_id, v_supplier, p_warehouse_id, p_quantity,
            CURRENT_DATE, CURRENT_DATE + v_lead)
    RETURNING po_id INTO p_po_id;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 8: set_stock - warehouse manager corrects/sets available stock
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE set_stock(p_product_id INT, p_warehouse_id INT, p_quantity INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_cap  INT;
    v_cur  INT;
BEGIN
    IF p_quantity < 0 THEN
        RAISE EXCEPTION 'Quantity cannot be negative';
    END IF;
    SELECT capacity INTO v_cap FROM warehouse WHERE warehouse_id = p_warehouse_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Warehouse % does not exist', p_warehouse_id;
    END IF;
    SELECT COALESCE(quantity_available, 0) INTO v_cur
      FROM inventory WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id;
    v_cur := COALESCE(v_cur, 0);

    IF get_warehouse_load(p_warehouse_id) - v_cur + p_quantity > v_cap THEN
        RAISE EXCEPTION 'Warehouse % capacity (%) would be exceeded', p_warehouse_id, v_cap;
    END IF;

    INSERT INTO inventory (product_id, warehouse_id, quantity_available)
    VALUES (p_product_id, p_warehouse_id, p_quantity)
    ON CONFLICT (product_id, warehouse_id)
    DO UPDATE SET quantity_available = EXCLUDED.quantity_available;
END;
$$;

-- ---------------------------------------------------------------------
-- PROCEDURE 9 (CURSOR): check_reorder_levels
--   Walks over every product whose total stock is below its reorder level
--   and which has no open PO, and raises a purchase order to its supplier.
--   Targets the warehouse that holds the least of that product.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE check_reorder_levels(INOUT p_created INT DEFAULT 0)
LANGUAGE plpgsql AS $$
DECLARE
    c_low CURSOR FOR
        SELECT p.product_id, p.product_name, p.reorder_level,
               get_total_stock(p.product_id) AS total_stock
          FROM product p
         WHERE get_total_stock(p.product_id) < p.reorder_level
           AND NOT EXISTS (SELECT 1 FROM purchase_order po
                            WHERE po.product_id = p.product_id AND po.po_status = 'CREATED')
         ORDER BY p.product_id;
    r        RECORD;
    v_wh     INT;
    v_po     INT;
BEGIN
    p_created := 0;
    OPEN c_low;
    LOOP
        FETCH c_low INTO r;
        EXIT WHEN NOT FOUND;

        SELECT warehouse_id INTO v_wh
          FROM inventory WHERE product_id = r.product_id
         ORDER BY quantity_available, warehouse_id LIMIT 1;
        IF v_wh IS NULL THEN
            SELECT warehouse_id INTO v_wh FROM warehouse ORDER BY warehouse_id LIMIT 1;
        END IF;

        v_po := raise_reorder_po(r.product_id, v_wh);
        IF v_po IS NOT NULL THEN
            p_created := p_created + 1;
        END IF;
    END LOOP;
    CLOSE c_low;
END;
$$;
