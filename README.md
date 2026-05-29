# Errand Marketplace — Complete Production Guide

## What's built

A full trust-based errand marketplace:
- **FastAPI backend** — 30+ endpoints, WebSocket live tracking, Paystack escrow, FCM push
- **Flutter app** — client + agent in one codebase, role-based routing
- **Admin panel** — React single-file web app for verification, disputes, monitoring
- **Nginx** — SSL termination, rate limiting, WebSocket proxy
- **CI/CD** — GitHub Actions: test → build Docker → deploy via SSH

---

## Quick start (development)

```bash
# 1. Clone and enter
git clone <your-repo> errand-marketplace
cd errand-marketplace

# 2. Configure environment
cp backend/.env.example backend/.env
# Edit backend/.env — SECRET_KEY is required, others optional for dev

# 3. Start everything (postgres + redis + backend + auto-migrations)
docker-compose up --build

# 4. Open API docs
open http://localhost:8000/docs

# 5. Open admin panel
open admin/index.html
# Login with FIRST_ADMIN_EMAIL / FIRST_ADMIN_PASSWORD from .env
```

---

## Environment variables (required for production)

```bash
# Core
SECRET_KEY=<32+ random chars>
APP_ENV=production
DEBUG=false

# Database (AWS RDS endpoint)
DATABASE_URL=postgresql+asyncpg://user:pass@rds-endpoint:5432/errand_marketplace
DATABASE_URL_SYNC=postgresql://user:pass@rds-endpoint:5432/errand_marketplace

# Redis (AWS ElastiCache endpoint)
REDIS_URL=redis://elasticache-endpoint:6379/0

# AWS S3
AWS_ACCESS_KEY_ID=<key>
AWS_SECRET_ACCESS_KEY=<secret>
AWS_REGION=eu-west-1
S3_BUCKET_NAME=errand-marketplace-media

# SMS OTP (Termii)
TERMII_API_KEY=<key>
TERMII_SENDER_ID=ErrandApp

# Paystack
PAYSTACK_SECRET_KEY=sk_live_<key>
PAYSTACK_PUBLIC_KEY=pk_live_<key>
PAYSTACK_WEBHOOK_SECRET=<webhook-secret>

# Firebase FCM
FIREBASE_CREDENTIALS_PATH=/app/firebase-credentials.json

# CORS (your Flutter app's domain/IP)
ALLOWED_ORIGINS=https://errandmarketplace.com,https://admin.errandmarketplace.com
```

---

## Production deployment

### Prerequisites
- AWS account with EC2, RDS, ElastiCache, S3 set up
- Domain pointing to your EC2 server
- GitHub repository with secrets configured

### First-time server setup
```bash
# Run once — creates VPC, EC2, RDS, S3
chmod +x scripts/deploy_aws.sh
./scripts/deploy_aws.sh

# SSH to the new server
ssh -i ~/.ssh/errand-marketplace-key.pem ubuntu@<server-ip>

# Get SSL certificate
sudo certbot certonly --standalone -d api.errandmarketplace.com

# Configure environment
sudo nano /etc/errand/.env
# Fill in all production values

# Start the app
cd /opt/errand-marketplace
docker-compose -f docker-compose.prod.yml up -d

# Check health
curl https://api.errandmarketplace.com/health
```

### GitHub Actions secrets required
```
PROD_HOST         # EC2 public IP
PROD_USER         # ubuntu
PROD_SSH_KEY      # Contents of .pem private key
```

---

## Running tests

```bash
cd backend
poetry install
poetry run pytest tests/ -v --cov=app --cov-report=term-missing

# Individual test files
poetry run pytest tests/test_auth.py -v
poetry run pytest tests/test_tasks.py -v
poetry run pytest tests/test_phase3.py -v
poetry run pytest tests/test_phase4.py -v
```

---

## Load testing

```bash
pip install locust
cd locust
locust -f locustfile.py --host=http://localhost:8000

# Open: http://localhost:8089
# Set users=500, spawn-rate=10, then start
```

---

## WebSocket testing

**Client tracking (browser console):**
```javascript
const token = "your_access_token";
const taskId = "your_task_id";
const ws = new WebSocket(`ws://localhost:8000/api/v1/ws/track/${taskId}?token=${token}`);
ws.onmessage = (e) => console.log(JSON.parse(e.data));
ws.send("ping");
```

**Agent location sender:**
```javascript
const ws = new WebSocket(`ws://localhost:8000/api/v1/ws/location?token=${token}`);
ws.onopen = () => {
  ws.send(JSON.stringify({ task_id: "...", lat: 6.5244, lng: 3.3792 }));
};
```

---

## Project structure

```
errand-marketplace/
├── backend/                    # FastAPI backend
│   ├── app/
│   │   ├── main.py             # App entry with all middleware
│   │   ├── config.py           # Pydantic settings
│   │   ├── database.py         # Async SQLAlchemy
│   │   ├── models/             # ORM models (5 files, 8 tables)
│   │   ├── schemas/            # Pydantic request/response
│   │   ├── routers/            # API endpoints (7 routers)
│   │   ├── services/           # Business logic (9 services)
│   │   ├── core/               # Auth, deps, exceptions
│   │   ├── middleware/         # Rate limiting, security headers, audit
│   │   └── websockets/         # Real-time location tracking
│   ├── alembic/                # DB migrations (3 versions)
│   ├── tests/                  # 35+ tests across 4 files
│   └── Dockerfile
├── flutter/                    # Flutter mobile app
│   └── lib/
│       ├── main.dart
│       ├── constants/          # Design system (colors, typography, theme)
│       ├── models/             # Data models
│       ├── providers/          # Riverpod state management
│       ├── services/           # API + WebSocket clients
│       ├── utils/              # Router with auth guards
│       └── screens/            # 40 screens (client + agent + shared)
├── admin/                      # React admin panel (single HTML file)
├── nginx/                      # Production Nginx config
├── locust/                     # Load test suite
├── scripts/                    # AWS deployment script
├── .github/workflows/          # CI/CD pipeline
├── docker-compose.yml          # Development
└── docker-compose.prod.yml     # Production
```

---

## API endpoint summary

| Category | Count | Key endpoints |
|----------|-------|---------------|
| Auth | 6 | register, verify-phone, login, refresh, logout |
| Users | 3 | me, update, avatar |
| Agents | 9 | kyc-submit, verify-status, location, availability |
| Tasks | 11 | create, list, detail, apply, accept, start, complete, confirm, dispute |
| Payments | 5 | initiate, webhook, release, refund, history |
| Reviews | 3 | submit, agent-reviews, trust-score |
| Notifications | 3 | list, mark-read, mark-all-read |
| WebSockets | 2 | /ws/track/{task_id}, /ws/location |

Total: **42 endpoints + 2 WebSocket channels**

---

## Database tables

| Table | Purpose |
|-------|---------|
| users | All users (client/agent/business/admin) |
| agent_profiles | Agent stats, trust score, availability |
| agent_verifications | KYC documents and review status |
| otp_codes | Phone verification codes |
| refresh_tokens | JWT refresh token store |
| tasks | Task marketplace core |
| task_applications | Agent bids on tasks |
| completion_proofs | Photo/OTP proof records |
| escrow_transactions | Paystack payment lifecycle |
| reviews | 5-dimension trust reviews |
| disputes | Dispute records and resolution |
| notifications | In-app + push notification log |
