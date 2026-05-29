import json
import httpx
from app.config import settings


class FCMService:
    """
    Firebase Cloud Messaging — sends push notifications to Flutter app.
    Uses FCM HTTP v1 API.
    """

    FCM_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

    async def send_to_token(
        self,
        fcm_token: str,
        title: str,
        body: str,
        data: dict | None = None,
    ) -> bool:
        """
        Sends a push notification to a specific device.
        Returns True on success, False on failure (non-blocking).
        """
        if not settings.FIREBASE_CREDENTIALS_PATH or not fcm_token:
            print(f"[DEV FCM] → {fcm_token[:20] if fcm_token else 'no-token'}... | {title}: {body}")
            return True

        message = {
            "message": {
                "token": fcm_token,
                "notification": {"title": title, "body": body},
                "android": {
                    "notification": {
                        "channel_id": "errand_alerts",
                        "priority": "HIGH",
                        "sound": "default",
                    }
                },
                "apns": {
                    "payload": {
                        "aps": {"alert": {"title": title, "body": body}, "sound": "default"}
                    }
                },
                "data": {k: str(v) for k, v in (data or {}).items()},
            }
        }

        try:
            access_token = await self._get_access_token()
            project_id = await self._get_project_id()
            url = self.FCM_URL.format(project_id=project_id)

            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    url,
                    json=message,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Content-Type": "application/json",
                    },
                )
                return resp.status_code == 200
        except Exception as e:
            print(f"[FCM ERROR] Failed to send notification: {e}")
            return False

    async def _get_access_token(self) -> str:
        """Gets Google OAuth2 access token for FCM."""
        try:
            import google.auth.transport.requests
            import google.oauth2.service_account
            credentials = google.oauth2.service_account.Credentials.from_service_account_file(
                settings.FIREBASE_CREDENTIALS_PATH,
                scopes=["https://www.googleapis.com/auth/firebase.messaging"],
            )
            request = google.auth.transport.requests.Request()
            credentials.refresh(request)
            return credentials.token
        except Exception:
            return "dev_token"

    async def _get_project_id(self) -> str:
        try:
            import json as _json
            with open(settings.FIREBASE_CREDENTIALS_PATH) as f:
                creds = _json.load(f)
            return creds.get("project_id", "errand-marketplace")
        except Exception:
            return "errand-marketplace"


fcm_service = FCMService()
