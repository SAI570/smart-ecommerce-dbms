-- =====================================================================
-- File 08: Database roles for the four user types (DCL: GRANT / REVOKE)
-- Business procedures run with the owner's rights (SECURITY DEFINER), so a
-- customer can place an order WITHOUT being allowed to touch INVENTORY directly.
-- =====================================================================
DO $$
DECLARE r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['customer_role','admin_role','warehouse_role','procurement_role'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

ALTER PROCEDURE place_order(INT, JSONB, INT, TIMESTAMP)         SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE cancel_order(INT)                               SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE record_payment(INT, VARCHAR, BOOLEAN, VARCHAR)  SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE update_order_status(INT, VARCHAR)               SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE receive_purchase_order(INT, DATE)               SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE cancel_purchase_order(INT)                      SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE create_purchase_order(INT, INT, INT, INT)       SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE set_stock(INT, INT, INT)                        SECURITY DEFINER SET search_path = public;
ALTER PROCEDURE check_reorder_levels(INT)                       SECURITY DEFINER SET search_path = public;

REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM customer_role, admin_role, warehouse_role, procurement_role;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO customer_role, admin_role, warehouse_role, procurement_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO customer_role, admin_role, warehouse_role, procurement_role;

-- Let the installing user switch into these roles (the web app does SET ROLE per user type)
GRANT customer_role, admin_role, warehouse_role, procurement_role TO CURRENT_USER;

-- Customer: browse products, place / pay / cancel orders, read own order list
GRANT SELECT ON product, v_stock_overview, v_order_summary, v_order_detail, v_customer_public TO customer_role;
GRANT INSERT, UPDATE ON customer TO customer_role;            -- register / edit profile
GRANT USAGE ON SEQUENCE customer_customer_id_seq TO customer_role;
GRANT EXECUTE ON PROCEDURE place_order(INT, JSONB, INT, TIMESTAMP),
                           cancel_order(INT),
                           record_payment(INT, VARCHAR, BOOLEAN, VARCHAR) TO customer_role;

-- Administrator: full control of master data, orders, payments and reports
GRANT SELECT, INSERT, UPDATE, DELETE ON customer, supplier, product, warehouse TO admin_role;
GRANT SELECT ON inventory, orders, order_item, payment, purchase_order TO admin_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO admin_role;    -- includes all report views
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO admin_role;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO admin_role;

-- Warehouse manager: maintain stock, read low-stock alerts, receive deliveries
GRANT SELECT ON warehouse, product, supplier, inventory, purchase_order, v_stock_overview, v_low_stock,
                v_order_summary, v_order_detail TO warehouse_role;
GRANT EXECUTE ON PROCEDURE set_stock(INT, INT, INT),
                           receive_purchase_order(INT, DATE),
                           update_order_status(INT, VARCHAR) TO warehouse_role;

-- Procurement manager: reorder alerts and purchase orders
GRANT SELECT ON supplier, product, warehouse, purchase_order,
                v_stock_overview, v_low_stock, v_supplier_performance TO procurement_role;
GRANT EXECUTE ON PROCEDURE check_reorder_levels(INT),
                           create_purchase_order(INT, INT, INT, INT),
                           cancel_purchase_order(INT) TO procurement_role;
