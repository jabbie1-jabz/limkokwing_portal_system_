# Limkokwing Campus Portal

A Flask and SQLite portal for campus service requests, student accounts, and
administration.

## Configuration

Set these environment variables before starting the application:

- `SECRET_KEY`: a private random value of at least 32 characters.
- `ADMIN_EMAIL`: the administrator's sign-in email.
- `ADMIN_PASSWORD`: the administrator's password (at least 9 characters).
- `CAMPUS_ID` and `CAMPUS_CODE`: private values required for student
  registration and sign-in.
- `DATABASE_PATH` (optional): SQLite file path. By default, the database is
  created beside `app.py`.

Copy `.env.example` to `.env` for local reference and fill it with private
values. Do not commit `.env` or paste secrets into source code. The app reads
environment variables; it does not load `.env` automatically. On PythonAnywhere,
set the values in the web app's WSGI configuration before importing the app,
then reload the web app.

## Run locally

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:SECRET_KEY = "replace-with-a-private-random-value-at-least-32-characters"
$env:ADMIN_EMAIL = "admin@example.com"
$env:ADMIN_PASSWORD = "replace-with-a-private-password"
$env:CAMPUS_ID = "set-your-private-campus-id"
$env:CAMPUS_CODE = "set-your-private-campus-code"
python app.py
```

## Android app (Flutter)

The Flutter Android client is in `mobile_app`. Open that folder in Android
Studio, run the Flask server above, and follow `mobile_app/README.md` to connect
an Android phone or emulator.

The university logo is not included in this repository. Add it only if you have
permission to redistribute it, and keep it out of commits unless authorized.
