@echo off
REM Windows setup. Needs PostgreSQL's bin folder on PATH.  Usage: setup.bat postgres
set DBUSER=%1
if "%DBUSER%"=="" set DBUSER=postgres
cd /d "%~dp0sql"
psql -U %DBUSER% -d postgres -c "DROP DATABASE IF EXISTS smart_ecommerce" -c "CREATE DATABASE smart_ecommerce"
psql -U %DBUSER% -d smart_ecommerce -q -f 00_install_all.sql
cd ..\tests
psql -U %DBUSER% -d smart_ecommerce -q -t -A -f test_core.sql
cd ..\app
pip install -r requirements.txt
echo.
echo Done. Start the app:  set DB_USER=%DBUSER% ^&^& set DB_PASSWORD=your_password ^&^& python app.py
