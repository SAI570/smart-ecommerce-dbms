# VELLORE INSTITUTE OF TECHNOLOGY
## School of Computer Science Engineering and Information Systems
### BCSE302P – Database Systems Lab
---
# LAB COURSE PROJECT REPORT

## 1. Project Title and Team/Student Details

* **Project Title:** Smart E-Commerce Order, Inventory & Supply Chain Management System
* **Course Code:** BCSE302P – Database Systems Lab
* **Student Name:** S. Sai Siva Prasad Reddy
* **Registration Number:** 24BYB0127
* **Degree / Programme:** B.Tech Computer Science and Engineering
* **Faculty / Guide:** Dr. Konjeti Srinivasulu
* **DBMS Environment:** PostgreSQL 18.x (Port: 5432, Database: `smart_ecommerce`, Superuser: `postgres`)
* **Repository Link:** [https://github.com/SAI570/smart-ecommerce-dbms](https://github.com/SAI570/smart-ecommerce-dbms)

---

## 2. Introduction and Problem Statement

### 2.1 Domain Overview
Modern enterprise e-commerce platforms must coordinate customer orders, multi-warehouse inventory, payment gateways, and supplier supply chains. In traditional systems, business logic is scattered across front-end JavaScript or back-end application servers ("fat application, dumb database"). This architectural pattern introduces critical vulnerabilities:
1. **Overselling & Race Conditions:** Concurrent checkout requests read outdated stock numbers and commit duplicate orders for the same physical unit.
2. **Disconnected Supply Chain:** Inventory depletion is noticed manually, causing prolonged stock-outs and delivery delays.
3. **Data Inconsistency:** Network failures during multi-step order placement leave orphan records (e.g., payment processed without stock allocated).
4. **Weak Security:** Authorization relies solely on application menus; any direct database connection (via SQL console or API breach) bypasses business logic.

### 2.2 Problem Statement
Design, implement, and evaluate an **Active Database Management System** for an end-to-end Smart E-Commerce ecosystem where **PostgreSQL 18** acts as the single source of truth and business logic enforcement. The system guarantees:
* Real-time multi-warehouse stock reservation to prevent overselling.
* Automatic supply chain restocking via event-driven database triggers.
* Strict ACID transactional guarantees during multi-item orders and cancellations.
* Database-native Data Control Language (DCL) role-based authorization (`admin_role`, `customer_role`, `warehouse_role`, `procurement_role`).

![pgAdmin 4 Relational Schema & Tables Catalog](C:/Users/sangi/.gemini/antigravity/brain/b2e5f594-8abc-4b94-95b8-05bd599f0e64/screenshot_5_tree.png)
*Figure 2.1: pgAdmin 4 Catalog inspection showing the 9 core relational tables and schema sizes.*

---

## 3. Functional Requirements

* **FR1 (Customer Management):** Register, validate, and manage customer accounts with strict constraints on unique emails, 10-digit mobile numbers, and encrypted password storage.
* **FR2 (Product & Supplier Master):** Categorize products, track base unit prices, define safety reorder levels, and link each product to primary suppliers with delivery lead-time metrics.
* **FR3 (Multi-Warehouse Inventory):** Distribute product stock across regional distribution centers (Hyderabad, Chennai, Mumbai, Delhi) with independent capacity limits.
* **FR4 (Dual-State Stock Model):** Separate inventory into `AVAILABLE` (sellable) and `RESERVED` (committed to unfulfilled orders) to protect against concurrency hazards.
* **FR5 (Transactional Multi-Item Ordering):** Place multi-item orders as an atomic transaction. If a requested product quantity exceeds total nationwide stock, the entire order rolls back cleanly. If single warehouse stock is insufficient, the procedure dynamically splits the order line across multiple warehouses.
* **FR6 (Trigger-Based Stock Reservation):** Immediately transfer order quantities from `quantity_available` to `quantity_reserved` upon order line insertion (Trigger 1).
* **FR7 (Payment State Transition):** Support payment methods (UPI, Credit Card, Debit Card, NetBanking, COD) and execute legal order status updates (`PLACED` $\rightarrow$ `CONFIRMED`).
* **FR8 (Order Cancellation & Restocking):** Atomically release reserved stock back into available stock if an order is cancelled prior to dispatch.
* **FR9 (Autonomous Supply Reordering):** Trigger purchase orders automatically to suppliers when nationwide stock dips below reorder thresholds (Trigger 2 & Cursor).
* **FR10 (Warehouse Receipt & Capacity Enforcement):** Process supplier deliveries, verify that receiving warehouse capacity is not exceeded, and convert purchase orders to `RECEIVED`.
* **FR11 (Analytical Views & Business Intelligence):** Provide real-time reporting views for supplier on-time delivery rates, low stock alerts, monthly revenue, and top-selling products.
* **FR12 (Database-Level Access Control):** Enforce least privilege using PostgreSQL roles and `SECURITY DEFINER` procedures.

---

## 4. Entity-Relationship (ER) Diagram

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDERS : places
    ORDERS ||--|{ ORDER_ITEM : contains
    PRODUCT ||--o{ ORDER_ITEM : "refers to"
    WAREHOUSE ||--o{ ORDER_ITEM : "fulfilled from"
    ORDERS ||--o| PAYMENT : "paid by"
    SUPPLIER ||--o{ PRODUCT : "supplied by"
    PRODUCT ||--o{ INVENTORY : "stocked in"
    WAREHOUSE ||--o{ INVENTORY : "stored at"
    PRODUCT ||--o{ PURCHASE_ORDER : "restocked by"
    SUPPLIER ||--o{ PURCHASE_ORDER : fulfils
    WAREHOUSE ||--o{ PURCHASE_ORDER : "delivered to"

    CUSTOMER {
        int customer_id PK
        string name
        string email UK
        string phone
        string address
        string city
        date registered_date
        string status
        string password_hash
    }
    SUPPLIER {
        int supplier_id PK
        string supplier_name
        string email
        string phone
        int lead_time_days
        string status
    }
    PRODUCT {
        int product_id PK
        string product_name
        string category
        string brand
        decimal unit_price
        int reorder_level
        int supplier_id FK
    }
    WAREHOUSE {
        int warehouse_id PK
        string warehouse_name UK
        string city
        int capacity
    }
    INVENTORY {
        int inventory_id PK
        int product_id FK
        int warehouse_id FK
        int quantity_available
        int quantity_reserved
        timestamp last_updated
    }
    ORDERS {
        int order_id PK
        int customer_id FK
        timestamp order_date
        string order_status
        decimal total_amount
    }
    ORDER_ITEM {
        int order_item_id PK
        int order_id FK
        int product_id FK
        int warehouse_id FK
        int quantity
        decimal unit_price
    }
    PAYMENT {
        int payment_id PK
        int order_id FK,UK
        string payment_method
        string payment_status
        decimal amount
        timestamp payment_date
    }
    PURCHASE_ORDER {
        int po_id PK
        int product_id FK
        int supplier_id FK
        int warehouse_id FK
        int quantity_ordered
        date po_date
        date expected_delivery
        date actual_delivery
        string po_status
    }
```

---

## 5. Relational Schema (3NF)

1. **`CUSTOMER`** (
   $\underline{\text{customer\_id}}$, name, email, phone, address, city, registered\_date, status, password\_hash
   )
   * *PK:* `customer_id` | *UK:* `email`

2. **`SUPPLIER`** (
   $\underline{\text{supplier\_id}}$, supplier\_name, email, phone, lead\_time\_days, status
   )
   * *PK:* `supplier_id`

3. **`PRODUCT`** (
   $\underline{\text{product\_id}}$, product\_name, category, brand, unit\_price, reorder\_level, $\text{supplier\_id}^*$
   )
   * *PK:* `product_id` | *FK:* `supplier_id` $\rightarrow$ `SUPPLIER(supplier_id)`

4. **`WAREHOUSE`** (
   $\underline{\text{warehouse\_id}}$, warehouse\_name, city, capacity
   )
   * *PK:* `warehouse_id` | *UK:* `warehouse_name`

5. **`INVENTORY`** (
   $\underline{\text{inventory\_id}}$, $\text{product\_id}^*$, $\text{warehouse\_id}^*$, quantity\_available, quantity\_reserved, last\_updated
   )
   * *PK:* `inventory_id` | *UK:* (`product_id`, `warehouse_id`)
   * *FK:* `product_id` $\rightarrow$ `PRODUCT(product_id)`, `warehouse_id` $\rightarrow$ `WAREHOUSE(warehouse_id)`

6. **`ORDERS`** (
   $\underline{\text{order\_id}}$, $\text{customer\_id}^*$, order\_date, order\_status, total\_amount
   )
   * *PK:* `order_id` | *FK:* `customer_id` $\rightarrow$ `CUSTOMER(customer_id)`

7. **`ORDER_ITEM`** (
   $\underline{\text{order\_item\_id}}$, $\text{order\_id}^*$, $\text{product\_id}^*$, $\text{warehouse\_id}^*$, quantity, unit\_price
   )
   * *PK:* `order_item_id`
   * *FK:* `order_id` $\rightarrow$ `ORDERS(order_id)`, `product_id` $\rightarrow$ `PRODUCT(product_id)`, `warehouse_id` $\rightarrow$ `WAREHOUSE(warehouse_id)`

8. **`PAYMENT`** (
   $\underline{\text{payment\_id}}$, $\text{order\_id}^*$, payment\_method, payment\_status, amount, payment\_date
   )
   * *PK:* `payment_id` | *UK:* `order_id` | *FK:* `order_id` $\rightarrow$ `ORDERS(order_id)`

9. **`PURCHASE_ORDER`** (
   $\underline{\text{po\_id}}$, $\text{product\_id}^*$, $\text{supplier\_id}^*$, $\text{warehouse\_id}^*$, quantity\_ordered, po\_date, expected\_delivery, actual\_delivery, po\_status
   )
   * *PK:* `po_id`
   * *FK:* `product_id` $\rightarrow$ `PRODUCT(product_id)`, `supplier_id` $\rightarrow$ `SUPPLIER(supplier_id)`, `warehouse_id` $\rightarrow$ `WAREHOUSE(warehouse_id)`

---

## 6. Table Creation and Constraints (DDL)

```sql
-- 1. CUSTOMER TABLE
CREATE TABLE customer (
    customer_id      SERIAL        PRIMARY KEY,
    name             VARCHAR(100)  NOT NULL,
    email            VARCHAR(120)  NOT NULL UNIQUE,
    phone            VARCHAR(15),
    address          VARCHAR(200),
    city             VARCHAR(60),
    password_hash    VARCHAR(255),
    registered_date  DATE          NOT NULL DEFAULT CURRENT_DATE,
    status           VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','INACTIVE')),
    CONSTRAINT chk_customer_email CHECK (email LIKE '%_@_%._%')
);

-- 2. SUPPLIER TABLE
CREATE TABLE supplier (
    supplier_id      SERIAL        PRIMARY KEY,
    supplier_name    VARCHAR(100)  NOT NULL,
    email            VARCHAR(120),
    phone            VARCHAR(15),
    lead_time_days   INT           NOT NULL CHECK (lead_time_days > 0),
    status           VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- 3. PRODUCT TABLE
CREATE TABLE product (
    product_id     SERIAL         PRIMARY KEY,
    product_name   VARCHAR(120)   NOT NULL,
    category       VARCHAR(60),
    brand          VARCHAR(60),
    unit_price     NUMERIC(10,2)  NOT NULL CHECK (unit_price > 0),
    reorder_level  INT            NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
    supplier_id    INT            NOT NULL REFERENCES supplier(supplier_id)
);

-- 4. WAREHOUSE TABLE
CREATE TABLE warehouse (
    warehouse_id    SERIAL       PRIMARY KEY,
    warehouse_name  VARCHAR(80)  NOT NULL UNIQUE,
    city            VARCHAR(60)  NOT NULL,
    capacity        INT          NOT NULL CHECK (capacity > 0)
);

-- 5. INVENTORY TABLE (Multi-Warehouse stock with dual states)
CREATE TABLE inventory (
    inventory_id        SERIAL     PRIMARY KEY,
    product_id          INT        NOT NULL REFERENCES product(product_id),
    warehouse_id        INT        NOT NULL REFERENCES warehouse(warehouse_id),
    quantity_available  INT        NOT NULL DEFAULT 0 CHECK (quantity_available >= 0),
    quantity_reserved   INT        NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    last_updated        TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_product_warehouse UNIQUE (product_id, warehouse_id)
);

-- 6. ORDERS TABLE
CREATE TABLE orders (
    order_id      SERIAL         PRIMARY KEY,
    customer_id   INT            NOT NULL REFERENCES customer(customer_id),
    order_date    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    order_status  VARCHAR(15)    NOT NULL DEFAULT 'PLACED'
                  CHECK (order_status IN ('PLACED','CONFIRMED','SHIPPED','DELIVERED','CANCELLED')),
    total_amount  NUMERIC(12,2)  NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0)
);

-- 7. ORDER_ITEM TABLE
CREATE TABLE order_item (
    order_item_id  SERIAL         PRIMARY KEY,
    order_id       INT            NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id     INT            NOT NULL REFERENCES product(product_id),
    warehouse_id   INT            NOT NULL REFERENCES warehouse(warehouse_id),
    quantity       INT            NOT NULL CHECK (quantity > 0),
    unit_price     NUMERIC(10,2)  NOT NULL CHECK (unit_price > 0)
);

-- 8. PAYMENT TABLE
CREATE TABLE payment (
    payment_id      SERIAL         PRIMARY KEY,
    order_id        INT            NOT NULL UNIQUE REFERENCES orders(order_id),
    payment_method  VARCHAR(20)    NOT NULL
                    CHECK (payment_method IN ('CREDIT_CARD','DEBIT_CARD','UPI','NETBANKING','COD')),
    payment_status  VARCHAR(15)    NOT NULL DEFAULT 'PENDING'
                    CHECK (payment_status IN ('PENDING','SUCCESS','FAILED')),
    amount          NUMERIC(12,2)  NOT NULL CHECK (amount > 0),
    payment_date    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 9. PURCHASE_ORDER TABLE
CREATE TABLE purchase_order (
    po_id              SERIAL       PRIMARY KEY,
    product_id         INT          NOT NULL REFERENCES product(product_id),
    supplier_id        INT          NOT NULL REFERENCES supplier(supplier_id),
    warehouse_id       INT          NOT NULL REFERENCES warehouse(warehouse_id),
    quantity_ordered   INT          NOT NULL CHECK (quantity_ordered > 0),
    po_date            DATE         NOT NULL DEFAULT CURRENT_DATE,
    expected_delivery  DATE         NOT NULL,
    actual_delivery    DATE,
    po_status          VARCHAR(15)  NOT NULL DEFAULT 'CREATED'
                       CHECK (po_status IN ('CREATED','RECEIVED','CANCELLED')),
    CONSTRAINT chk_po_delivery CHECK (expected_delivery >= po_date)
);
```

---

## 7. SQL Queries and Execution Outputs

![pgAdmin 4 SQL Query Execution and Output Grid](C:/Users/sangi/.gemini/antigravity/brain/b2e5f594-8abc-4b94-95b8-05bd599f0e64/screenshot_1_queries.png)
*Figure 7.1: pgAdmin 4 Query Tool executing multi-table join and low-stock business intelligence queries.*

### Query 1: High-Value Products Filter (Selection & Ordering)
```sql
SELECT product_id, product_name, brand, unit_price 
FROM product 
WHERE unit_price > 2000 
ORDER BY unit_price DESC;
```
*Live Output:*
| product_id | product_name | brand | unit_price |
| :--- | :--- | :--- | :--- |
| 9 | Running Shoes | Puma | ₹3,999.00 |
| 13 | Mixer Grinder | Bajaj | ₹3,499.00 |
| 3 | USB-C Hub 7-in-1 | Anker | ₹3,299.00 |
| 2 | Mechanical Keyboard | Redragon | ₹2,499.00 |
| 16 | Dumbbell Set 10kg | Cultsport | ₹2,299.00 |

### Query 2: Multi-Table Inner Join (Orders & Customers)
```sql
SELECT o.order_id, c.name, o.order_date::DATE AS order_date, o.order_status, o.total_amount
FROM orders o 
JOIN customer c ON c.customer_id = o.customer_id
ORDER BY o.order_id LIMIT 5;
```
*Live Output:*
| order_id | name | order_date | order_status | total_amount |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Aarav Reddy | 2026-07-03 | DELIVERED | ₹1,997.00 |
| 2 | Priya Nair | 2026-07-09 | DELIVERED | ₹4,296.00 |
| 3 | Rohan Mehta | 2026-07-15 | DELIVERED | ₹3,798.00 |
| 4 | Sneha Kapoor | 2026-07-22 | DELIVERED | ₹3,495.00 |
| 5 | Vikram Singh | 2026-08-02 | DELIVERED | ₹3,097.00 |

### Query 3: Multi-Warehouse Line Items Breakdown (3-Table Join)
```sql
SELECT oi.order_item_id, p.product_name, w.warehouse_name, oi.quantity, oi.unit_price,
       (oi.quantity * oi.unit_price) AS line_total
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
JOIN warehouse w ON w.warehouse_id = oi.warehouse_id
WHERE oi.order_id = 1;
```
*Live Output:*
| order_item_id | product_name | warehouse_name | quantity | unit_price | line_total |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | Wireless Mouse | Hyderabad Central | 1 | ₹699.00 | ₹699.00 |
| 2 | Cotton T-Shirt | Chennai Hub | 2 | ₹499.00 | ₹998.00 |
| 3 | Stainless Steel Bottle | Hyderabad Central | 1 | ₹300.00 | ₹300.00 |

### Query 4: Group By & Having (High-Spending Customers)
```sql
SELECT c.name, COUNT(*) AS orders, SUM(o.total_amount) AS spent
FROM customer c 
JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_status <> 'CANCELLED'
GROUP BY c.customer_id, c.name
HAVING SUM(o.total_amount) > 5000
ORDER BY spent DESC;
```
*Live Output:*
| name | orders | spent |
| :--- | :--- | :--- |
| Aarav Reddy | 15 | ₹56,582.00 |
| Nikhil Sharma | 2 | ₹18,793.00 |
| Vikram Singh | 2 | ₹16,192.00 |
| Ananya Iyer | 4 | ₹11,393.00 |
| Priya Nair | 2 | ₹11,294.00 |

### Query 5: Category Revenue Aggregation
```sql
SELECT p.category, SUM(oi.quantity) AS units, SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_item oi 
JOIN product p ON p.product_id = oi.product_id
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_status <> 'CANCELLED'
GROUP BY p.category 
ORDER BY revenue DESC;
```
*Live Output:*
| category | units | revenue |
| :--- | :--- | :--- |
| Footwear | 18 | ₹59,982.00 |
| Electronics | 37 | ₹47,763.00 |
| Appliances | 12 | ₹37,988.00 |
| Fitness | 14 | ₹23,586.00 |
| Apparel | 30 | ₹17,970.00 |

### Query 6: Subquery (Products Above Average Price)
```sql
SELECT product_name, unit_price 
FROM product
WHERE unit_price > (SELECT AVG(unit_price) FROM product) 
ORDER BY unit_price DESC;
```
*Live Output:*
| product_name | unit_price |
| :--- | :--- |
| Running Shoes | ₹3,999.00 |
| Mixer Grinder | ₹3,499.00 |
| USB-C Hub 7-in-1 | ₹3,299.00 |
| Mechanical Keyboard | ₹2,499.00 |
| Dumbbell Set 10kg | ₹2,299.00 |

### Query 7: Correlated Subquery (Each Customer's Maximum Order)
```sql
SELECT c.name, o.order_id, o.total_amount
FROM orders o 
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.total_amount = (
    SELECT MAX(o2.total_amount) 
    FROM orders o2 
    WHERE o2.customer_id = o.customer_id
)
ORDER BY o.total_amount DESC LIMIT 5;
```
*Live Output:*
| name | order_id | total_amount |
| :--- | :--- | :--- |
| Vikram Singh | 19 | ₹12,194.00 |
| Nikhil Sharma | 18 | ₹10,996.00 |
| Aarav Reddy | 22 | ₹9,597.00 |
| Priya Nair | 15 | ₹6,998.00 |
| Ananya Iyer | 20 | ₹5,597.00 |

### Query 8: Anti-Join (Customers with Zero Orders via NOT EXISTS)
```sql
SELECT customer_id, name, city, status 
FROM customer c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
);
```
*Live Output:*
| customer_id | name | city | status |
| :--- | :--- | :--- | :--- |
| 13 | Tarun Joshi | Ahmedabad | ACTIVE |

### Query 9: Window Function (Rank Products by Revenue within Category)
```sql
SELECT category, product_name, revenue,
       RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_cat
FROM v_sales_by_product 
ORDER BY category, rank_in_cat;
```
*Live Output:*
| category | product_name | revenue | rank_in_cat |
| :--- | :--- | :--- | :--- |
| Apparel | Cotton T-Shirt | ₹9,980.00 | 1 |
| Apparel | Denim Jeans | ₹7,990.00 | 2 |
| Appliances | Mixer Grinder | ₹24,493.00 | 1 |
| Appliances | Electric Kettle | ₹13,495.00 | 2 |
| Electronics | USB-C Hub 7-in-1 | ₹26,392.00 | 1 |
| Electronics | Mechanical Keyboard | ₹12,495.00 | 2 |

### Query 10: Window Function (Cumulative Daily Revenue Running Total)
```sql
SELECT order_date::DATE AS day, total_amount,
       SUM(total_amount) OVER (ORDER BY order_date) AS running_revenue
FROM orders 
WHERE order_status IN ('CONFIRMED','SHIPPED','DELIVERED') 
ORDER BY order_date LIMIT 5;
```
*Live Output:*
| day | total_amount | running_revenue |
| :--- | :--- | :--- |
| 2026-07-03 | ₹1,997.00 | ₹1,997.00 |
| 2026-07-09 | ₹4,296.00 | ₹6,293.00 |
| 2026-07-15 | ₹3,798.00 | ₹10,091.00 |
| 2026-07-22 | ₹3,495.00 | ₹13,586.00 |
| 2026-08-02 | ₹3,097.00 | ₹16,683.00 |

### Query 11: Common Table Expression (CTE) Integrity Verification
```sql
WITH calc AS (
    SELECT order_id, get_order_total(order_id) AS calculated 
    FROM orders
)
SELECT o.order_id, o.total_amount, c.calculated, (o.total_amount = c.calculated) AS matches
FROM orders o 
JOIN calc c USING (order_id) 
ORDER BY o.order_id LIMIT 5;
```
*Live Output:*
| order_id | total_amount | calculated | matches |
| :--- | :--- | :--- | :--- |
| 1 | 1997.00 | 1997.00 | true |
| 2 | 4296.00 | 4296.00 | true |
| 3 | 3798.00 | 3798.00 | true |
| 4 | 3495.00 | 3495.00 | true |
| 5 | 3097.00 | 3097.00 | true |

### Query 12: Actionable Operations via UNION ALL
```sql
SELECT 'Open purchase order' AS item, po_id AS ref_id, po_date::TEXT AS logged_date 
FROM purchase_order WHERE po_status = 'CREATED'
UNION ALL
SELECT 'Unpaid placed order', order_id, order_date::DATE::TEXT 
FROM v_order_summary WHERE payment_status IN ('NOT PAID','FAILED') AND order_status = 'PLACED'
ORDER BY item, ref_id;
```
*Live Output:*
| item | ref_id | logged_date |
| :--- | :--- | :--- |
| Open purchase order | 1 | 2026-10-09 |
| Open purchase order | 2 | 2026-10-10 |
| Unpaid placed order | 23 | 2026-10-23 |

### Query 13: Order Status Distribution Percentage
```sql
SELECT order_status, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM orders 
GROUP BY order_status 
ORDER BY orders DESC;
```
*Live Output:*
| order_status | orders | percentage |
| :--- | :--- | :--- |
| DELIVERED | 30 | 65.2% |
| CONFIRMED | 6 | 13.0% |
| CANCELLED | 5 | 10.9% |
| PLACED | 5 | 10.9% |

---

## 8. Procedures, Functions, Cursor and Triggers

### 8.1 Database Functions (UDFs)

![pgAdmin 4 Custom Database Functions Execution](C:/Users/sangi/.gemini/antigravity/brain/b2e5f594-8abc-4b94-95b8-05bd599f0e64/screenshot_2_functions.png)
*Figure 8.1: pgAdmin 4 executing custom PL/pgSQL functions (`get_order_total`, `get_total_stock`, `get_warehouse_load`).*

#### 1. `get_order_total(p_order_id INT)`
Computes the exact total price of an order by summing `(quantity * unit_price)` across all related rows in `order_item`.
```sql
CREATE OR REPLACE FUNCTION get_order_total(p_order_id INT)
RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(quantity * unit_price), 0)
    FROM   order_item
    WHERE  order_id = p_order_id;
$$;
```

#### 2. `get_total_stock(p_product_id INT)`
Calculates the total nationwide sellable stock across all warehouses.
```sql
CREATE OR REPLACE FUNCTION get_total_stock(p_product_id INT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(quantity_available), 0)::INT
    FROM   inventory
    WHERE  product_id = p_product_id;
$$;
```

#### 3. `get_warehouse_load(p_warehouse_id INT)`
Calculates the physical occupancy (available + reserved) of a specific warehouse to prevent inventory overflow.
```sql
CREATE OR REPLACE FUNCTION get_warehouse_load(p_warehouse_id INT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(quantity_available + quantity_reserved), 0)::INT
    FROM   inventory
    WHERE  warehouse_id = p_warehouse_id;
$$;
```

#### 4. `raise_reorder_po(p_product_id INT, p_warehouse_id INT)`
Autonomous supply chain helper that validates thresholds, lead times, and open PO status, generating a new `purchase_order` row when needed.
```sql
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
        RETURN NULL; -- Stock is healthy
    END IF;

    -- Avoid duplicate open purchase orders
    IF EXISTS (SELECT 1 FROM purchase_order
                WHERE product_id = p_product_id AND po_status = 'CREATED') THEN
        RETURN NULL;
    END IF;

    -- Restock target: 3x reorder level
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
```

---

### 8.2 Database Triggers

![pgAdmin 4 Triggers & Stock Reservation](C:/Users/sangi/.gemini/antigravity/brain/b2e5f594-8abc-4b94-95b8-05bd599f0e64/screenshot_3_triggers.png)
*Figure 8.2: pgAdmin 4 verifying Trigger 1 stock reservation (`quantity_available` drops while `quantity_reserved` increments).*

#### 1. Trigger 1 (`trg_order_item_reduce_stock`): Immediate Stock Reservation
Moves inventory from `quantity_available` to `quantity_reserved`. If sufficient stock does not exist, an exception is raised, triggering an automatic rollback of the transaction.
```sql
CREATE OR REPLACE FUNCTION fn_order_item_reduce_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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
```

#### 2. Trigger 2 (`trg_inventory_reorder`): Event-Driven Supplier Restocking
Fires automatically whenever `quantity_available` decreases on the `inventory` table. Evaluates reorder conditions and triggers autonomous PO creation.
```sql
CREATE OR REPLACE FUNCTION fn_inventory_reorder()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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
```

#### 3. Trigger 3 (`trg_orders_status_flow`): State Machine Validation
Enforces legal status progressions and prevents invalid operations (e.g., cancelling an order that has already shipped).
```sql
CREATE OR REPLACE FUNCTION fn_orders_status_flow()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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

    RAISE EXCEPTION 'Illegal order status transition from % to %',
                    OLD.order_status, NEW.order_status;
END;
$$;

CREATE TRIGGER trg_orders_status_flow
BEFORE UPDATE OF order_status ON orders
FOR EACH ROW EXECUTE FUNCTION fn_orders_status_flow();
```

#### 4. Trigger 4 (`trg_order_item_total`): Total Amount Synchronization
```sql
CREATE OR REPLACE FUNCTION fn_order_item_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE orders SET total_amount = get_order_total(NEW.order_id)
     WHERE order_id = NEW.order_id;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_order_item_total
AFTER INSERT ON order_item
FOR EACH ROW EXECUTE FUNCTION fn_order_item_total();
```

---

### 8.3 Stored Procedures & Explicit Cursor

![pgAdmin 4 Cursor Procedure Execution in Messages Console](C:/Users/sangi/.gemini/antigravity/brain/b2e5f594-8abc-4b94-95b8-05bd599f0e64/screenshot_4_cursor.png)
*Figure 8.3: pgAdmin 4 executing Procedure `check_reorder_levels()` with the Messages tab displaying cursor iteration and PO generation notices.*

#### 1. Procedure 9 (Explicit Cursor): `check_reorder_levels`
Demonstrates explicit cursor declaration, opening, iterative record fetching, and closure to perform bulk reordering across all catalog items.
```sql
CREATE OR REPLACE PROCEDURE check_reorder_levels(INOUT p_created INT DEFAULT 0)
LANGUAGE plpgsql AS $$
DECLARE
    -- Explicit cursor declaring low stock products without open purchase orders
    c_low CURSOR FOR
        SELECT p.product_id, p.product_name, p.reorder_level,
               get_total_stock(p.product_id) AS total_stock
          FROM product p
         WHERE get_total_stock(p.product_id) < p.reorder_level
           AND NOT EXISTS (
               SELECT 1 FROM purchase_order po
               WHERE po.product_id = p.product_id AND po.po_status = 'CREATED'
           )
         ORDER BY p.product_id;

    r    RECORD;
    v_wh INT;
    v_po INT;
BEGIN
    p_created := 0;
    
    -- 1. Open the explicit cursor
    OPEN c_low;
    
    -- 2. Fetch loop
    LOOP
        FETCH c_low INTO r;
        EXIT WHEN NOT FOUND;

        -- Target the warehouse with the least stock for this product
        SELECT warehouse_id INTO v_wh
          FROM inventory WHERE product_id = r.product_id
         ORDER BY quantity_available, warehouse_id LIMIT 1;

        IF v_wh IS NULL THEN
            SELECT warehouse_id INTO v_wh FROM warehouse ORDER BY warehouse_id LIMIT 1;
        END IF;

        -- 3. Raise purchase order via helper
        v_po := raise_reorder_po(r.product_id, v_wh);
        IF v_po IS NOT NULL THEN
            p_created := p_created + 1;
            RAISE NOTICE 'Cursor generated PO % for product % (Current Stock: %, Threshold: %)',
                         v_po, r.product_name, r.total_stock, r.reorder_level;
        END IF;
    END LOOP;
    
    -- 4. Close the cursor
    CLOSE c_low;
END;
$$;
```

#### 2. Procedure 1: `place_order` (Multi-Warehouse Splitting)
```sql
CREATE OR REPLACE PROCEDURE place_order(
    p_customer_id INT,
    p_items       JSONB,
    INOUT p_order_id INT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item RECORD;
    v_wh RECORD;
    v_need INT;
    v_take INT;
    v_unit_price NUMERIC(10,2);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM customer WHERE customer_id = p_customer_id AND status = 'ACTIVE') THEN
        RAISE EXCEPTION 'Customer % does not exist or is inactive', p_customer_id;
    END IF;

    -- Pre-check: Verify total nationwide stock across all warehouses
    FOR v_item IN SELECT (elem->>'product_id')::INT AS product_id,
                         (elem->>'quantity')::INT   AS quantity
                    FROM jsonb_array_elements(p_items) AS elem
    LOOP
        IF get_total_stock(v_item.product_id) < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock: product % has % available, requested %',
                            v_item.product_id, get_total_stock(v_item.product_id), v_item.quantity;
        END IF;
    END LOOP;

    INSERT INTO orders (customer_id, order_status, total_amount)
    VALUES (p_customer_id, 'PLACED', 0)
    RETURNING order_id INTO p_order_id;

    -- Allocate stock, splitting across warehouses if needed
    FOR v_item IN SELECT (elem->>'product_id')::INT AS product_id,
                         (elem->>'quantity')::INT   AS quantity
                    FROM jsonb_array_elements(p_items) AS elem
    LOOP
        SELECT unit_price INTO v_unit_price FROM product WHERE product_id = v_item.product_id;
        v_need := v_item.quantity;

        FOR v_wh IN SELECT warehouse_id, quantity_available
                      FROM inventory
                     WHERE product_id = v_item.product_id AND quantity_available > 0
                     ORDER BY quantity_available DESC, warehouse_id
        LOOP
            v_take := LEAST(v_need, v_wh.quantity_available);
            INSERT INTO order_item (order_id, product_id, warehouse_id, quantity, unit_price)
            VALUES (p_order_id, v_item.product_id, v_wh.warehouse_id, v_take, v_unit_price);

            v_need := v_need - v_take;
            EXIT WHEN v_need = 0;
        END LOOP;

        IF v_need > 0 THEN
            RAISE EXCEPTION 'Stock shortage occurred during allocation for product %', v_item.product_id;
        END IF;
    END LOOP;
END;
$$;
```

#### 3. Procedure 2: `cancel_order` (Stock Restoration)
```sql
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
```

#### 4. Procedure 5: `receive_purchase_order` (Capacity Enforcement)
```sql
CREATE OR REPLACE PROCEDURE receive_purchase_order(p_po_id INT, p_received_date DATE DEFAULT CURRENT_DATE)
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

    -- Enforce physical warehouse storage capacity
    SELECT capacity INTO v_cap FROM warehouse WHERE warehouse_id = v_po.warehouse_id;
    IF get_warehouse_load(v_po.warehouse_id) + v_po.quantity_ordered > v_cap THEN
        RAISE EXCEPTION 'Warehouse % lacks capacity: current load % + incoming % exceeds limit %',
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
```

---

## 9. Real-World Transaction Demonstrations

### Transaction 1: Multi-Item Order with Dynamic Warehouse Splitting
* **Operation:** Customer orders 10 units of an item where Warehouse 1 has 6 units and Warehouse 2 has 4 units.
* **Tables Involved:** `orders`, `order_item`, `inventory`.
* **Component Executed:** `CALL place_order(1, '[{"product_id":1, "quantity":10}]', v_order_id);`
* **Database Effect:** Two `order_item` records are generated (6 units from WH 1, 4 units from WH 2). Trigger 1 moves available stock to reserved stock across both warehouses.
* **Result Generated:** Order is placed with status `PLACED`, stock is reserved, and overselling is prevented.

### Transaction 2: Payment Processing & Confirmation
* **Operation:** Customer completes UPI payment for an order.
* **Tables Involved:** `payment`, `orders`.
* **Component Executed:** `CALL record_payment(1, 'UPI', TRUE, 'TXN992817');`
* **Database Effect:** A `payment` record is inserted with status `SUCCESS`. The order status changes from `PLACED` to `CONFIRMED`.
* **Result Generated:** Order is confirmed and ready for warehouse fulfillment.

### Transaction 3: Order Cancellation & Stock Restoration
* **Operation:** Customer cancels a `CONFIRMED` order before shipment.
* **Tables Involved:** `orders`, `inventory`.
* **Component Executed:** `CALL cancel_order(1);`
* **Database Effect:** `orders.order_status` is updated to `CANCELLED`. Procedure restores inventory:
  $$\text{quantity\_available} \leftarrow \text{quantity\_available} + N$$
  $$\text{quantity\_reserved} \leftarrow \text{quantity\_reserved} - N$$
* **Result Generated:** Reserved lock is released and inventory becomes available for other customers.

### Transaction 4: Automated Low-Stock Purchase Order (Trigger 2)
* **Operation:** Customer purchases 7 units of Running Shoes, dropping nationwide stock from 18 to 11 (reorder level is 15).
* **Tables Involved:** `inventory`, `purchase_order`, `supplier`.
* **Component Executed:** Trigger `trg_inventory_reorder` calling `raise_reorder_po()`.
* **Database Effect:** Automatically calculates target order quantity ($3 \times \text{reorder\_level} - \text{stock} = 34\text{ units}$) and inserts a new row into `purchase_order` with supplier lead-time delivery date.
* **Result Generated:** Stock replenishment cycle initiated without manual administrator intervention.

### Transaction 5: Receiving Supplier Delivery
* **Operation:** Supplier delivers goods for Purchase Order #1 at Chennai Hub.
* **Tables Involved:** `purchase_order`, `inventory`, `warehouse`.
* **Component Executed:** `CALL receive_purchase_order(1);`
* **Database Effect:** Validates that warehouse capacity is not exceeded. Updates `po_status` to `RECEIVED`, records `actual_delivery = CURRENT_DATE`, and increments `quantity_available` by delivered amount.
* **Result Generated:** Available inventory updated and purchase order cycle concluded.

---

## 10. Conclusion

The **Smart E-Commerce Order, Inventory & Supply Chain Management System** demonstrates the transition from traditional, vulnerable application-side computation to an **Active Relational Database Architecture**.

### Key Achievements:
1. **100% ACID Integrity:** Multi-item orders, inventory reservation, and warehouse capacity constraints are enforced at the database layer.
2. **Elimination of Race Conditions:** The dual-state `AVAILABLE` vs `RESERVED` inventory model prevents negative stock during concurrent customer checkouts.
3. **Autonomous Supply Chain:** Triggers and explicit PL/pgSQL cursors automate purchase order creation and supplier lead-time management.
4. **True Role-Based Security:** Leverages PostgreSQL DCL (`GRANT`/`REVOKE`, `SECURITY DEFINER`) to restrict table access according to user roles.
5. **Interactive Full-Stack Demonstration:** A responsive Python/Flask frontend with single-click execution connects directly to PostgreSQL 18, demonstrating end-to-end transactional workflows.

---
*Report prepared for BCSE302P – Database Systems Lab evaluation.*
