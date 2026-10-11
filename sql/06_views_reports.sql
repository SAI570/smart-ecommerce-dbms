-- =====================================================================
-- File 06: Views used by the reports (FR12)
-- "Sales" counts orders that are CONFIRMED, SHIPPED or DELIVERED.
-- =====================================================================

CREATE OR REPLACE VIEW v_order_summary AS
SELECT o.order_id, o.order_date, c.customer_id, c.name AS customer_name, c.city,
       o.order_status, o.total_amount,
       COALESCE(p.payment_method, '-') AS payment_method,
       COALESCE(p.payment_status, 'NOT PAID') AS payment_status
FROM   orders o
JOIN   customer c       ON c.customer_id = o.customer_id
LEFT JOIN payment p     ON p.order_id    = o.order_id;

CREATE OR REPLACE VIEW v_stock_overview AS
SELECT p.product_id, p.product_name, p.category, p.reorder_level,
       COALESCE(SUM(i.quantity_available), 0)::INT AS total_available,
       COALESCE(SUM(i.quantity_reserved),  0)::INT AS total_reserved,
       CASE WHEN COALESCE(SUM(i.quantity_available), 0) < p.reorder_level
            THEN 'LOW' ELSE 'OK' END                AS stock_status,
       s.supplier_id, s.supplier_name, s.lead_time_days,
       EXISTS (SELECT 1 FROM purchase_order po
                WHERE po.product_id = p.product_id AND po.po_status = 'CREATED') AS has_open_po
FROM   product p
JOIN   supplier s          ON s.supplier_id = p.supplier_id
LEFT JOIN inventory i      ON i.product_id  = p.product_id
GROUP  BY p.product_id, s.supplier_id;

CREATE OR REPLACE VIEW v_low_stock AS
SELECT * FROM v_stock_overview WHERE stock_status = 'LOW';

CREATE OR REPLACE VIEW v_sales_by_product AS
SELECT p.product_id, p.product_name, p.category,
       SUM(oi.quantity)::INT                AS units_sold,
       SUM(oi.quantity * oi.unit_price)     AS revenue
FROM   order_item oi
JOIN   orders  o ON o.order_id   = oi.order_id
JOIN   product p ON p.product_id = oi.product_id
WHERE  o.order_status IN ('CONFIRMED','SHIPPED','DELIVERED')
GROUP  BY p.product_id, p.product_name, p.category;

CREATE OR REPLACE VIEW v_sales_by_customer AS
SELECT c.customer_id, c.name, c.city,
       COUNT(o.order_id)::INT       AS orders_placed,
       COALESCE(SUM(o.total_amount), 0) AS total_spent
FROM   customer c
LEFT JOIN orders o ON o.customer_id = c.customer_id
      AND o.order_status IN ('CONFIRMED','SHIPPED','DELIVERED')
GROUP  BY c.customer_id, c.name, c.city;

CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT TO_CHAR(order_date, 'YYYY-MM') AS month,
       COUNT(*)::INT                  AS orders,
       SUM(total_amount)              AS revenue,
       ROUND(AVG(total_amount), 2)    AS avg_order_value
FROM   orders
WHERE  order_status IN ('CONFIRMED','SHIPPED','DELIVERED')
GROUP  BY TO_CHAR(order_date, 'YYYY-MM');

CREATE OR REPLACE VIEW v_supplier_performance AS
SELECT s.supplier_id, s.supplier_name, s.lead_time_days,
       COUNT(po.po_id)                                   FILTER (WHERE po.po_status = 'RECEIVED')::INT  AS pos_received,
       COUNT(po.po_id)                                   FILTER (WHERE po.po_status = 'CREATED')::INT   AS pos_open,
       COUNT(po.po_id)                                   FILTER (WHERE po.po_status = 'CANCELLED')::INT AS pos_cancelled,
       ROUND(AVG(po.actual_delivery - po.po_date)        FILTER (WHERE po.po_status = 'RECEIVED'), 1)   AS avg_actual_days,
       ROUND(AVG(po.actual_delivery - po.expected_delivery) FILTER (WHERE po.po_status = 'RECEIVED'), 1) AS avg_delay_days,
       ROUND(100.0 * COUNT(po.po_id) FILTER (WHERE po.po_status = 'RECEIVED' AND po.actual_delivery <= po.expected_delivery)
             / NULLIF(COUNT(po.po_id) FILTER (WHERE po.po_status = 'RECEIVED'), 0), 1)                  AS on_time_pct
FROM   supplier s
LEFT JOIN purchase_order po ON po.supplier_id = s.supplier_id
GROUP  BY s.supplier_id, s.supplier_name, s.lead_time_days;

-- Line items with names, used by the order detail screen
CREATE OR REPLACE VIEW v_order_detail AS
SELECT oi.order_id, o.customer_id, oi.order_item_id, oi.product_id, p.product_name,
       w.warehouse_name, oi.quantity, oi.unit_price, oi.quantity * oi.unit_price AS line_total
FROM   order_item oi
JOIN   orders o    ON o.order_id     = oi.order_id
JOIN   product p   ON p.product_id   = oi.product_id
JOIN   warehouse w ON w.warehouse_id = oi.warehouse_id;

-- Customer list without contact details (used on the sign-in screen)
CREATE OR REPLACE VIEW v_customer_public AS
SELECT customer_id, name, city FROM customer WHERE status = 'ACTIVE';
