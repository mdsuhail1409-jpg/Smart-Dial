# SmartDial Backend

FastAPI backend for the Smart Reciprocal Call Coordination System.

## Requirements

- Python 3.11+
- PostgreSQL (or Supabase-hosted PostgreSQL)

## Setup

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Configure environment
cp .env.example .env
# Edit .env with your DATABASE_URL and JWT_SECRET_KEY

# 3. Run Alembic migrations
alembic upgrade head

# 4. Start the development server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | No | Health check |
| POST | /api/auth/register | No | Register new user |
| POST | /api/auth/login | No | Login + receive JWT |
| GET | /api/users | Bearer JWT | List all users |
| GET | /api/users/{id} | Bearer JWT | Get user by ID |

## Running Tests

```bash
python -m pytest tests/ -v
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET_KEY` | Secret key for JWT signing (min 32 chars) |
| `JWT_ALGORITHM` | JWT algorithm (default: HS256) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token TTL in minutes (default: 60) |

## Security Notes

- Passwords are hashed with bcrypt — plaintext is never stored or returned.
- JWT identity is taken from the verified token payload only — never from client-supplied values.
- `password_hash` is excluded from all API responses.
