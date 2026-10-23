-- =====================================================================
-- Smart E-Commerce Order, Inventory & Supply Chain Management System
-- BCSE302L Database Systems - Course Project
-- File 01: Schema (9 tables, constraints, indexes)      DBMS: PostgreSQL
-- =====================================================================

DROP TABLE IF EXISTS purchase_order, payment, order_item, orders, inventory,
                     product, warehouse, supplier, customer CASCADE;

-- ---------------------------------------------------------------------
-- CUSTOMER
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- SUPPLIER
-- ---------------------------------------------------------------------
CREATE TABLE supplier (
    supplier_id      SERIAL        PRIMARY KEY,
    supplier_name    VARCHAR(100)  NOT NULL,
    email            VARCHAR(120),
    phone            VARCHAR(15),
    lead_time_days   INT           NOT NULL CHECK (lead_time_days > 0),
    status           VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- ---------------------------------------------------------------------
-- PRODUCT   (many products : one main supplier)
-- ---------------------------------------------------------------------
CREATE TABLE product (
    product_id     SERIAL         PRIMARY KEY,
    product_name   VARCHAR(120)   NOT NULL,
    category       VARCHAR(60),
    brand          VARCHAR(60),
    unit_price     NUMERIC(10,2)  NOT NULL CHECK (unit_price > 0),
    reorder_level  INT            NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
    supplier_id    INT            NOT NULL REFERENCES supplier(supplier_id)
);

-- ---------------------------------------------------------------------
-- WAREHOUSE
-- ---------------------------------------------------------------------
CREATE TABLE warehouse (
    warehouse_id    SERIAL        PRIMARY KEY,
    warehouse_name  VARCHAR(80)   NOT NULL UNIQUE,
    city            VARCHAR(60),
    capacity        INT           NOT NULL CHECK (capacity > 0)
);

-- ---------------------------------------------------------------------
-- INVENTORY  (resolves the M:N between PRODUCT and WAREHOUSE)
-- ---------------------------------------------------------------------
CREATE TABLE inventory (
    inventory_id        SERIAL     PRIMARY KEY,
    product_id          INT        NOT NULL REFERENCES product(product_id),
    warehouse_id        INT        NOT NULL REFERENCES warehouse(warehouse_id),
    quantity_available  INT        NOT NULL CHECK (quantity_available >= 0),
    quantity_reserved   INT        NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    last_updated        TIMESTAMP  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_inventory_product_wh UNIQUE (product_id, warehouse_id)
);

-- ---------------------------------------------------------------------
-- ORDERS  (named ORDERS because ORDER is a reserved word)
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id      SERIAL         PRIMARY KEY,
    customer_id   INT            NOT NULL REFERENCES customer(customer_id),
    order_date    TIMESTAMP      NOT NULL DEFAULT NOW(),
    order_status  VARCHAR(10)    NOT NULL DEFAULT 'PLACED'
                  CHECK (order_status IN ('PLACED','CONFIRMED','SHIPPED','DELIVERED','CANCELLED')),
    total_amount  NUMERIC(12,2)  NOT NULL DEFAULT 0 CHECK (total_amount >= 0)
);

-- ---------------------------------------------------------------------
-- ORDER_ITEM  (unit_price is the price AT THE TIME OF SALE)
-- ---------------------------------------------------------------------
CREATE TABLE order_item (
    order_item_id  SERIAL         PRIMARY KEY,
    order_id       INT            NOT NULL REFERENCES orders(order_id),
    product_id     INT            NOT NULL REFERENCES product(product_id),
    warehouse_id   INT            NOT NULL REFERENCES warehouse(warehouse_id),
    quantity       INT            NOT NULL CHECK (quantity > 0),
    unit_price     NUMERIC(10,2)  NOT NULL CHECK (unit_price > 0)
);

-- ---------------------------------------------------------------------
-- PAYMENT  (1:1 with ORDERS, enforced by UNIQUE on order_id)
-- ---------------------------------------------------------------------
CREATE TABLE payment (
    payment_id      SERIAL         PRIMARY KEY,
    order_id        INT            NOT NULL UNIQUE REFERENCES orders(order_id),
    payment_method  VARCHAR(12)    NOT NULL
                    CHECK (payment_method IN ('UPI','CARD','NETBANKING','COD')),
    payment_status  VARCHAR(10)    NOT NULL DEFAULT 'PENDING'
                    CHECK (payment_status IN ('PENDING','SUCCESS','FAILED')),
    amount          NUMERIC(12,2)  NOT NULL CHECK (amount > 0),
    payment_date    TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- PURCHASE_ORDER  (restocking request to a supplier)
-- ---------------------------------------------------------------------
CREATE TABLE purchase_order (
    po_id              SERIAL     PRIMARY KEY,
    product_id         INT        NOT NULL REFERENCES product(product_id),
    supplier_id        INT        NOT NULL REFERENCES supplier(supplier_id),
    warehouse_id       INT        NOT NULL REFERENCES warehouse(warehouse_id),
    quantity_ordered   INT        NOT NULL CHECK (quantity_ordered > 0),
    po_date            DATE       NOT NULL DEFAULT CURRENT_DATE,
    expected_delivery  DATE,
    actual_delivery    DATE,
    po_status          VARCHAR(10) NOT NULL DEFAULT 'CREATED'
                       CHECK (po_status IN ('CREATED','RECEIVED','CANCELLED')),
    CONSTRAINT chk_po_expected CHECK (expected_delivery IS NULL OR expected_delivery >= po_date),
    CONSTRAINT chk_po_actual   CHECK (actual_delivery   IS NULL OR actual_delivery   >= po_date),
    CONSTRAINT chk_po_received CHECK ((po_status = 'RECEIVED') = (actual_delivery IS NOT NULL))
);

-- ---------------------------------------------------------------------
-- INDEXES (non-functional requirement: product name, order date, FKs)
-- PK and UNIQUE columns are indexed automatically.
-- ---------------------------------------------------------------------
CREATE INDEX idx_product_name        ON product (product_name);
CREATE INDEX idx_product_supplier    ON product (supplier_id);
CREATE INDEX idx_orders_date         ON orders (order_date);
CREATE INDEX idx_orders_customer     ON orders (customer_id);
CREATE INDEX idx_order_item_order    ON order_item (order_id);
CREATE INDEX idx_order_item_product  ON order_item (product_id);
CREATE INDEX idx_order_item_wh       ON order_item (warehouse_id);
CREATE INDEX idx_inventory_wh        ON inventory (warehouse_id);
CREATE INDEX idx_po_product          ON purchase_order (product_id);
CREATE INDEX idx_po_supplier         ON purchase_order (supplier_id);
CREATE INDEX idx_po_warehouse        ON purchase_order (warehouse_id);
CREATE INDEX idx_po_status           ON purchase_order (po_status);
