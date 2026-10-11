"""Thin database layer. Every business rule lives in PostgreSQL (triggers,
procedures, constraints); this module only sends SQL and returns rows."""
import os
import psycopg2
import psycopg2.extras
from flask import g

CONFIG = dict(
    host=os.environ.get("DB_HOST", "localhost"),
    port=os.environ.get("DB_PORT", "5432"),
    dbname=os.environ.get("DB_NAME", "smart_ecommerce"),
    user=os.environ.get("DB_USER", "postgres"),
    password=os.environ.get("DB_PASSWORD", ""),
)
# Run each request under the PostgreSQL role of the logged-in user type, so the
# database itself (GRANT/REVOKE) enforces what that user may do. Set to 0 to disable.
USE_DB_ROLES = os.environ.get("USE_DB_ROLES", "1") == "1"

ROLE_MAP = {
    "admin": "admin_role",
    "customer": "customer_role",
    "warehouse": "warehouse_role",
    "procurement": "procurement_role",
}


class DBError(Exception):
    """A readable message for a database error."""


def friendly(e: psycopg2.Error) -> str:
    diag = getattr(e, "diag", None)
    msg = (diag.message_primary if diag and diag.message_primary else str(e)).strip()
    code = getattr(e, "pgcode", None) or ""
    cname = getattr(diag, "constraint_name", None) if diag else None
    if code == "23505":
        return "Duplicate value: a record with the same unique value already exists."
    if code == "23503":
        return "Operation blocked by a foreign key: related records exist (or the referenced record is missing)."
    if code == "23514" and cname:
        return f"Value rejected by database rule '{cname}'."
    if code == "23502":
        return "A required field was left empty."
    if code == "42501":
        return "Permission denied for this user type."
    if code == "22P02" or code == "22003":
        return "Invalid number or value."
    return msg


def conn():
    if "db" not in g:
        c = psycopg2.connect(**CONFIG)
        c.autocommit = True
        g.db = c
        role = ROLE_MAP.get(g.get("role"))
        if role and USE_DB_ROLES:
            with c.cursor() as cur:
                cur.execute("SET ROLE " + role)
    return g.db


def close(_exc=None):
    c = g.pop("db", None)
    if c is not None:
        c.close()


def _run(sql, params=(), fetch=True):
    try:
        with conn().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall() if fetch and cur.description else []
    except psycopg2.Error as e:
        raise DBError(friendly(e)) from e


def q(sql, params=()):
    """Run a query, return a list of dict rows."""
    return _run(sql, params)


def one(sql, params=()):
    rows = _run(sql, params)
    return rows[0] if rows else None


def execute(sql, params=()):
    """Run INSERT/UPDATE/CALL; return the first returned row (e.g. INOUT result) if any."""
    rows = _run(sql, params)
    return rows[0] if rows else None
