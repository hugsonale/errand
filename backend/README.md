# Errand Marketplace — Backend API

## Phase 1: Foundation — Auth, Users & Agent Verification

---

## Prerequisites

Install these before starting:

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | Latest | https://docs.docker.com/get-docker/ |
| Python | 3.11+ | https://python.org |
| Poetry | 1.8+ | `pip install poetry` |
| Git | Any | https://git-scm.com |

---

## Quick Start (Docker — Recommended)

### 1. Clone and enter the project

```bash
git clone <your-repo-url> errand-marketplace
cd errand-marketplace
```

### 2. Create your environment file

```bash
cp backend/.env.example backend/.env
```

Open `backend/.env` and set at minimum:
- `SECRET_KEY` — any random 32+ character string
- Leave AWS, Termii, and Paystack keys empty for now (dev mode handles this)

### 3. Start everything

```bash
docker-compose up --build
```

This will:
- Start PostgreSQL on port 5432
- Start Redis on port 6379
- Run Alembic migrations automatically
- Start the FastAPI server on port 8000

### 4. Verify it's running

Open your browser:
- **API Docs (Swagger):** http://localhost:8000/docs
- **Health Check:** http://localhost:8000/health

---

## Running Without Docker (Local Python)

### 1. Install dependencies

```bash
cd backend
poetry install
```

### 2. Start PostgreSQL and Redis locally

```bash
# If you have Docker but want to run backend locally:
docker-compose up postgres redis -d
```

### 3. Copy and configure .env

```bash
cp .env.example .env
# Edit .env — DATABASE_URL should point to localhost:5432
```

### 4. Run migrations

```bash
cd backend
poetry run alembic upgrade head
```

### 5. Start the server

```bash
poetry run uvicorn app.main:app --reload --port 8000
```

---

## Running Tests

```bash
cd backend

# Install test dependencies (included in poetry)
poetry install

# Run all tests
poetry run pytest tests/ -v

# Run with coverage report
poetry run pytest tests/ -v --cov=app --cov-report=term-missing
```

---

## API Overview

All endpoints are prefixed with `/api/v1/`

### Authentication
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/auth/register` | Register new user | No |
| POST | `/auth/verify-phone` | Verify OTP → get tokens | No |
| POST | `/auth/resend-otp` | Resend OTP | No |
| POST | `/auth/login` | Login → get tokens | No |
| POST | `/auth/refresh` | Refresh access token | No |
| POST | `/auth/logout` | Revoke refresh token | Yes |

### Users
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET | `/users/me` | Get my profile | Yes |
| PATCH | `/users/me` | Update my profile | Yes |
| POST | `/users/me/avatar` | Upload avatar | Yes |

### Agents
| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/agents/verify/submit` | Submit KYC documents | Agent |
| GET | `/agents/verify/status` | Check KYC status | Agent |
| GET | `/agents/me/profile` | My agent profile | Agent |
| PATCH | `/agents/me/profile` | Update bio/skills | Agent |
| GET | `/agents/{id}/profile` | Public agent profile | Any |
| PATCH | `/agents/location` | Update live location | Agent |
| PATCH | `/agents/availability` | Toggle online/offline | Agent |
| GET | `/agents/admin/verifications` | List pending KYC | Admin |
| POST | `/agents/admin/verifications/{id}/review` | Approve/reject KYC | Admin |

---

## Development Notes

### OTP in Development
When `TERMII_API_KEY` is empty, OTPs are printed to the terminal:
```
[DEV OTP] Phone: +2348012345678 | Code: 483920
```
Copy this code and use it in the verify-phone endpoint.

### S3 in Development
When `AWS_ACCESS_KEY_ID` is empty, file uploads are simulated:
```
[DEV S3] Would upload to s3://errand-marketplace-media/kyc/...
```
A placeholder key is returned — KYC flows work end-to-end without real AWS.

### Making Yourself an Admin
After registering and verifying your account, run this SQL:
```sql
UPDATE users SET role = 'admin' WHERE phone = '+2348012345678';
```

---

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI app, middleware, routers
│   ├── config.py            # Settings from .env
│   ├── database.py          # Async SQLAlchemy engine + session
│   ├── models/              # ORM models (User, AgentProfile, etc.)
│   ├── schemas/             # Pydantic request/response models
│   ├── routers/             # API route handlers
│   ├── services/            # Business logic layer
│   ├── core/                # Auth, security, dependencies, exceptions
│   └── utils/               # Helper functions
├── alembic/                 # Database migrations
├── tests/                   # Pytest test suite
├── Dockerfile
├── pyproject.toml
└── .env.example
```

---

## Phase 2 Preview

Next phase adds:
- Task posting and lifecycle (Posted → Accepted → In Progress → Completed)
- Agent nearby task browsing with geo filtering
- Client agent selection and task tracking
- Google Maps integration
- Flutter app Phase 1 screens

Run `docker-compose up` and start exploring the Swagger docs at `/docs`.
Everything is ready for Phase 2.
