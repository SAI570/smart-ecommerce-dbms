-- Run from the sql/ folder:   psql -U postgres -d smart_ecommerce -f 00_install_all.sql
\set ON_ERROR_STOP on
\ir 01_schema.sql
\ir 02_functions.sql
\ir 03_triggers.sql
\ir 04_procedures.sql
\ir 05_seed_data.sql
\ir 06_views_reports.sql
\ir 08_roles_security.sql
