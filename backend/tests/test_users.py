"""
Tests for user endpoints:
  GET /api/users          (auth required)
  GET /api/users/{id}     (auth required)
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


def _register_and_login(client, user: dict) -> str:
    """Helper: register a user and return its JWT."""
    client.post("/api/auth/register", json=user)
    resp = client.post("/api/auth/login", json={
        "email": user["email"],
        "password": user["password"],
    })
    return resp.json()["access_token"]


# ── GET /api/users ────────────────────────────────────────────────────────────

def test_get_users_without_token_rejected(client):
    response = client.get("/api/users")
    assert response.status_code == 403  # HTTPBearer returns 403 when no credentials


def test_get_users_with_invalid_token_rejected(client):
    response = client.get(
        "/api/users",
        headers={"Authorization": "Bearer this.is.not.valid"},
    )
    assert response.status_code == 401


def test_get_users_with_valid_token(client):
    token = _register_and_login(client, USER_A)
    response = client.get(
        "/api/users",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "users" in data
    assert data["total"] >= 1
    # Confirm password_hash is never returned
    for user in data["users"]:
        assert "password_hash" not in user
        assert "password" not in user


def test_get_users_returns_multiple(client):
    token = _register_and_login(client, USER_A)
    client.post("/api/auth/register", json=USER_B)

    response = client.get(
        "/api/users",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 2
    names = [u["name"] for u in data["users"]]
    assert "Arun Kumar" in names
    assert "Bala Murugan" in names


# ── GET /api/users/{id} ───────────────────────────────────────────────────────

def test_get_user_by_id(client):
    token = _register_and_login(client, USER_A)
    # Fetch user list to get ID
    users_resp = client.get(
        "/api/users",
        headers={"Authorization": f"Bearer {token}"},
    )
    user_id = users_resp.json()["users"][0]["id"]

    response = client.get(
        f"/api/users/{user_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == user_id
    assert "password_hash" not in data


def test_get_user_not_found(client):
    token = _register_and_login(client, USER_A)
    response = client.get(
        "/api/users/99999",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 404
