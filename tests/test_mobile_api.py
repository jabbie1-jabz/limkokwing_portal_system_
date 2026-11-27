import os
import tempfile
import unittest
from unittest.mock import patch

_database_dir = tempfile.TemporaryDirectory()
_environment = patch.dict(
    os.environ,
    {
        "DATABASE_PATH": os.path.join(_database_dir.name, "portal-tests.db"),
        "SECRET_KEY": "test-secret-key-that-is-at-least-32-characters",
        "ADMIN_EMAIL": "admin@test.local",
        "ADMIN_PASSWORD": "admin-password-123",
        "CAMPUS_ID": "12345",
        "CAMPUS_CODE": "6789",
    },
)
_environment.start()

from app import app, get_db
from werkzeug.security import generate_password_hash


class MobileApiTests(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        _environment.stop()
        _database_dir.cleanup()

    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()
        with app.app_context():
            db = get_db()
            db.execute("DELETE FROM mobile_tokens")
            db.execute("DELETE FROM request_notes")
            db.execute("DELETE FROM requests")
            db.execute("DELETE FROM users WHERE role != 'admin'")
            db.execute(
                """INSERT INTO users(
                    full_name,student_id,email,password_hash,role,identity_status,created_at
                ) VALUES(?,?,?,?,?,?,?)""",
                (
                    "Verified Student", "STU-1001", "student@test.local",
                    generate_password_hash("student-password"), "user", "verified",
                    "2026-01-01T00:00:00",
                ),
            )
            db.execute(
                """INSERT INTO users(
                    full_name,student_id,email,password_hash,role,identity_status,created_at
                ) VALUES(?,?,?,?,?,?,?)""",
                (
                    "Other Student", "STU-1002", "other@test.local",
                    generate_password_hash("other-password"), "user", "verified",
                    "2026-01-01T00:00:00",
                ),
            )
            db.commit()
        self.student_id = self._user_id("student@test.local")
        self.other_student_id = self._user_id("other@test.local")

    def _user_id(self, email):
        with app.app_context():
            return get_db().execute(
                "SELECT id FROM users WHERE email=?", (email,)
            ).fetchone()["id"]

    def _login(self, email, password, campus=True):
        data = {"email": email, "password": password}
        if campus:
            data.update(campus_id="12345", campus_code="6789")
        response = self.client.post("/api/mobile/login", json=data)
        self.assertEqual(response.status_code, 200, response.json)
        return response.json["token"]

    def test_registration_requires_admin_verification(self):
        response = self.client.post(
            "/api/mobile/register",
            json={
                "full_name": "New Student",
                "campus_id": "12345",
                "campus_code": "6789",
                "student_id": "STU-2001",
                "email": "new@test.local",
                "password": "student-password",
            },
        )
        self.assertEqual(response.status_code, 201)

        pending_login = self.client.post(
            "/api/mobile/login",
            json={
                "email": "new@test.local",
                "password": "student-password",
                "campus_id": "12345",
                "campus_code": "6789",
            },
        )
        self.assertEqual(pending_login.status_code, 403)
        self.assertEqual(pending_login.json["code"], "identity_pending")

        admin_token = self._login("admin@test.local", "admin-password-123", campus=False)
        new_user_id = self._user_id("new@test.local")
        verified = self.client.post(
            f"/api/mobile/users/{new_user_id}/verify",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(verified.status_code, 200)

        student_token = self._login("new@test.local", "student-password")
        signed_out = self.client.post(
            "/api/mobile/logout",
            headers={"Authorization": f"Bearer {student_token}"},
        )
        self.assertEqual(signed_out.status_code, 200)
        revoked = self.client.get(
            "/api/mobile/me",
            headers={"Authorization": f"Bearer {student_token}"},
        )
        self.assertEqual(revoked.status_code, 401)

    def test_requests_are_private_and_internal_notes_are_hidden(self):
        student_token = self._login("student@test.local", "student-password")
        student_headers = {"Authorization": f"Bearer {student_token}"}
        created = self.client.post(
            "/api/mobile/requests",
            headers=student_headers,
            json={
                "category": "IT & Digital Services",
                "service_type": "Technical issue",
                "description": "Cannot connect to campus Wi-Fi.",
                "priority": "High",
            },
        )
        self.assertEqual(created.status_code, 201)
        request_id = created.json["id"]

        private_request = self.client.get(
            f"/api/mobile/requests/{request_id}",
            headers={"Authorization": f"Bearer {self._login('other@test.local', 'other-password')}"},
        )
        self.assertEqual(private_request.status_code, 403)

        admin_token = self._login("admin@test.local", "admin-password-123", campus=False)
        admin_headers = {"Authorization": f"Bearer {admin_token}"}
        update_path = f"/api/mobile/requests/{request_id}/update"
        internal_update = self.client.post(
            update_path,
            headers=admin_headers,
            json={
                "status": "In Progress",
                "priority": "Normal",
                "note": "Internal review.",
                "is_internal": True,
            },
        )
        self.assertEqual(internal_update.status_code, 200)
        public_update = self.client.post(
            update_path,
            headers=admin_headers,
            json={
                "status": "In Progress",
                "priority": "Normal",
                "note": "Technician assigned.",
                "is_internal": False,
            },
        )
        self.assertEqual(public_update.status_code, 200)

        details = self.client.get(
            f"/api/mobile/requests/{request_id}", headers=student_headers
        )
        self.assertEqual(details.status_code, 200)
        self.assertEqual(
            [note["note"] for note in details.json["notes"]],
            ["Technician assigned."],
        )
        own_requests = self.client.get(
            "/api/mobile/requests", headers=student_headers
        )
        self.assertEqual(len(own_requests.json["requests"]), 1)

    def test_admin_routes_reject_student_tokens(self):
        student_token = self._login("student@test.local", "student-password")
        response = self.client.get(
            "/api/mobile/users",
            headers={"Authorization": f"Bearer {student_token}"},
        )
        self.assertEqual(response.status_code, 403)
if __name__ == "__main__":
    unittest.main()
