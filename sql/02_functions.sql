-- =====================================================================
-- File 02: Functions
-- =====================================================================

-- Function 1: total value of an order = SUM(quantity * unit_price)
CREATE OR REPLACE FUNCTION get_order_total(p_order_id INT)
RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(quantity * unit_price), 0)
    FROM   order_item
    WHERE  order_id = p_order_id;
$$;

-- Function 2: total sellable stock of a product across all warehouses
CREATE OR REPLACE FUNCTION get_total_stock(p_product_id INT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(quantity_available), 0)::INT
    FROM   inventory
    WHERE  product_id = p_product_id;
$$;

-- Helper: stock used by one warehouse (available + reserved), for capacity checks
CREATE OR REPLACE FUNCTION get_warehouse_load(p_warehouse_id INT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(quantity_available + quantity_reserved), 0)::INT
    FROM   inventory
    WHERE  warehouse_id = p_warehouse_id;
$$;
