-- =====================================================================
-- File 07: Demonstration queries (20) - covers joins, aggregation, subqueries,
-- set operations, window functions, CTEs and the report views.
-- Run with:  psql -d smart_ecommerce -f 07_queries.sql
-- =====================================================================

\echo '--- Q1  Simple selection: products costing more than Rs 2000, dearest first'
SELECT product_id, product_name, brand, unit_price
FROM   product WHERE unit_price > 2000 ORDER BY unit_price DESC;

\echo '--- Q2  Pattern match: customers living in cities that start with H or C'
SELECT customer_id, name, city FROM customer WHERE city LIKE 'H%' OR city LIKE 'C%' ORDER BY city, name;

\echo '--- Q3  INNER JOIN: every order with customer name and status'
SELECT o.order_id, c.name, o.order_date::DATE AS order_date, o.order_status, o.total_amount
FROM   orders o JOIN customer c ON c.customer_id = o.customer_id
ORDER  BY o.order_id;

\echo '--- Q4  Multi-table JOIN: line items of order 1 with product and warehouse'
SELECT oi.order_item_id, p.product_name, w.warehouse_name, oi.quantity, oi.unit_price,
       oi.quantity * oi.unit_price AS line_total
FROM   order_item oi
JOIN   product p   ON p.product_id   = oi.product_id
JOIN   warehouse w ON w.warehouse_id = oi.warehouse_id
WHERE  oi.order_id = 1;

\echo '--- Q5  GROUP BY + HAVING: customers who spent more than Rs 5000 on active orders'
SELECT c.name, COUNT(*) AS orders, SUM(o.total_amount) AS spent
FROM   customer c JOIN orders o ON o.customer_id = c.customer_id
WHERE  o.order_status <> 'CANCELLED'
GROUP  BY c.customer_id, c.name
HAVING SUM(o.total_amount) > 5000
ORDER  BY spent DESC;

\echo '--- Q6  Aggregate: revenue per category (non-cancelled orders)'
SELECT p.category, SUM(oi.quantity) AS units, SUM(oi.quantity * oi.unit_price) AS revenue
FROM   order_item oi JOIN product p ON p.product_id = oi.product_id
       JOIN orders o ON o.order_id = oi.order_id
WHERE  o.order_status <> 'CANCELLED'
GROUP  BY p.category ORDER BY revenue DESC;

\echo '--- Q7  Top 5 best-selling products (view)'
SELECT * FROM v_sales_by_product ORDER BY units_sold DESC, revenue DESC LIMIT 5;

\echo '--- Q8  Monthly revenue report (view)'
SELECT * FROM v_monthly_revenue ORDER BY month;

\echo '--- Q9  Low-stock report: products below reorder level (view)'
SELECT product_id, product_name, total_available, reorder_level, supplier_name, has_open_po
FROM   v_low_stock ORDER BY product_id;

\echo '--- Q10 Stock of every product per warehouse, with total via function get_total_stock()'
SELECT p.product_name, w.warehouse_name, i.quantity_available, i.quantity_reserved,
       get_total_stock(p.product_id) AS total_all_warehouses
FROM   inventory i JOIN product p ON p.product_id = i.product_id
       JOIN warehouse w ON w.warehouse_id = i.warehouse_id
ORDER  BY p.product_id, w.warehouse_id;

\echo '--- Q11 Subquery: products priced above the average product price'
SELECT product_name, unit_price FROM product
WHERE  unit_price > (SELECT AVG(unit_price) FROM product) ORDER BY unit_price DESC;

\echo '--- Q12 Correlated subquery: each customer''s most expensive order'
SELECT c.name, o.order_id, o.total_amount
FROM   orders o JOIN customer c ON c.customer_id = o.customer_id
WHERE  o.total_amount = (SELECT MAX(o2.total_amount) FROM orders o2 WHERE o2.customer_id = o.customer_id)
ORDER  BY o.total_amount DESC;

\echo '--- Q13 NOT EXISTS (anti-join): customers who never placed an order'
SELECT customer_id, name, status FROM customer c
WHERE  NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

\echo '--- Q14 LEFT JOIN: products that were never sold'
SELECT p.product_id, p.product_name
FROM   product p LEFT JOIN order_item oi ON oi.product_id = p.product_id
WHERE  oi.order_item_id IS NULL;

\echo '--- Q15 Window function: rank products by revenue inside each category'
SELECT category, product_name, revenue,
       RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
FROM   v_sales_by_product ORDER BY category, rank_in_category;

\echo '--- Q16 Window function: running total of daily revenue'
SELECT order_date::DATE AS day, total_amount,
       SUM(total_amount) OVER (ORDER BY order_date) AS running_revenue
FROM   orders WHERE order_status IN ('CONFIRMED','SHIPPED','DELIVERED') ORDER BY order_date;

\echo '--- Q17 CTE: order totals recomputed with get_order_total() and compared with the stored total'
WITH calc AS (SELECT order_id, get_order_total(order_id) AS calculated FROM orders)
SELECT o.order_id, o.total_amount, c.calculated, (o.total_amount = c.calculated) AS matches
FROM   orders o JOIN calc c USING (order_id) ORDER BY o.order_id;

\echo '--- Q18 Supplier delivery performance (view)'
SELECT * FROM v_supplier_performance ORDER BY on_time_pct DESC NULLS LAST;

\echo '--- Q19 UNION: everything that needs attention (open POs and unpaid orders)'
SELECT 'Open purchase order' AS item, po_id AS ref, po_date::TEXT AS since FROM purchase_order WHERE po_status = 'CREATED'
UNION ALL
SELECT 'Unpaid order', order_id, order_date::DATE::TEXT FROM v_order_summary WHERE payment_status IN ('NOT PAID','FAILED') AND order_status = 'PLACED'
ORDER  BY item, ref;

\echo '--- Q20 Order status distribution with percentage'
SELECT order_status, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM   orders GROUP BY order_status ORDER BY orders DESC;
