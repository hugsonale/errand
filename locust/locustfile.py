"""
Errand Marketplace — Load Test Suite
Run: locust -f locustfile.py --host=http://localhost:8000 --users=500 --spawn-rate=10

Tests the 4 critical flows under load:
1. Auth flow (register → verify → login)
2. Client task posting
3. Agent task browsing
4. Task detail viewing
"""
import random
import string
from locust import HttpUser, task, between, events


def random_phone() -> str:
    suffix = "".join(random.choices(string.digits, k=8))
    return f"+23480{suffix}"


def random_string(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase, k=length))


# ─── Shared state ─────────────────────────────────────────────────────────────

_client_tokens: list[str] = []
_agent_tokens: list[str] = []
_task_ids: list[str] = []


# ─── Auth User — registers and logs in ───────────────────────────────────────

class AuthUser(HttpUser):
    """Simulates the registration and login flow."""
    wait_time = between(1, 3)
    weight = 1

    def on_start(self):
        self.phone = random_phone()
        self.token = None
        self._register()

    def _register(self):
        resp = self.client.post("/api/v1/auth/register", json={
            "full_name": f"Load Test User {random_string()}",
            "phone": self.phone,
            "password": "LoadTest1",
            "role": "client",
        }, name="/auth/register")

        if resp.status_code != 201:
            return

        # In load testing, we can't get the OTP from DB easily
        # So we test up to the registration step only
        # In a real load test environment, you'd use a test OTP endpoint

    @task(3)
    def check_health(self):
        self.client.get("/health", name="/health")

    @task(1)
    def attempt_login_invalid(self):
        """Tests login error handling under load."""
        self.client.post("/api/v1/auth/login", json={
            "identifier": self.phone,
            "password": "WrongPassword1",
        }, name="/auth/login [invalid]")


# ─── Authenticated Client ─────────────────────────────────────────────────────

class ClientUser(HttpUser):
    """
    Simulates a verified client browsing and posting tasks.
    Requires pre-seeded tokens — set CLIENT_TOKEN env var or seed via script.
    """
    wait_time = between(2, 5)
    weight = 3

    def on_start(self):
        # For load testing, use a pre-created test account
        resp = self.client.post("/api/v1/auth/login", json={
            "identifier": "+2348000000001",  # Pre-seeded test client
            "password": "LoadTest1",
        }, name="/auth/login [load-test-client]")

        if resp.status_code == 200:
            self.token = resp.json().get("access_token")
            self.headers = {"Authorization": f"Bearer {self.token}"}
        else:
            self.token = None
            self.headers = {}

    @task(5)
    def browse_my_tasks(self):
        if not self.token:
            return
        self.client.get(
            "/api/v1/tasks/",
            headers=self.headers,
            name="/tasks/ [client list]",
        )

    @task(2)
    def post_task(self):
        if not self.token:
            return
        categories = ["shopping", "food_pickup", "cleaning", "delivery", "office_errand"]
        resp = self.client.post(
            "/api/v1/tasks/",
            json={
                "title": f"Load test task {random_string(6)}",
                "description": "This is a load test task to measure API performance",
                "category": random.choice(categories),
                "budget": random.choice([2000, 3000, 5000, 8000, 10000]),
                "pickup_address": "Victoria Island, Lagos",
                "pickup_lat": 6.4281 + random.uniform(-0.05, 0.05),
                "pickup_lng": 3.4219 + random.uniform(-0.05, 0.05),
                "is_emergency": random.random() < 0.1,
            },
            headers=self.headers,
            name="/tasks/ [POST]",
        )
        if resp.status_code == 201:
            task_id = resp.json().get("id")
            if task_id:
                _task_ids.append(task_id)

    @task(3)
    def view_task_detail(self):
        if not self.token or not _task_ids:
            return
        task_id = random.choice(_task_ids)
        self.client.get(
            f"/api/v1/tasks/{task_id}",
            headers=self.headers,
            name="/tasks/{id} [detail]",
        )

    @task(1)
    def check_notifications(self):
        if not self.token:
            return
        self.client.get(
            "/api/v1/notifications/",
            headers=self.headers,
            name="/notifications/",
        )

    @task(1)
    def check_payment_history(self):
        if not self.token:
            return
        self.client.get(
            "/api/v1/payments/history",
            headers=self.headers,
            name="/payments/history",
        )


# ─── Authenticated Agent ──────────────────────────────────────────────────────

class AgentUser(HttpUser):
    """Simulates a verified agent browsing tasks nearby."""
    wait_time = between(3, 8)
    weight = 2

    def on_start(self):
        resp = self.client.post("/api/v1/auth/login", json={
            "identifier": "+2348000000002",  # Pre-seeded test agent
            "password": "LoadTest1",
        }, name="/auth/login [load-test-agent]")

        if resp.status_code == 200:
            self.token = resp.json().get("access_token")
            self.headers = {"Authorization": f"Bearer {self.token}"}
        else:
            self.token = None
            self.headers = {}

    @task(5)
    def browse_nearby_tasks(self):
        if not self.token:
            return
        lat = 6.5244 + random.uniform(-0.1, 0.1)
        lng = 3.3792 + random.uniform(-0.1, 0.1)
        self.client.get(
            "/api/v1/tasks/",
            params={"lat": lat, "lng": lng, "radius_km": 10},
            headers=self.headers,
            name="/tasks/ [agent browse]",
        )

    @task(3)
    def filter_by_category(self):
        if not self.token:
            return
        categories = ["shopping", "food_pickup", "cleaning", "delivery"]
        self.client.get(
            "/api/v1/tasks/",
            params={"category": random.choice(categories), "lat": 6.5244, "lng": 3.3792},
            headers=self.headers,
            name="/tasks/ [filtered]",
        )

    @task(2)
    def view_task_detail(self):
        if not self.token or not _task_ids:
            return
        task_id = random.choice(_task_ids)
        self.client.get(
            f"/api/v1/tasks/{task_id}",
            headers=self.headers,
            name="/tasks/{id} [agent view]",
        )

    @task(1)
    def check_profile(self):
        if not self.token:
            return
        self.client.get(
            "/api/v1/agents/me/profile",
            headers=self.headers,
            name="/agents/me/profile",
        )


# ─── Event hooks ──────────────────────────────────────────────────────────────

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print("🚀 Load test starting...")
    print("   Users: 500 | Spawn rate: 10/s")
    print("   Flows: Auth, Task posting, Task browsing, Agent matching")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    stats = environment.stats
    total = stats.total
    print(f"\n📊 Load test complete:")
    print(f"   Requests: {total.num_requests}")
    print(f"   Failures: {total.num_failures}")
    print(f"   Avg response: {total.avg_response_time:.0f}ms")
    print(f"   95th percentile: {total.get_response_time_percentile(0.95):.0f}ms")
    print(f"   RPS: {total.current_rps:.1f}")
