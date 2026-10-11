# Smart E-Commerce Order, Inventory & Supply Chain Management System

BCSE302L Database Systems – course project (Review I design → full implementation).
Database: **PostgreSQL 14+**. Front end: **Python / Flask**.

The point of the project is that **the database keeps the business correct**: stock can't be oversold,
stock changes with every order, and a purchase order to the supplier is raised automatically when a
product runs low. The web app only sends SQL and shows results.

## 1. Quick start

```bash
# PostgreSQL must be running. Replace 'postgres' with your DB user if different.
./setup.sh                     # Windows: setup.bat postgres
cd app
export DB_USER=postgres DB_PASSWORD=yourpassword      # Windows: set DB_USER=... & set DB_PASSWORD=...
python app.py                  # open http://localhost:5000
```

`setup.sh` creates the database `smart_ecommerce`, loads schema + sample data, runs the 31 database
tests, and installs Flask + psycopg2. Manual alternative:

```bash
createdb smart_ecommerce
cd sql && psql -d smart_ecommerce -f 00_install_all.sql
```

On the sign-in screen pick a user type (no passwords – this demonstrates the database, not authentication).
Each type connects under its own PostgreSQL role (`customer_role`, `admin_role`, `warehouse_role`,
`procurement_role`), so permissions are enforced by `GRANT`/`REVOKE`, not just hidden menus.
Set `USE_DB_ROLES=0` to disable this if your DB user cannot `SET ROLE`.

## 2. What is where

| Folder / file | Contents |
|---|---|
| `sql/01_schema.sql` | 9 tables, PK/FK, NOT NULL, UNIQUE, CHECK, DEFAULT, 12 indexes |
| `sql/02_functions.sql` | `get_order_total`, `get_total_stock`, `get_warehouse_load` |
| `sql/03_triggers.sql` | Trigger 1 (reduce stock), Trigger 2 (auto purchase order), + total, status-flow, timestamp triggers |
| `sql/04_procedures.sql` | `place_order`, `cancel_order`, `record_payment`, `update_order_status`, `receive_purchase_order`, `check_reorder_levels` (**cursor**), `set_stock`, PO create/cancel |
| `sql/05_seed_data.sql` | 13 customers, 6 suppliers, 4 warehouses, 20 products, 22 orders (built *through* the procedures), PO history |
| `sql/06_views_reports.sql` | Views behind the reports (sales, revenue, best sellers, low stock, supplier performance) |
| `sql/07_queries.sql` | **20 demo queries**: joins, GROUP BY/HAVING, subqueries, window functions, CTE, UNION, anti-joins |
| `sql/08_roles_security.sql` | The four DB roles and their GRANTs |
| `sql/09_transaction_demo.sql` | Atomicity / consistency / isolation / durability demo with SAVEPOINT |
| `tests/test_core.sql` | 31 automated checks (rolls back, leaves data untouched) |
| `tests/concurrency_test.sh` | Two simultaneous buyers of the last stock |
| `app/` | Flask application (`app.py`, `db.py`, templates, CSS) |
| `docs/ER_and_schema.md` | ER diagram (Mermaid) |

## 3. Review I design → implementation

| Review I item | Implemented as |
|---|---|
| FR1–FR4 master data & multi-warehouse stock | Customers / Products / Suppliers / Warehouses / Inventory screens; `set_stock` procedure |
| FR5 order with many items, reject if short | `place_order` (JSON item list; whole order rolls back on any shortage; splits a line across warehouses) |
| FR6 reduce stock on order item (Trigger 1) | `trg_order_item_reduce_stock`: *available → reserved* |
| FR7 payment | `record_payment`: SUCCESS → CONFIRMED, FAILED → stays PLACED (retry allowed), COD → CONFIRMED + PENDING until delivery |
| FR8 cancel + restore stock (procedure) | `cancel_order` |
| FR9 auto reorder (Trigger 2 / cursor) | `trg_inventory_reorder` + `check_reorder_levels` (explicit cursor) |
| FR10 receive PO delivery | `receive_purchase_order` (also enforces warehouse capacity) |
| FR11 functions | `get_order_total`, `get_total_stock` |
| FR12 reports | Reports page + views + `07_queries.sql` |
| Non-functional: integrity, ACID, indexes | Constraints, procedures run as single transactions, `09_transaction_demo.sql`, indexes on names/dates/FKs |

### Stock model
`available` = sellable. `reserved` = held for orders that are PLACED/CONFIRMED but not shipped.
Order placed: available −n, reserved +n. Cancelled: reverse. Shipped: reserved −n (stock leaves).
A reorder is triggered when a product's **total available across all warehouses** drops below its
reorder level and no purchase order is already open for it. Quantity ordered = enough to reach 3 × reorder level.

### Choices to mention in the viva (small deviations from the Review I text)
* **PostgreSQL / PL/pgSQL instead of Oracle PL/SQL.** Same concepts (procedures, functions, cursor, triggers);
  `RAISE EXCEPTION` ≈ `RAISE_APPLICATION_ERROR`, `CALL proc(..., INOUT x)` ≈ OUT parameters.
* FR7 says a failed payment sets the order to FAILED, but the Review I `order_status` CHECK has no FAILED value.
  I kept the schema as designed: the **payment** becomes FAILED and the order stays PLACED so it can be retried or cancelled.
* Three extra triggers beyond the planned two: order total maintenance, legal order-status transitions
  (PLACED→CONFIRMED→SHIPPED→DELIVERED, cancel only before shipping), and `last_updated`.
* Refunds are out of scope: cancelling a paid order keeps its payment row (there is no REFUNDED status in the design).
* Customers can see only their own orders in the app; this is an application filter. Row-level security would be the production answer.

## 4. Demo script (≈5 minutes)
1. Sign in as **Administrator → Dashboard**: note USB-C Hub, Mixer Grinder and Dumbbell Set are low and already have POs (raised by the trigger while the seed orders were placed).
2. **Inventory**: Wireless Mouse has available/reserved quantities in 3 warehouses.
3. **New order**: customer Aarav, 7 × Wireless Mouse + 1 × Running Shoes → open the order: each line shows its warehouse. Pay by UPI.
4. Order 100 × Smartphone Stand: it is **split over several warehouses**. Order 5000: **rejected**, nothing changes.
5. Cancel an order: stock returns (check Inventory).
6. Order enough Running Shoes to cross the reorder level (15): a **purchase order appears** automatically. Sign in as **Warehouse Manager** and *Receive* it: stock goes up.
7. **Procurement** → *Run reorder check* (the cursor). **Reports** → supplier on-time %, monthly revenue.
8. In psql: `\i 07_queries.sql`, `\i 09_transaction_demo.sql`, run `tests/test_core.sql` and `tests/concurrency_test.sh`.

## 5. Troubleshooting
* `psycopg2` install fails → `pip install psycopg2-binary` (or install `libpq-dev` and use `psycopg2`).
* `permission denied` / `SET ROLE` errors → connect as the user that ran `00_install_all.sql`, or set `USE_DB_ROLES=0`.
* Re-load a clean database any time with `./setup.sh`.
