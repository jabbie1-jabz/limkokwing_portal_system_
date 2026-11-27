import hmac
import hashlib
import os
import re
import secrets
import sqlite3
from functools import wraps
from datetime import datetime
from flask import Flask, jsonify, render_template, request, redirect, url_for, session, flash, g
from werkzeug.security import generate_password_hash, check_password_hash

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DATABASE = os.environ.get("DATABASE_PATH", os.path.join(BASE_DIR, "public_service_portal.db"))


def required_environment_variable(name, minimum_length=1):
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise RuntimeError(f"Set the {name} environment variable before starting the application.")
    if len(value) < minimum_length:
        raise RuntimeError(f"{name} must be at least {minimum_length} characters.")
    return value


ADMIN_EMAIL = required_environment_variable("ADMIN_EMAIL").strip().lower()
ADMIN_PASSWORD = required_environment_variable("ADMIN_PASSWORD", minimum_length=9)
CAMPUS_ID = required_environment_variable("CAMPUS_ID")
CAMPUS_CODE = required_environment_variable("CAMPUS_CODE")
STUDENT_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{4,20}$")
APP_NAME = "Limkokwing Campus Portal"
REQUEST_CATEGORIES = [
    "IT & Digital Services",
    "Housing & Utilities",
    "Transportation",
    "Health & Wellness",
    "Education & Training",
    "Finance & Billing",
    "Safety & Community",
    "Other",
]
SERVICE_TYPES = [
    "Technical issue",
    "Account or login problem",
    "Service request",
    "Complaint or feedback",
    "Maintenance or repair request",
    "Information or guidance needed",
    "Billing or payment issue",
    "Safety or community concern",
    "Other request",
]
REQUEST_STATUSES = ["Pending", "In Progress", "Approved", "Resolved"]
REQUEST_PRIORITIES = ["Low", "Normal", "High"]
MOBILE_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 7
app = Flask(__name__)
app.config["SECRET_KEY"] = required_environment_variable("SECRET_KEY", minimum_length=32)
app.config["APP_NAME"] = APP_NAME


def normalize_student_id(student_id):
    value = (student_id or "").strip()
    if not value:
        return ""
    clean = re.sub(r"\s+", "", value)
    if STUDENT_ID_PATTERN.fullmatch(clean):
        return clean.upper()
    return ""


def get_csrf_token():
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return session["csrf_token"]


def valid_campus_credentials(campus_id, campus_code):
    return (campus_id or "").strip() == CAMPUS_ID and (campus_code or "").strip() == CAMPUS_CODE


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DATABASE)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


@app.teardown_appcontext
def close_db(_error=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    db = sqlite3.connect(DATABASE)
    db.execute("PRAGMA foreign_keys = ON")
    db.executescript("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        full_name TEXT NOT NULL,
        student_id TEXT UNIQUE,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'user' CHECK(role IN ('user','admin')),
        identity_status TEXT NOT NULL DEFAULT 'pending'
          CHECK(identity_status IN ('pending','verified')),
        created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_code TEXT UNIQUE NOT NULL,
        user_id INTEGER NOT NULL,
        category TEXT NOT NULL,
        service_type TEXT NOT NULL,
        description TEXT NOT NULL,
        priority TEXT NOT NULL DEFAULT 'Normal',
        status TEXT NOT NULL DEFAULT 'Pending'
          CHECK(status IN ('Pending','In Progress','Approved','Resolved')),
        payment_amount REAL,
        payment_currency TEXT,
        payment_date TEXT,
        payment_method TEXT,
        payment_reference TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
    );
    CREATE TABLE IF NOT EXISTS request_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL,
        author_id INTEGER NOT NULL,
        note TEXT NOT NULL,
        is_internal INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(request_id) REFERENCES requests(id) ON DELETE CASCADE,
        FOREIGN KEY(author_id) REFERENCES users(id)
    );
    CREATE TABLE IF NOT EXISTS mobile_tokens (
        token_hash TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
    """)
    user_columns = {row[1] for row in db.execute("PRAGMA table_info(users)")}
    if "identity_status" not in user_columns:
        db.execute(
            "ALTER TABLE users ADD COLUMN identity_status TEXT NOT NULL DEFAULT 'pending'"
        )
    # Ensure the seeded administrator exists and uses the expected credentials.
    admin_user = db.execute(
        "SELECT id FROM users WHERE role='admin' OR email=? LIMIT 1",
        (ADMIN_EMAIL,)
    ).fetchone()
    admin_values = (
        "Campus Administrator",
        None,
        ADMIN_EMAIL,
        generate_password_hash(ADMIN_PASSWORD),
        "admin",
        "verified",
        datetime.now().isoformat(timespec="seconds"),
    )
    if admin_user:
        admin_id = admin_user[0]
        db.execute(
            "UPDATE users SET full_name=?, student_id=?, email=?, password_hash=?, role=?, identity_status=?, created_at=? WHERE id=?",
            (*admin_values, admin_id)
        )
    else:
        db.execute(
            "INSERT INTO users(full_name, student_id, email, password_hash, role, identity_status, created_at) VALUES(?,?,?,?,?,?,?)",
            admin_values
        )
    db.commit()
    db.close()


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if (not session.get("user_id") or not session.get("campus_verified")
                or (session.get("role") != "admin" and not session.get("identity_verified"))):
            session.clear()
            flash("Please sign in with a verified campus account.", "warning")
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if (not session.get("user_id") or not session.get("campus_verified")
                or (session.get("role") != "admin" and not session.get("identity_verified"))):
            session.clear()
            return redirect(url_for("login"))
        if session.get("role") != "admin":
            flash("Administrator access is required.", "danger")
            return redirect(url_for("dashboard"))
        return view(*args, **kwargs)
    return wrapped


def ticket_code(ticket_id):
    return f"CSR-{ticket_id:05d}"


@app.route("/")
def index():
    if session.get("user_id"):
        return redirect(url_for("admin_dashboard" if session.get("role") == "admin" else "dashboard"))
    return render_template("landing.html")


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        full_name = request.form.get("full_name", "").strip()
        campus_id = request.form.get("campus_id", "")
        campus_code = request.form.get("campus_code", "")
        student_id = request.form.get("student_id", "")
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        normalized_student_id = normalize_student_id(student_id)
        if not valid_campus_credentials(campus_id, campus_code):
            flash("Enter the correct campus ID and campus code to register.", "danger")
            return render_template("register.html")
        if not all([full_name, normalized_student_id, email, password]):
            flash("Enter your full name, a valid student ID, email, and password.", "danger")
            return render_template("register.html")
        if len(password) < 8:
            flash("Password must contain at least 8 characters.", "danger")
            return render_template("register.html")
        db = get_db()
        try:
            db.execute(
                "INSERT INTO users(full_name,student_id,email,password_hash,role,identity_status,created_at) VALUES(?,?,?,?,?,'pending',?)",
                (full_name, normalized_student_id, email, generate_password_hash(password), "user",
                 datetime.now().isoformat(timespec="seconds"))
            )
            db.commit()
        except sqlite3.IntegrityError:
            flash("That email or student ID is already registered.", "danger")
            return render_template("register.html")
        flash("Campus account created. A campus administrator must verify your student ID before you can sign in.", "success")
        return redirect(url_for("login"))
    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        campus_id = request.form.get("campus_id", "")
        campus_code = request.form.get("campus_code", "")
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        user = get_db().execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
        is_admin = user is not None and user["role"] == "admin"
        if not is_admin and not valid_campus_credentials(campus_id, campus_code):
            flash("Incorrect campus ID or campus code.", "danger")
            return render_template("login.html")
        if not user or not check_password_hash(user["password_hash"], password):
            flash("Incorrect email or password.", "danger")
            return render_template("login.html")
        if user["role"] != "admin" and user["identity_status"] != "verified":
            flash("Your student ID is awaiting verification by a campus administrator.", "warning")
            return render_template("login.html")
        session.clear()
        session["user_id"] = user["id"]
        session["name"] = user["full_name"]
        session["role"] = user["role"]
        session["campus_verified"] = True
        session["identity_verified"] = user["role"] == "admin" or user["identity_status"] == "verified"
        return redirect(url_for("admin_dashboard" if user["role"] == "admin" else "dashboard"))
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("You have signed out.", "success")
    return redirect(url_for("login"))


@app.route("/dashboard")
@login_required
def dashboard():
    db = get_db()
    rows = db.execute(
        "SELECT * FROM requests WHERE user_id=? ORDER BY id DESC", (session["user_id"],)
    ).fetchall()
    return render_template("dashboard.html", requests=rows)


@app.route("/requests/new", methods=["GET", "POST"])
@login_required
def new_request():
    if request.method == "POST":
        category = request.form.get("category", "")
        service_type = request.form.get("service_type", "").strip()
        description = request.form.get("description", "").strip()
        priority = request.form.get("priority", "Normal")
        allowed_priorities = set(REQUEST_PRIORITIES)
        if category not in REQUEST_CATEGORIES or service_type not in SERVICE_TYPES or not description:
            flash("Please select a valid category, request type, and describe the issue clearly.", "danger")
            return render_template("new_request.html", categories=REQUEST_CATEGORIES, service_types=SERVICE_TYPES)
        if priority not in allowed_priorities:
            priority = "Normal"
        now = datetime.now().isoformat(timespec="seconds")
        db = get_db()
        cur = db.execute("""
          INSERT INTO requests(ticket_code,user_id,category,service_type,description,priority,status,
            payment_amount,payment_currency,payment_date,payment_method,payment_reference,created_at,updated_at)
          VALUES('TEMP',?,?,?,?,?,'Pending',NULL,NULL,NULL,NULL,NULL,?,?)
        """, (session["user_id"], category, service_type, description, priority, now, now))
        rid = cur.lastrowid
        code = ticket_code(rid)
        db.execute("UPDATE requests SET ticket_code=? WHERE id=?", (code, rid))
        db.commit()
        flash(f"Request submitted successfully. Your ticket is {code}.", "success")
        return redirect(url_for("dashboard"))
    return render_template("new_request.html", categories=REQUEST_CATEGORIES, service_types=SERVICE_TYPES)


@app.route("/requests/<int:request_id>")
@login_required
def request_detail(request_id):
    db = get_db()
    item = db.execute("""
        SELECT r.*, u.full_name, u.student_id, u.email
        FROM requests r JOIN users u ON u.id=r.user_id WHERE r.id=?
    """, (request_id,)).fetchone()
    if not item:
        flash("Request not found.", "danger")
        return redirect(url_for("admin_dashboard" if session.get("role") == "admin" else "dashboard"))
    if session.get("role") != "admin" and item["user_id"] != session["user_id"]:
        flash("You can only view your own requests.", "danger")
        return redirect(url_for("dashboard"))
    notes_query = "SELECT n.*, u.full_name FROM request_notes n JOIN users u ON u.id=n.author_id WHERE n.request_id=?"
    if session.get("role") != "admin":
        notes_query += " AND n.is_internal=0"
    notes = db.execute(notes_query + " ORDER BY n.id DESC", (request_id,)).fetchall()
    return render_template("request_detail.html", item=item, notes=notes)


@app.route("/admin")
@admin_required
def admin_dashboard():
    db = get_db()
    filters = []
    values = []
    status = request.args.get("status", "")
    category = request.args.get("category", "")
    search = request.args.get("q", "").strip()
    if status in REQUEST_STATUSES:
        filters.append("r.status=?"); values.append(status)
    if category:
        filters.append("r.category=?"); values.append(category)
    if search:
        filters.append("(r.ticket_code LIKE ? OR u.full_name LIKE ? OR u.student_id LIKE ? OR u.email LIKE ?)")
        values.extend([f"%{search}%"] * 4)
    where = ("WHERE " + " AND ".join(filters)) if filters else ""
    rows = db.execute(f"""
      SELECT r.*, u.full_name, u.student_id, u.email
      FROM requests r JOIN users u ON u.id=r.user_id
      {where} ORDER BY r.id DESC
    """, values).fetchall()
    stats = {}
    for s in REQUEST_STATUSES:
        stats[s] = db.execute("SELECT COUNT(*) FROM requests WHERE status=?", (s,)).fetchone()[0]
    stats["Total"] = db.execute("SELECT COUNT(*) FROM requests").fetchone()[0]
    stats["Finance"] = db.execute("SELECT COUNT(*) FROM requests WHERE category='Finance & Billing'").fetchone()[0]
    return render_template("admin.html", requests=rows, stats=stats, categories=REQUEST_CATEGORIES,
                           selected_status=status, selected_category=category, q=search)


@app.route("/admin/requests/<int:request_id>/update", methods=["POST"])
@admin_required
def update_request(request_id):
    status = request.form.get("status", "")
    priority = request.form.get("priority", "Normal")
    note = request.form.get("note", "").strip()
    is_internal = 1 if request.form.get("is_internal") == "on" else 0
    if status not in REQUEST_STATUSES:
        flash("Invalid status.", "danger")
        return redirect(url_for("request_detail", request_id=request_id))
    if priority not in REQUEST_PRIORITIES:
        priority = "Normal"
    db = get_db()
    exists = db.execute("SELECT id FROM requests WHERE id=?", (request_id,)).fetchone()
    if not exists:
        flash("Request not found.", "danger")
        return redirect(url_for("admin_dashboard"))
    now = datetime.now().isoformat(timespec="seconds")
    db.execute("UPDATE requests SET status=?,priority=?,updated_at=? WHERE id=?",
               (status, priority, now, request_id))
    if note:
        db.execute("INSERT INTO request_notes(request_id,author_id,note,is_internal,created_at) VALUES(?,?,?,?,?)",
                   (request_id, session["user_id"], note, is_internal, now))
    db.commit()
    flash("Request updated.", "success")
    return redirect(url_for("request_detail", request_id=request_id))


@app.route("/admin/users")
@admin_required
def admin_users():
    users = get_db().execute(
        "SELECT id,full_name,student_id,email,role,identity_status,created_at FROM users ORDER BY id DESC"
    ).fetchall()
    return render_template("users.html", users=users, csrf_token=get_csrf_token())


@app.route("/admin/users/<int:user_id>/verify", methods=["POST"])
@admin_required
def verify_student(user_id):
    submitted_token = request.form.get("csrf_token", "")
    expected_token = session.get("csrf_token", "")
    if not expected_token or not hmac.compare_digest(submitted_token, expected_token):
        flash("Invalid verification request. Reload the users page and try again.", "danger")
        return redirect(url_for("admin_users"))

    db = get_db()
    user = db.execute(
        "SELECT id, role, identity_status FROM users WHERE id=?", (user_id,)
    ).fetchone()
    if not user or user["role"] != "user":
        flash("Campus student account not found.", "danger")
        return redirect(url_for("admin_users"))
    if user["identity_status"] != "pending":
        flash("This student account is already verified.", "info")
        return redirect(url_for("admin_users"))

    db.execute(
        "UPDATE users SET identity_status='verified' WHERE id=? AND role='user' AND identity_status='pending'",
        (user_id,)
    )
    db.commit()
    session["csrf_token"] = secrets.token_urlsafe(32)
    flash("Student identity verified.", "success")
    return redirect(url_for("admin_users"))


def mobile_user_data(user):
    return {
        "id": user["id"],
        "full_name": user["full_name"],
        "student_id": user["student_id"],
        "email": user["email"],
        "role": user["role"],
        "identity_status": user["identity_status"],
    }


def mobile_login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        authorization = request.headers.get("Authorization", "")
        scheme, separator, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not separator or not token.strip():
            return jsonify(error="Please sign in to continue."), 401

        token_hash = hashlib.sha256(token.strip().encode("utf-8")).hexdigest()
        now = int(datetime.now().timestamp())
        user = get_db().execute(
            """SELECT u.id, u.full_name, u.student_id, u.email, u.role,
                      u.identity_status
               FROM mobile_tokens t JOIN users u ON u.id=t.user_id
               WHERE t.token_hash=? AND t.expires_at>?""",
            (token_hash, now),
        ).fetchone()
        if not user:
            return jsonify(error="Your session has expired. Please sign in again."), 401

        g.mobile_user = user
        g.mobile_token_hash = token_hash
        return view(*args, **kwargs)
    return wrapped


def mobile_admin_required(view):
    @wraps(view)
    @mobile_login_required
    def wrapped(*args, **kwargs):
        if g.mobile_user["role"] != "admin":
            return jsonify(error="Administrator access is required."), 403
        return view(*args, **kwargs)
    return wrapped


@app.post("/api/mobile/register")
def mobile_register():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error="Send registration details as JSON."), 400

    full_name = str(data.get("full_name", "")).strip()
    campus_id = str(data.get("campus_id", ""))
    campus_code = str(data.get("campus_code", ""))
    student_id = normalize_student_id(data.get("student_id", ""))
    email = str(data.get("email", "")).strip().lower()
    password = str(data.get("password", ""))
    if not valid_campus_credentials(campus_id, campus_code):
        return jsonify(error="Enter the correct campus ID and campus code."), 400
    if not all([full_name, student_id, email, password]):
        return jsonify(error="Enter your name, valid student ID, email, and password."), 400
    if len(password) < 8:
        return jsonify(error="Password must contain at least 8 characters."), 400

    db = get_db()
    try:
        db.execute(
            """INSERT INTO users(
                full_name,student_id,email,password_hash,role,identity_status,created_at
            ) VALUES(?,?,?,?,?,'pending',?)""",
            (
                full_name, student_id, email, generate_password_hash(password), "user",
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        db.commit()
    except sqlite3.IntegrityError:
        return jsonify(error="That email or student ID is already registered."), 409

    return jsonify(
        message="Account created. A campus administrator must verify your student ID before sign-in.",
    ), 201


@app.post("/api/mobile/login")
def mobile_login():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error="Send sign-in details as JSON."), 400

    email = str(data.get("email", "")).strip().lower()
    password = str(data.get("password", ""))
    user = get_db().execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
    is_admin = user is not None and user["role"] == "admin"
    if not is_admin and not valid_campus_credentials(
        str(data.get("campus_id", "")), str(data.get("campus_code", ""))
    ):
        return jsonify(error="Incorrect campus ID or campus code."), 401
    if not user or not check_password_hash(user["password_hash"], password):
        return jsonify(error="Incorrect email or password."), 401
    if not is_admin and user["identity_status"] != "verified":
        return jsonify(
            error="Your student ID is awaiting verification by a campus administrator.",
            code="identity_pending",
        ), 403

    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    expires_at = int(datetime.now().timestamp()) + MOBILE_TOKEN_TTL_SECONDS
    get_db().execute(
        "INSERT INTO mobile_tokens(token_hash,user_id,expires_at) VALUES(?,?,?)",
        (token_hash, user["id"], expires_at),
    )
    get_db().commit()
    return jsonify(
        token=token,
        expires_at=expires_at,
        user=mobile_user_data(user),
    )


@app.get("/api/mobile/me")
@mobile_login_required
def mobile_me():
    return jsonify(user=mobile_user_data(g.mobile_user))


@app.post("/api/mobile/logout")
@mobile_login_required
def mobile_logout():
    get_db().execute(
        "DELETE FROM mobile_tokens WHERE token_hash=?", (g.mobile_token_hash,)
    )
    get_db().commit()
    return jsonify(message="Signed out.")


@app.get("/api/mobile/requests")
@mobile_login_required
def mobile_requests():
    db = get_db()
    is_admin = g.mobile_user["role"] == "admin"
    if not is_admin:
        rows = db.execute(
            "SELECT * FROM requests WHERE user_id=? ORDER BY id DESC",
            (g.mobile_user["id"],),
        ).fetchall()
    else:
        status = request.args.get("status", "")
        category = request.args.get("category", "")
        search = request.args.get("q", "").strip()
        filters = []
        values = []
        if status in REQUEST_STATUSES:
            filters.append("r.status=?")
            values.append(status)
        if category in REQUEST_CATEGORIES:
            filters.append("r.category=?")
            values.append(category)
        if search:
            filters.append(
                "(r.ticket_code LIKE ? OR u.full_name LIKE ? OR "
                "u.student_id LIKE ? OR u.email LIKE ?)"
            )
            values.extend([f"%{search}%"] * 4)
        where = ("WHERE " + " AND ".join(filters)) if filters else ""
        rows = db.execute(
            f"""SELECT r.*, u.full_name, u.student_id, u.email
                FROM requests r JOIN users u ON u.id=r.user_id
                {where} ORDER BY r.id DESC""",
            values,
        ).fetchall()
    result = [dict(row) for row in rows]
    return jsonify(
        requests=result,
        stats={
            status: sum(1 for row in result if row["status"] == status)
            for status in REQUEST_STATUSES
        },
        total=len(result),
    )


@app.post("/api/mobile/requests")
@mobile_login_required
def mobile_create_request():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error="Send request details as JSON."), 400

    category = str(data.get("category", ""))
    service_type = str(data.get("service_type", "")).strip()
    description = str(data.get("description", "")).strip()
    priority = str(data.get("priority", "Normal"))
    if category not in REQUEST_CATEGORIES or service_type not in SERVICE_TYPES or not description:
        return jsonify(error="Select a valid category and request type, and describe the issue."), 400
    if priority not in REQUEST_PRIORITIES:
        priority = "Normal"

    now = datetime.now().isoformat(timespec="seconds")
    db = get_db()
    cursor = db.execute(
        """INSERT INTO requests(
            ticket_code,user_id,category,service_type,description,priority,status,
            payment_amount,payment_currency,payment_date,payment_method,payment_reference,
            created_at,updated_at
        ) VALUES('TEMP',?,?,?,?,?,'Pending',NULL,NULL,NULL,NULL,NULL,?,?)""",
        (
            g.mobile_user["id"], category, service_type, description,
            priority, now, now,
        ),
    )
    request_id = cursor.lastrowid
    code = ticket_code(request_id)
    db.execute(
        "UPDATE requests SET ticket_code=? WHERE id=?", (code, request_id)
    )
    db.commit()
    return jsonify(id=request_id, ticket_code=code, message="Request submitted."), 201


@app.get("/api/mobile/requests/<int:request_id>")
@mobile_login_required
def mobile_request_detail(request_id):
    db = get_db()
    item = db.execute(
        """SELECT r.*, u.full_name, u.student_id, u.email
           FROM requests r JOIN users u ON u.id=r.user_id WHERE r.id=?""",
        (request_id,),
    ).fetchone()
    if not item:
        return jsonify(error="Request not found."), 404
    is_admin = g.mobile_user["role"] == "admin"
    if not is_admin and item["user_id"] != g.mobile_user["id"]:
        return jsonify(error="You can only view your own requests."), 403

    notes_query = """SELECT n.id, n.note, n.is_internal, n.created_at, u.full_name
                     FROM request_notes n JOIN users u ON u.id=n.author_id
                     WHERE n.request_id=?"""
    if not is_admin:
        notes_query += " AND n.is_internal=0"
    notes = db.execute(
        notes_query + " ORDER BY n.id DESC", (request_id,)
    ).fetchall()
    return jsonify(request=dict(item), notes=[dict(note) for note in notes])


@app.post("/api/mobile/requests/<int:request_id>/update")
@mobile_admin_required
def mobile_update_request(request_id):
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error="Send update details as JSON."), 400
    status = str(data.get("status", ""))
    priority = str(data.get("priority", "Normal"))
    note = str(data.get("note", "")).strip()
    is_internal = data.get("is_internal") is True
    if status not in REQUEST_STATUSES:
        return jsonify(error="Select a valid request status."), 400
    if priority not in REQUEST_PRIORITIES:
        priority = "Normal"

    db = get_db()
    if not db.execute("SELECT id FROM requests WHERE id=?", (request_id,)).fetchone():
        return jsonify(error="Request not found."), 404
    now = datetime.now().isoformat(timespec="seconds")
    db.execute(
        "UPDATE requests SET status=?,priority=?,updated_at=? WHERE id=?",
        (status, priority, now, request_id),
    )
    if note:
        db.execute(
            """INSERT INTO request_notes(
                request_id,author_id,note,is_internal,created_at
            ) VALUES(?,?,?,?,?)""",
            (request_id, g.mobile_user["id"], note, int(is_internal), now),
        )
    db.commit()
    return jsonify(message="Request updated.")


@app.get("/api/mobile/users")
@mobile_admin_required
def mobile_users():
    users = get_db().execute(
        """SELECT id,full_name,student_id,email,role,identity_status,created_at
           FROM users ORDER BY id DESC"""
    ).fetchall()
    return jsonify(users=[dict(user) for user in users])


@app.post("/api/mobile/users/<int:user_id>/verify")
@mobile_admin_required
def mobile_verify_student(user_id):
    db = get_db()
    user = db.execute(
        "SELECT id,role,identity_status FROM users WHERE id=?", (user_id,)
    ).fetchone()
    if not user or user["role"] != "user":
        return jsonify(error="Campus student account not found."), 404
    if user["identity_status"] != "pending":
        return jsonify(error="This student account is already verified."), 409
    db.execute(
        """UPDATE users SET identity_status='verified'
           WHERE id=? AND role='user' AND identity_status='pending'""",
        (user_id,),
    )
    db.commit()
    return jsonify(message="Student identity verified.")


with app.app_context():
    init_db()


if __name__ == "__main__":
    app.run(debug=False, host="0.0.0.0", port=int(os.environ.get("PORT", 5000)))
