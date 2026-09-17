"""
Tests for authentication endpoints:
  POST /api/auth/register
  POST /api/auth/login
"""

USER_A = {
    "name": "Arun Kumar",
    "email": "arun@example.com",
    "phone": "9000000001",
    "password": "SecurePass1",
}

USER_B = {
    "name": "Bala Murugan",
    "email": "bala@example.com",
    "phone": "9000000002",
    "password": "SecurePass2",
}


# ── Register ─────────────────────────────────────────────────────────────────

def test_register_user_a(client):
    response = client.post("/api/auth/register", json=USER_A)
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == USER_A["email"]
    assert data["name"] == USER_A["name"]
    # password_hash must NEVER appear in any response
    assert "password_hash" not in data
    assert "password" not in data


def test_register_user_b(client):
    response = client.post("/api/auth/register", json=USER_B)
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == USER_B["email"]
    assert "password_hash" not in data


def test_register_duplicate_email(client):
    client.post("/api/auth/register", json=USER_A)
    # Second registration with same email
    duplicate = {**USER_A, "phone": "9000000099"}
    response = client.post("/api/auth/register", json=duplicate)
    assert response.status_code == 409
    assert "email" in response.json()["detail"].lower()


def test_register_duplicate_phone(client):
    client.post("/api/auth/register", json=USER_A)
    # Second registration with same phone
    duplicate = {**USER_A, "email": "other@example.com"}
    response = client.post("/api/auth/register", json=duplicate)
    assert response.status_code == 409
    assert "phone" in response.json()["detail"].lower()


def test_register_missing_field(client):
    response = client.post("/api/auth/register", json={"email": "x@x.com"})
    assert response.status_code == 422


def test_register_invalid_email(client):
    payload = {**USER_A, "email": "not-an-email"}
    response = client.post("/api/auth/register", json=payload)
    assert response.status_code == 422


def test_register_short_password(client):
    payload = {**USER_A, "password": "short"}
    response = client.post("/api/auth/register", json=payload)
    assert response.status_code == 422


# ── Login ─────────────────────────────────────────────────────────────────────

def test_login_success(client):
    client.post("/api/auth/register", json=USER_A)
    response = client.post("/api/auth/login", json={
        "email": USER_A["email"],
        "password": USER_A["password"],
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == USER_A["email"]
    assert "password_hash" not in data["user"]
    assert "password_hash" not in str(data)


def test_login_wrong_password(client):
    client.post("/api/auth/register", json=USER_A)
    response = client.post("/api/auth/login", json={
        "email": USER_A["email"],
        "password": "WrongPassword!",
    })
    assert response.status_code == 401


def test_login_unknown_email(client):
    response = client.post("/api/auth/login", json={
        "email": "nobody@example.com",
        "password": "SomePass123",
    })
    assert response.status_code == 401
