# Phase 3 Integration Guide — Trust + Payments

## What was built in Phase 3

---

## Backend additions

### New models (app/models/payment.py)
- `EscrowTransaction` — tracks every payment from initiation to agent payout
- `Review` — 5-dimension review with weighted score computation
- `Dispute` — dispute lifecycle with admin resolution
- `Notification` — in-app + push notification records

### New services
- `paystack_service.py` — Paystack API: charge, verify, transfer, refund
- `payment_service.py` — Escrow lifecycle: initiate → hold → release → refund
- `review_service.py` — Review submission, trust score algorithm, level-up detection
- `notification_service.py` — DB records + FCM push dispatch
- `fcm_service.py` — Firebase Cloud Messaging HTTP v1 API

### New endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/payments/initiate/{task_id}` | Create Paystack charge, hold escrow |
| POST | `/payments/webhook` | Paystack event receiver (HMAC verified) |
| POST | `/payments/release/{task_id}` | Admin: release escrow to agent |
| POST | `/payments/refund/{task_id}` | Admin: refund to client |
| GET  | `/payments/history` | User payment history |
| POST | `/reviews/` | Submit 5-dimension review |
| GET  | `/reviews/agent/{id}` | Agent reviews with breakdown |
| GET  | `/reviews/trust-score/{id}` | Full trust score breakdown |
| GET  | `/notifications/` | User notifications |
| POST | `/notifications/{id}/read` | Mark notification read |
| POST | `/notifications/read-all` | Mark all read |

---

## Payment flow (complete)

```
1. Client accepts agent application
   → POST /tasks/{id}/accept/{app_id}
   → Task status: ACCEPTED

2. Client initiates payment
   → POST /payments/initiate/{task_id}
   → Returns: { authorization_url, reference, amount }
   → Flutter opens authorization_url in WebView

3. Client completes payment on Paystack
   → Paystack fires webhook: charge.success
   → POST /payments/webhook (HMAC verified)
   → EscrowTransaction.status → HELD
   → Funds locked, neither party can access

4. Agent completes task + submits proof
   → POST /tasks/{id}/complete (multipart, photos)
   → OTP generated, sent to client via SMS/FCM
   → Task status: PROOF_SUBMITTED

5. Client confirms completion (enters OTP or just confirms)
   → POST /tasks/{id}/confirm { otp_code }
   → Task status: COMPLETED
   → payment_service.release_to_agent() called automatically
   → EscrowTransaction.status → RELEASED
   → Agent payout initiated (85% of amount)
   → Notifications fired to both parties

6. Review screen shown to client
   → POST /reviews/ (5-dimension)
   → Agent trust score recomputed with recency decay
   → Level-up check → notification if level changed
```

---

## Trust score algorithm

The trust score uses recency-weighted averaging:

```python
# Most recent review has full weight
# Each older review decays by factor of 0.95
weight = 0.95 ** review_index
weighted_score = sum(review.weighted_score * weight) / sum(weights)
```

Individual weighted_score per review:
```
overall_rating    × 0.30   (most important)
trustworthiness   × 0.25
professionalism   × 0.20
punctuality       × 0.15
communication     × 0.10
```

Trust level thresholds:
| Level    | Tasks | Score |
|----------|-------|-------|
| Bronze   | < 10  | any   |
| Silver   | ≥ 10  | ≥ 3.5 |
| Gold     | ≥ 50  | ≥ 4.2 |
| Platinum | ≥ 100 | ≥ 4.7 |

---

## Paystack setup (production)

1. Create account at paystack.com
2. Add keys to `.env`:
   ```
   PAYSTACK_SECRET_KEY=sk_live_xxxxx
   PAYSTACK_PUBLIC_KEY=pk_live_xxxxx
   PAYSTACK_WEBHOOK_SECRET=your_webhook_secret
   ```
3. In Paystack dashboard → Settings → Webhooks
   → Add URL: `https://yourdomain.com/api/v1/payments/webhook`
4. Test with: `sk_test_xxxxx` keys first

---

## Firebase FCM setup (production)

1. Create Firebase project at console.firebase.google.com
2. Add Android + iOS apps
3. Download service account JSON
4. Set `FIREBASE_CREDENTIALS_PATH=/path/to/firebase-credentials.json`
5. In Flutter: add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)

---

## Flutter Phase 3 screens

New files in `lib/screens/shared/phase3_screens.dart`:
- `WalletScreen` — client payment history + escrow status
- `ReviewScreen` — 5-star 5-dimension review form
- `AgentEarningsScreen` — agent payout history + total earnings
- `NotificationsScreen` — all notification types with icons
- `LevelUpScreen` — animated celebration with benefits list

Add to router.dart (see lib/utils/phase3_routes.dart for route definitions).

Update bottom navigation bars to include Wallet (client) and Earnings (agent) tabs.

---

## Running Phase 3

Same command as before:
```bash
docker-compose up --build
```

Migrations run automatically. New tables:
- `escrow_transactions`
- `reviews`  
- `disputes`
- `notifications`

Test the payment flow in dev mode — Paystack calls print to console instead of hitting the real API. FCM push notifications print to console instead of sending.
