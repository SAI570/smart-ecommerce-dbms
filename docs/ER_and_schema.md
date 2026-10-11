# ER diagram and relational schema

Same design as Review I (9 entities, 11 relationships, 3NF).

```mermaid
erDiagram
    CUSTOMER  ||--o{ ORDERS         : places
    ORDERS    ||--|{ ORDER_ITEM     : contains
    PRODUCT   ||--o{ ORDER_ITEM     : "refers to"
    WAREHOUSE ||--o{ ORDER_ITEM     : "fulfilled from"
    ORDERS    ||--o| PAYMENT        : "paid by"
    SUPPLIER  ||--o{ PRODUCT        : "supplied by"
    PRODUCT   ||--o{ INVENTORY      : "stocked in"
    WAREHOUSE ||--o{ INVENTORY      : "stored at"
    PRODUCT   ||--o{ PURCHASE_ORDER : "restocked by"
    SUPPLIER  ||--o{ PURCHASE_ORDER : fulfils
    WAREHOUSE ||--o{ PURCHASE_ORDER : "delivered to"

    CUSTOMER { int customer_id PK
               string name
               string email UK
               string phone
               string address
               string city
               date registered_date
               string status }
    SUPPLIER { int supplier_id PK
               string supplier_name
               string email
               string phone
               int lead_time_days
               string status }
    PRODUCT  { int product_id PK
               string product_name
               string category
               string brand
               decimal unit_price
               int reorder_level
               int supplier_id FK }
    WAREHOUSE { int warehouse_id PK
                string warehouse_name UK
                string city
                int capacity }
    INVENTORY { int inventory_id PK
                int product_id FK
                int warehouse_id FK
                int quantity_available
                int quantity_reserved
                timestamp last_updated }
    ORDERS    { int order_id PK
                int customer_id FK
                timestamp order_date
                string order_status
                decimal total_amount }
    ORDER_ITEM { int order_item_id PK
                 int order_id FK
                 int product_id FK
                 int warehouse_id FK
                 int quantity
                 decimal unit_price }
    PAYMENT   { int payment_id PK
                int order_id FK,UK
                string payment_method
                string payment_status
                decimal amount
                timestamp payment_date }
    PURCHASE_ORDER { int po_id PK
                     int product_id FK
                     int supplier_id FK
                     int warehouse_id FK
                     int quantity_ordered
                     date po_date
                     date expected_delivery
                     date actual_delivery
                     string po_status }
```

PRODUCT and WAREHOUSE are many-to-many; INVENTORY resolves it (UNIQUE on product_id + warehouse_id).
The full constraint list is in `sql/01_schema.sql`.
