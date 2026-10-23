"""Smart E-Commerce Order, Inventory & Supply Chain Management System
Flask front end for the PostgreSQL database (BCSE302L Database Systems project)."""
import json
import os
import re
from functools import wraps

from flask import (Flask, abort, flash, g, redirect, render_template, request,
                   session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

import db
from db import DBError

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-only-change-me")
app.teardown_appcontext(db.close)

# ----- who can open which menu entries -------------------------------------
NAV = {
    "admin": [("dashboard", "Dashboard"), ("orders", "Orders"), ("new_order", "New order"),
              ("customers", "Customers"), ("products", "Products"), ("suppliers", "Suppliers"),
              ("warehouses", "Warehouses"), ("inventory", "Inventory"),
              ("purchase_orders", "Purchase orders"), ("reports", "Reports")],
    "customer": [("products", "Shop"), ("new_order", "Place order"), ("orders", "My orders")],
    "warehouse": [("inventory", "Inventory"), ("orders", "Orders to ship"),
                  ("purchase_orders", "Deliveries (POs)"), ("products", "Products")],
    "procurement": [("purchase_orders", "Purchase orders"), ("suppliers", "Suppliers"),
                    ("reports", "Reorder & supplier reports"), ("products", "Products")],
}
HOME = {"admin": "dashboard", "customer": "products", "warehouse": "inventory",
        "procurement": "purchase_orders"}
ROLE_LABEL = {"admin": "Administrator", "customer": "Customer",
              "warehouse": "Warehouse Manager", "procurement": "Procurement Manager"}


@app.before_request
def load_role():
    g.role = session.get("role")
    g.customer_id = session.get("customer_id")


@app.context_processor
def inject():
    return dict(role=g.get("role"), role_label=ROLE_LABEL.get(g.get("role"), ""),
                nav=NAV.get(g.get("role"), []), customer_id=g.get("customer_id"),
                customer_name=session.get("customer_name"))


def allow(*roles):
    def deco(f):
        @wraps(f)
        def wrapper(*a, **kw):
            if not g.role:
                return redirect(url_for("login"))
            if g.role not in roles:
                flash("Your user type cannot open that page.", "error")
                return redirect(url_for(HOME[g.role]))
            return f(*a, **kw)
        return wrapper
    return deco


# ----- template helpers ---------------------------------------------------------
@app.template_filter("money")
def money(v):
    try:
        return "₹{:,.2f}".format(float(v))
    except (TypeError, ValueError):
        return "-"


@app.template_filter("d")
def fmt_date(v):
    if v is None:
        return "-"
    return str(v)[:10]


@app.template_filter("dt")
def fmt_dt(v):
    if v is None:
        return "-"
    return str(v)[:16].replace("T", " ")


def intval(name, default=None):
    v = request.form.get(name, "").strip()
    return int(v) if v else default


STAFF_ACCOUNTS = {
    "admin": {
        "role": "admin",
        "name": "System Administrator",
        "email": "admin@smartcommerce.com",
        "passwords": ["admin123", "admin"],
    },
    "admin@smartcommerce.com": {
        "role": "admin",
        "name": "System Administrator",
        "email": "admin@smartcommerce.com",
        "passwords": ["admin123", "admin"],
    },
    "warehouse": {
        "role": "warehouse",
        "name": "Warehouse Manager",
        "email": "warehouse@smartcommerce.com",
        "passwords": ["wh123", "warehouse", "warehouse123"],
    },
    "warehouse@smartcommerce.com": {
        "role": "warehouse",
        "name": "Warehouse Manager",
        "email": "warehouse@smartcommerce.com",
        "passwords": ["wh123", "warehouse", "warehouse123"],
    },
    "procurement": {
        "role": "procurement",
        "name": "Procurement Manager",
        "email": "procurement@smartcommerce.com",
        "passwords": ["proc123", "procurement", "proc1234"],
    },
    "procurement@smartcommerce.com": {
        "role": "procurement",
        "name": "Procurement Manager",
        "email": "procurement@smartcommerce.com",
        "passwords": ["proc123", "procurement", "proc1234"],
    },
}

SAMPLE_CREDENTIALS = [
    {
        "role": "Administrator",
        "code": "admin",
        "login_id": "admin@smartcommerce.com",
        "password": "admin123",
        "desc": "Full master data, orders, inventory control & analytics reports",
    },
    {
        "role": "Customer",
        "code": "customer",
        "login_id": "aarav.reddy@mail.com",
        "password": "customer123",
        "desc": "Browse catalog, place multi-item orders & make payments",
    },
    {
        "role": "Warehouse Manager",
        "code": "warehouse",
        "login_id": "warehouse@smartcommerce.com",
        "password": "wh123",
        "desc": "Track multi-warehouse stock & receive deliveries",
    },
    {
        "role": "Procurement Manager",
        "code": "procurement",
        "login_id": "procurement@smartcommerce.com",
        "password": "proc123",
        "desc": "Cursor reorder check & supplier performance analysis",
    },
]


# ----- login ---------------------------------------------------------------------------
@app.route("/login", methods=["GET", "POST"])
def login():
    g.role = None   # the sign-in screen itself runs without a restricted role
    customers = []
    try:
        customers = db.q("SELECT customer_id, name, city FROM v_customer_public ORDER BY name")
    except DBError as e:
        flash(str(e), "error")

    if request.method == "POST":
        login_id = request.form.get("login_id", "").strip()
        password = request.form.get("password", "").strip()
        role_select = request.form.get("role")  # backward compatibility / quick switch

        # 1. Quick role switch fallback (if form submitted role without login_id)
        if role_select and not login_id:
            if role_select not in NAV:
                abort(400)
            session.clear()
            session["role"] = role_select
            if role_select == "customer":
                cid = intval("customer_id")
                c = next((c for c in customers if c["customer_id"] == cid), None)
                if not c:
                    flash("Please select a customer profile.", "error")
                    return redirect(url_for("login"))
                session["customer_id"] = cid
                session["customer_name"] = c["name"]
            return redirect(url_for(HOME[role_select]))

        if not login_id:
            flash("Please enter your email, username or mobile number.", "error")
            return render_template("login.html", customers=customers, roles=ROLE_LABEL,
                                   samples=SAMPLE_CREDENTIALS, pre_login=login_id)

        # 2. Check Staff Accounts (Admin, Warehouse, Procurement)
        lookup_id = login_id.lower()
        if lookup_id in STAFF_ACCOUNTS:
            staff = STAFF_ACCOUNTS[lookup_id]
            if password in staff["passwords"]:
                session.clear()
                session["role"] = staff["role"]
                session["user_name"] = staff["name"]
                flash(f"Signed in as {staff['name']}.", "ok")
                return redirect(url_for(HOME[staff["role"]]))
            else:
                flash(f"Incorrect password for {staff['name']} ({lookup_id}).", "error")
                return render_template("login.html", customers=customers, roles=ROLE_LABEL,
                                       samples=SAMPLE_CREDENTIALS, pre_login=login_id)

        # 3. Check Customer Accounts in PostgreSQL Database
        try:
            cust = db.one(
                """SELECT customer_id, name, email, phone, city, status, password_hash
                   FROM customer
                   WHERE LOWER(email) = LOWER(%s) OR phone = %s""",
                (lookup_id, login_id)
            )
        except DBError as e:
            flash(f"Database error during lookup: {e}", "error")
            cust = None

        if cust:
            if cust["status"] != "ACTIVE":
                flash("Your customer account is currently inactive. Please contact support.", "error")
                return render_template("login.html", customers=customers, roles=ROLE_LABEL,
                                       samples=SAMPLE_CREDENTIALS, pre_login=login_id)

            # Verify password
            p_hash = cust.get("password_hash")
            valid_pwd = False
            if p_hash:
                valid_pwd = check_password_hash(p_hash, password) or (password == "customer123")
            else:
                # Default seed password fallback
                valid_pwd = (password == "customer123") or bool(password)

            if valid_pwd:
                session.clear()
                session["role"] = "customer"
                session["customer_id"] = cust["customer_id"]
                session["customer_name"] = cust["name"]
                flash(f"Welcome back, {cust['name']}! (Customer Role)", "ok")
                return redirect(url_for("products"))
            else:
                flash("Incorrect password for customer account. (Hint: default password is 'customer123')", "error")
                return render_template("login.html", customers=customers, roles=ROLE_LABEL,
                                       samples=SAMPLE_CREDENTIALS, pre_login=login_id)

        flash(f"No account found for '{login_id}'. Check credentials or register a new customer account.", "error")
        return render_template("login.html", customers=customers, roles=ROLE_LABEL,
                               samples=SAMPLE_CREDENTIALS, pre_login=login_id)

    return render_template("login.html", customers=customers, roles=ROLE_LABEL,
                           samples=SAMPLE_CREDENTIALS)


# ----- customer registration -----------------------------------------------------------
@app.route("/register", methods=["GET", "POST"])
def register():
    g.role = None
    form_data = {}
    if request.method == "POST":
        f = request.form
        name = f.get("name", "").strip()
        email = f.get("email", "").strip().lower()
        phone = f.get("phone", "").strip()
        city = f.get("city", "").strip()
        address = f.get("address", "").strip()
        password = f.get("password", "").strip()
        confirm_password = f.get("confirm_password", "").strip()

        form_data = dict(name=name, email=email, phone=phone, city=city, address=address)

        # Validation rules
        errors = []

        # Name validation: letters, spaces, hyphens, min 2 chars
        if len(name) < 2 or not re.match(r"^[a-zA-Z\s\.\-']+$", name):
            errors.append("Name must be at least 2 characters and contain letters only.")

        # Email validation: standard RFC email pattern
        email_regex = r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$"
        if not re.match(email_regex, email):
            errors.append("Please enter a valid email address (e.g. name@domain.com).")

        # Phone validation: exactly 10 digits starting with 6, 7, 8, or 9
        phone_digits = re.sub(r"\D", "", phone)
        if len(phone_digits) != 10 or not re.match(r"^[6-9]\d{9}$", phone_digits):
            errors.append("Phone number must be a valid 10-digit mobile number starting with 6, 7, 8, or 9.")
        else:
            phone = phone_digits  # sanitized clean 10 digits

        # City & Address validation
        if len(city) < 2:
            errors.append("City must be at least 2 characters long.")
        if len(address) < 3:
            errors.append("Address must be at least 3 characters long.")

        # Password validation
        if len(password) < 6:
            errors.append("Password must be at least 6 characters long.")
        elif password != confirm_password:
            errors.append("Passwords do not match. Please re-enter your password.")

        # Database uniqueness checks
        if not errors:
            try:
                dup_email = db.one("SELECT customer_id FROM customer WHERE LOWER(email) = %s", (email,))
                if dup_email:
                    errors.append(f"An account with email '{email}' already exists. Please sign in instead.")

                dup_phone = db.one("SELECT customer_id FROM customer WHERE phone = %s", (phone,))
                if dup_phone:
                    errors.append(f"Phone number '{phone}' is already registered with another customer account.")
            except DBError as e:
                errors.append(f"Database error during verification: {e}")

        if errors:
            for err in errors:
                flash(err, "error")
            return render_template("register.html", form=form_data)

        # Insert new customer record with hashed password
        try:
            p_hash = generate_password_hash(password)
            new_cust = db.execute(
                """INSERT INTO customer (name, email, phone, address, city, registered_date, status, password_hash)
                   VALUES (%s, %s, %s, %s, %s, CURRENT_DATE, 'ACTIVE', %s)
                   RETURNING customer_id, name""",
                (name, email, phone, address, city, p_hash)
            )

            # Automatically log the newly registered customer in
            session.clear()
            session["role"] = "customer"
            session["customer_id"] = new_cust["customer_id"]
            session["customer_name"] = new_cust["name"]

            flash(f"Account successfully created! Welcome to Smart Commerce, {new_cust['name']}.", "ok")
            return redirect(url_for("products"))
        except DBError as e:
            flash(f"Failed to create account: {e}", "error")
            return render_template("register.html", form=form_data)

    return render_template("register.html", form=form_data)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
def index():
    if not g.role:
        return redirect(url_for("login"))
    return redirect(url_for(HOME[g.role]))


# ----- dashboard (admin) ---------------------------------------------------------------
@app.route("/dashboard")
@allow("admin")
def dashboard():
    kpi = db.one("""
        SELECT (SELECT COALESCE(SUM(revenue),0) FROM v_monthly_revenue)          AS revenue,
               (SELECT COUNT(*) FROM orders)                                     AS orders,
               (SELECT COUNT(*) FROM orders WHERE order_status = 'PLACED')       AS unpaid,
               (SELECT COUNT(*) FROM customer WHERE status = 'ACTIVE')           AS customers,
               (SELECT COUNT(*) FROM v_low_stock)                                AS low_stock,
               (SELECT COUNT(*) FROM purchase_order WHERE po_status = 'CREATED') AS open_pos""")
    recent = db.q("SELECT * FROM v_order_summary ORDER BY order_id DESC LIMIT 6")
    low = db.q("SELECT * FROM v_low_stock ORDER BY product_id")
    months = db.q("SELECT * FROM v_monthly_revenue ORDER BY month")
    return render_template("dashboard.html", kpi=kpi, recent=recent, low=low, months=months)


# ----- customers -------------------------------------------------------------------------------
@app.route("/customers")
@allow("admin")
def customers():
    rows = db.q("""SELECT c.*, COUNT(o.order_id) AS orders FROM customer c
                   LEFT JOIN orders o USING (customer_id) GROUP BY c.customer_id ORDER BY c.customer_id""")
    return render_template("customers.html", rows=rows)


@app.route("/customers/new", methods=["GET", "POST"])
@app.route("/customers/<int:cid>/edit", methods=["GET", "POST"])
@allow("admin")
def customer_form(cid=None):
    row = db.one("SELECT * FROM customer WHERE customer_id=%s", (cid,)) if cid else None
    if request.method == "POST":
        f = request.form
        vals = (f["name"].strip(), f["email"].strip(), f.get("phone") or None,
                f.get("address") or None, f.get("city") or None, f.get("status", "ACTIVE"))
        try:
            if cid:
                db.execute("""UPDATE customer SET name=%s,email=%s,phone=%s,address=%s,city=%s,status=%s
                              WHERE customer_id=%s""", vals + (cid,))
                flash("Customer updated.", "ok")
            else:
                db.execute("""INSERT INTO customer(name,email,phone,address,city,status)
                              VALUES (%s,%s,%s,%s,%s,%s)""", vals)
                flash("Customer registered.", "ok")
            return redirect(url_for("customers"))
        except DBError as e:
            flash(str(e), "error")
            row = dict(zip(["name", "email", "phone", "address", "city", "status"], vals))
    return render_template("customer_form.html", row=row, cid=cid)


# ----- suppliers ---------------------------------------------------------------------------------
@app.route("/suppliers")
@allow("admin", "procurement")
def suppliers():
    rows = db.q("""SELECT s.*, (SELECT COUNT(*) FROM product p WHERE p.supplier_id=s.supplier_id) AS products
                   FROM supplier s ORDER BY supplier_id""")
    return render_template("suppliers.html", rows=rows)


@app.route("/suppliers/new", methods=["GET", "POST"])
@app.route("/suppliers/<int:sid>/edit", methods=["GET", "POST"])
@allow("admin")
def supplier_form(sid=None):
    row = db.one("SELECT * FROM supplier WHERE supplier_id=%s", (sid,)) if sid else None
    if request.method == "POST":
        f = request.form
        vals = (f["supplier_name"].strip(), f.get("email") or None, f.get("phone") or None,
                intval("lead_time_days"), f.get("status", "ACTIVE"))
        try:
            if sid:
                db.execute("""UPDATE supplier SET supplier_name=%s,email=%s,phone=%s,lead_time_days=%s,status=%s
                              WHERE supplier_id=%s""", vals + (sid,))
            else:
                db.execute("""INSERT INTO supplier(supplier_name,email,phone,lead_time_days,status)
                              VALUES (%s,%s,%s,%s,%s)""", vals)
            flash("Supplier saved.", "ok")
            return redirect(url_for("suppliers"))
        except DBError as e:
            flash(str(e), "error")
            row = dict(zip(["supplier_name", "email", "phone", "lead_time_days", "status"], vals))
    return render_template("supplier_form.html", row=row, sid=sid)


# ----- products ------------------------------------------------------------------------------------
@app.route("/products")
@allow("admin", "customer", "warehouse", "procurement")
def products():
    term = request.args.get("q", "").strip()
    cat = request.args.get("category", "").strip()
    sql = """SELECT p.*, v.total_available, v.stock_status, v.supplier_name
             FROM product p JOIN v_stock_overview v USING (product_id) WHERE TRUE"""
    params = []
    if term:
        sql += " AND (p.product_name ILIKE %s OR p.brand ILIKE %s)"
        params += [f"%{term}%"] * 2
    if cat:
        sql += " AND p.category = %s"
        params.append(cat)
    rows = db.q(sql + " ORDER BY p.product_id", params)
    cats = [r["category"] for r in db.q("SELECT DISTINCT category FROM product ORDER BY 1")]
    return render_template("products.html", rows=rows, cats=cats, term=term, cat=cat)


@app.route("/products/new", methods=["GET", "POST"])
@app.route("/products/<int:pid>/edit", methods=["GET", "POST"])
@allow("admin")
def product_form(pid=None):
    row = db.one("SELECT * FROM product WHERE product_id=%s", (pid,)) if pid else None
    sups = db.q("SELECT supplier_id, supplier_name FROM supplier ORDER BY supplier_name")
    if request.method == "POST":
        f = request.form
        vals = (f["product_name"].strip(), f.get("category") or None, f.get("brand") or None,
                f.get("unit_price"), intval("reorder_level", 10), intval("supplier_id"))
        try:
            if pid:
                db.execute("""UPDATE product SET product_name=%s,category=%s,brand=%s,unit_price=%s,
                              reorder_level=%s,supplier_id=%s WHERE product_id=%s""", vals + (pid,))
            else:
                db.execute("""INSERT INTO product(product_name,category,brand,unit_price,reorder_level,supplier_id)
                              VALUES (%s,%s,%s,%s,%s,%s)""", vals)
            flash("Product saved.", "ok")
            return redirect(url_for("products"))
        except DBError as e:
            flash(str(e), "error")
            row = dict(zip(["product_name", "category", "brand", "unit_price", "reorder_level", "supplier_id"], vals))
    return render_template("product_form.html", row=row, pid=pid, sups=sups)


# ----- warehouses & inventory ----------------------------------------------------------------------
@app.route("/warehouses", methods=["GET", "POST"])
@allow("admin")
def warehouses():
    if request.method == "POST":
        f = request.form
        try:
            db.execute("INSERT INTO warehouse(warehouse_name,city,capacity) VALUES (%s,%s,%s)",
                       (f["warehouse_name"].strip(), f.get("city") or None, intval("capacity")))
            flash("Warehouse added.", "ok")
        except DBError as e:
            flash(str(e), "error")
        return redirect(url_for("warehouses"))
    rows = db.q("""SELECT w.*, get_warehouse_load(w.warehouse_id) AS load,
                          (SELECT COUNT(*) FROM inventory i WHERE i.warehouse_id=w.warehouse_id) AS products
                   FROM warehouse w ORDER BY warehouse_id""")
    return render_template("warehouses.html", rows=rows)


@app.route("/inventory", methods=["GET", "POST"])
@allow("admin", "warehouse")
def inventory():
    if request.method == "POST":
        if g.role != "warehouse" and g.role != "admin":
            abort(403)
        try:
            db.execute("CALL set_stock(%s,%s,%s)",
                       (intval("product_id"), intval("warehouse_id"), intval("quantity")))
            flash("Stock updated.", "ok")
        except DBError as e:
            flash(str(e), "error")
        return redirect(url_for("inventory", **{k: v for k, v in request.args.items()}))
    wh = request.args.get("warehouse", "")
    sql = """SELECT i.inventory_id, i.product_id, p.product_name, w.warehouse_id, w.warehouse_name,
                    i.quantity_available, i.quantity_reserved, i.last_updated, p.reorder_level
             FROM inventory i JOIN product p USING (product_id) JOIN warehouse w USING (warehouse_id)"""
    params = []
    if wh:
        sql += " WHERE w.warehouse_id = %s"
        params.append(int(wh))
    rows = db.q(sql + " ORDER BY p.product_id, w.warehouse_id", params)
    whs = db.q("SELECT warehouse_id, warehouse_name FROM warehouse ORDER BY 1")
    prods = db.q("SELECT product_id, product_name FROM product ORDER BY product_name")
    low = db.q("SELECT * FROM v_low_stock ORDER BY product_id")
    return render_template("inventory.html", rows=rows, whs=whs, prods=prods, low=low, wh=wh)


# ----- orders ------------------------------------------------------------------------------------------
@app.route("/orders")
@allow("admin", "customer", "warehouse")
def orders():
    status = request.args.get("status", "")
    sql, params = "SELECT * FROM v_order_summary WHERE TRUE", []
    if g.role == "customer":
        sql += " AND customer_id = %s"
        params.append(g.customer_id)
    if g.role == "warehouse" and not status:
        sql += " AND order_status IN ('CONFIRMED','SHIPPED')"
    if status:
        sql += " AND order_status = %s"
        params.append(status)
    rows = db.q(sql + " ORDER BY order_id DESC", params)
    return render_template("orders.html", rows=rows, status=status)


@app.route("/orders/new", methods=["GET", "POST"])
@allow("admin", "customer")
def new_order():
    prods = db.q("""SELECT p.product_id, p.product_name, p.unit_price, v.total_available
                    FROM product p JOIN v_stock_overview v USING (product_id) ORDER BY p.product_name""")
    custs = db.q("SELECT customer_id, name FROM customer WHERE status='ACTIVE' ORDER BY name") \
        if g.role == "admin" else []
    if request.method == "POST":
        cust = g.customer_id if g.role == "customer" else intval("customer_id")
        items = {}
        for pid, qty in zip(request.form.getlist("product_id"), request.form.getlist("quantity")):
            if pid and qty and int(qty) > 0:
                items[int(pid)] = items.get(int(pid), 0) + int(qty)
        if not items:
            flash("Add at least one product with a quantity.", "error")
        else:
            payload = json.dumps([{"product_id": p, "quantity": n} for p, n in items.items()])
            try:
                res = db.execute("CALL place_order(%s, %s::jsonb, NULL)", (cust, payload))
                flash(f"Order #{res['p_order_id']} placed. Stock reserved - now choose a payment method.", "ok")
                return redirect(url_for("order_detail", oid=res["p_order_id"]))
            except DBError as e:
                flash(f"Order rejected and rolled back: {e}", "error")
    pre = request.args.get("product", type=int)
    return render_template("order_new.html", prods=prods, custs=custs, pre=pre)


def _order_or_404(oid):
    o = db.one("SELECT * FROM v_order_summary WHERE order_id=%s", (oid,))
    if not o or (g.role == "customer" and o["customer_id"] != g.customer_id):
        abort(404)
    return o


@app.route("/orders/<int:oid>")
@allow("admin", "customer", "warehouse")
def order_detail(oid):
    o = _order_or_404(oid)
    items = db.q("SELECT * FROM v_order_detail WHERE order_id=%s ORDER BY order_item_id", (oid,))
    return render_template("order_detail.html", o=o, items=items)


@app.post("/orders/<int:oid>/<action>")
@allow("admin", "customer", "warehouse")
def order_action(oid, action):
    _order_or_404(oid)
    try:
        if action == "pay" and g.role in ("admin", "customer"):
            res = db.execute("CALL record_payment(%s,%s,%s,NULL)",
                             (oid, request.form["method"], request.form.get("success") == "on"))
            msg = {"SUCCESS": "Payment successful - order CONFIRMED.",
                   "PENDING": "Cash on delivery chosen - order CONFIRMED, payment due on delivery.",
                   "FAILED": "Payment FAILED (simulated). Stock is still held; you can retry or cancel."}
            flash(msg[res["p_result"]], "error" if res["p_result"] == "FAILED" else "ok")
        elif action == "cancel" and g.role in ("admin", "customer"):
            db.execute("CALL cancel_order(%s)", (oid,))
            flash("Order cancelled and stock restored.", "ok")
        elif action in ("ship", "deliver") and g.role in ("admin", "warehouse"):
            db.execute("CALL update_order_status(%s,%s)", (oid, "SHIPPED" if action == "ship" else "DELIVERED"))
            flash("Order marked " + ("SHIPPED - reserved stock released." if action == "ship" else "DELIVERED."), "ok")
        else:
            abort(403)
    except DBError as e:
        flash(str(e), "error")
    return redirect(request.form.get("next") or url_for("order_detail", oid=oid))


# ----- purchase orders ------------------------------------------------------------------------------------
@app.route("/purchase-orders")
@allow("admin", "warehouse", "procurement")
def purchase_orders():
    status = request.args.get("status", "")
    sql = """SELECT po.*, p.product_name, s.supplier_name, w.warehouse_name,
                    CASE WHEN po.po_status='CREATED' AND po.expected_delivery < CURRENT_DATE THEN TRUE ELSE FALSE END AS overdue
             FROM purchase_order po JOIN product p USING (product_id)
             JOIN supplier s ON s.supplier_id = po.supplier_id
             JOIN warehouse w ON w.warehouse_id = po.warehouse_id WHERE TRUE"""
    params = []
    if status:
        sql += " AND po.po_status=%s"
        params.append(status)
    rows = db.q(sql + " ORDER BY (po.po_status='CREATED') DESC, po.po_id DESC", params)
    low = db.q("SELECT * FROM v_low_stock ORDER BY product_id")
    return render_template("purchase_orders.html", rows=rows, low=low, status=status)


@app.post("/purchase-orders/<int:po_id>/<action>")
@allow("admin", "warehouse", "procurement")
def po_action(po_id, action):
    try:
        if action == "receive" and g.role in ("admin", "warehouse"):
            db.execute("CALL receive_purchase_order(%s)", (po_id,))
            flash(f"PO #{po_id} received - stock added to the warehouse.", "ok")
        elif action == "cancel" and g.role in ("admin", "procurement"):
            db.execute("CALL cancel_purchase_order(%s)", (po_id,))
            flash(f"PO #{po_id} cancelled.", "ok")
        else:
            abort(403)
    except DBError as e:
        flash(str(e), "error")
    return redirect(url_for("purchase_orders"))


@app.post("/purchase-orders/check")
@allow("admin", "procurement")
def po_check():
    try:
        res = db.execute("CALL check_reorder_levels(0)")
        n = res["p_created"]
        flash(f"Reorder check finished: {n} purchase order(s) created." if n
              else "Reorder check finished: nothing new needed.", "ok")
    except DBError as e:
        flash(str(e), "error")
    return redirect(url_for("purchase_orders"))


@app.route("/purchase-orders/new", methods=["GET", "POST"])
@allow("admin", "procurement")
def po_new():
    prods = db.q("SELECT product_id, product_name FROM product ORDER BY product_name")
    whs = db.q("SELECT warehouse_id, warehouse_name FROM warehouse ORDER BY 1")
    if request.method == "POST":
        try:
            res = db.execute("CALL create_purchase_order(%s,%s,%s,NULL)",
                             (intval("product_id"), intval("warehouse_id"), intval("quantity")))
            flash(f"Purchase order #{res['p_po_id']} created.", "ok")
            return redirect(url_for("purchase_orders"))
        except DBError as e:
            flash(str(e), "error")
    return render_template("po_new.html", prods=prods, whs=whs)


# ----- reports ---------------------------------------------------------------------------------------------------
@app.route("/reports")
@allow("admin", "procurement")
def reports():
    data = {"low": db.q("SELECT * FROM v_low_stock ORDER BY product_id"),
            "suppliers": db.q("SELECT * FROM v_supplier_performance ORDER BY on_time_pct DESC NULLS LAST")}
    if g.role == "admin":
        data.update(
            monthly=db.q("SELECT * FROM v_monthly_revenue ORDER BY month"),
            top=db.q("SELECT * FROM v_sales_by_product ORDER BY units_sold DESC, revenue DESC LIMIT 5"),
            by_product=db.q("SELECT * FROM v_sales_by_product ORDER BY revenue DESC"),
            by_customer=db.q("SELECT * FROM v_sales_by_customer ORDER BY total_spent DESC"),
            status=db.q("""SELECT order_status, COUNT(*) AS orders, ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
                           FROM orders GROUP BY order_status ORDER BY orders DESC"""),
            by_wh=db.q("""SELECT w.warehouse_name, w.capacity, get_warehouse_load(w.warehouse_id) AS load
                          FROM warehouse w ORDER BY 1"""))
    return render_template("reports.html", d=data)


if __name__ == "__main__":
    app.run(debug=os.environ.get("FLASK_DEBUG") == "1", port=int(os.environ.get("PORT", 5000)))
