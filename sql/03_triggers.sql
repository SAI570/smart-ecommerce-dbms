-- =====================================================================
-- File 03: Triggers
--   Trigger 1  trg_order_item_reduce_stock : ORDER_ITEM insert -> reduce INVENTORY
--   Trigger 2  trg_inventory_reorder       : INVENTORY update  -> create PURCHASE_ORDER
--   Extra      trg_order_item_total        : keep ORDERS.total_amount correct
--   Extra      trg_orders_status_flow      : only legal order-status transitions
--   Extra      trg_inventory_touch         : maintain last_updated
-- =====================================================================

-- Helper used by Trigger 2 and by the cursor procedure -----------------
-- Creates a purchase order for a product IF its total stock is below the
-- reorder level AND no open (CREATED) PO already exists. Returns po_id or NULL.
CREATE OR REPLACE FUNCTION raise_reorder_po(p_product_id INT, p_warehouse_id INT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_reorder   INT;
    v_supplier  INT;
    v_lead      INT;
    v_total     INT;
    v_qty       INT;
    v_po_id     INT;
BEGIN
    SELECT p.reorder_level, p.supplier_id, s.lead_time_days
      INTO v_reorder, v_supplier, v_lead
      FROM product p JOIN supplier s ON s.supplier_id = p.supplier_id
     WHERE p.product_id = p_product_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_total := get_total_stock(p_product_id);

    IF v_total >= v_reorder THEN
        RETURN NULL;                              -- stock is fine
    END IF;

    IF EXISTS (SELECT 1 FROM purchase_order
                WHERE product_id = p_product_id AND po_status = 'CREATED') THEN
        RETURN NULL;                              -- restock already on the way
    END IF;

    -- order enough to bring stock back to 3 x reorder level (at least one reorder level)
    v_qty := GREATEST(v_reorder * 3 - v_total, v_reorder, 1);

    INSERT INTO purchase_order
           (product_id, supplier_id, warehouse_id, quantity_ordered,
            po_date, expected_delivery, po_status)
    VALUES (p_product_id, v_supplier, p_warehouse_id, v_qty,
            CURRENT_DATE, CURRENT_DATE + v_lead, 'CREATED')
    RETURNING po_id INTO v_po_id;

    RAISE NOTICE 'Auto purchase order % created for product % (stock %, reorder level %, qty %)',
                 v_po_id, p_product_id, v_total, v_reorder, v_qty;
    RETURN v_po_id;
END;
$$;

-- ---------------------------------------------------------------------
-- TRIGGER 1: after an order line is inserted, move stock from
--            "available" to "reserved". Rejects the line if not enough stock.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_order_item_reduce_stock()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE inventory
       SET quantity_available = quantity_available - NEW.quantity,
           quantity_reserved  = quantity_reserved  + NEW.quantity
     WHERE product_id   = NEW.product_id
       AND warehouse_id = NEW.warehouse_id
       AND quantity_available >= NEW.quantity;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient stock: product % in warehouse % cannot supply % unit(s)',
                        NEW.product_id, NEW.warehouse_id, NEW.quantity
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_order_item_reduce_stock
AFTER INSERT ON order_item
FOR EACH ROW EXECUTE FUNCTION fn_order_item_reduce_stock();

-- ---------------------------------------------------------------------
-- Extra: keep ORDERS.total_amount in step with its lines
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_order_item_total()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE orders SET total_amount = get_order_total(NEW.order_id)
     WHERE order_id = NEW.order_id;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_order_item_total
AFTER INSERT ON order_item
FOR EACH ROW EXECUTE FUNCTION fn_order_item_total();

-- ---------------------------------------------------------------------
-- TRIGGER 2: after available stock goes DOWN, check the product's reorder
--            level and raise a purchase order to its supplier if needed.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_inventory_reorder()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM raise_reorder_po(NEW.product_id, NEW.warehouse_id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_inventory_reorder
AFTER UPDATE OF quantity_available ON inventory
FOR EACH ROW
WHEN (NEW.quantity_available < OLD.quantity_available)
EXECUTE FUNCTION fn_inventory_reorder();

-- ---------------------------------------------------------------------
-- Extra: only legal order status transitions
--   PLACED -> CONFIRMED | CANCELLED
--   CONFIRMED -> SHIPPED | CANCELLED
--   SHIPPED -> DELIVERED
--   DELIVERED and CANCELLED are final
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_orders_status_flow()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.order_status = OLD.order_status THEN
        RETURN NEW;
    END IF;

    IF (OLD.order_status, NEW.order_status) IN
       (('PLACED','CONFIRMED'), ('PLACED','CANCELLED'),
        ('CONFIRMED','SHIPPED'), ('CONFIRMED','CANCELLED'),
        ('SHIPPED','DELIVERED')) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Illegal order status change % -> % (order %)',
                    OLD.order_status, NEW.order_status, OLD.order_id
          USING ERRCODE = 'check_violation';
END;
$$;

CREATE TRIGGER trg_orders_status_flow
BEFORE UPDATE OF order_status ON orders
FOR EACH ROW EXECUTE FUNCTION fn_orders_status_flow();

-- ---------------------------------------------------------------------
-- Extra: stamp last_updated on every inventory change
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_inventory_touch()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.last_updated := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_inventory_touch
BEFORE INSERT OR UPDATE ON inventory
FOR EACH ROW EXECUTE FUNCTION fn_inventory_touch();
