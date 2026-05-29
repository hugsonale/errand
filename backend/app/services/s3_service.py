import uuid
import boto3
from botocore.exceptions import ClientError
from fastapi import UploadFile

from app.config import settings
from app.core.exceptions import ServiceUnavailableError, BadRequestError

# Allowed MIME types per upload category
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
ALLOWED_DOC_TYPES = {"image/jpeg", "image/png", "application/pdf"}
MAX_FILE_SIZE_MB = 10
MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024


class S3Service:
    def __init__(self):
        self._client = None

    @property
    def client(self):
        """Lazy init — only creates boto3 client when first needed."""
        if self._client is None:
            self._client = boto3.client(
                "s3",
                aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
                region_name=settings.AWS_REGION,
            )
        return self._client

    async def upload_file(
        self,
        file: UploadFile,
        folder: str,
        allowed_types: set[str] | None = None,
    ) -> str:
        """
        Uploads a file to S3 and returns the S3 key (not a public URL).
        All files are private — access via presigned URLs only.

        folder examples: "avatars", "kyc/nin", "kyc/selfie", "kyc/address"
        """
        if allowed_types is None:
            allowed_types = ALLOWED_DOC_TYPES

        # Validate content type
        if file.content_type not in allowed_types:
            raise BadRequestError(
                f"File type '{file.content_type}' not allowed. "
                f"Accepted: {', '.join(allowed_types)}"
            )

        # Read and validate size
        contents = await file.read()
        if len(contents) > MAX_FILE_SIZE_BYTES:
            raise BadRequestError(f"File too large. Maximum size is {MAX_FILE_SIZE_MB}MB.")

        # Generate a unique key
        extension = file.filename.rsplit(".", 1)[-1] if file.filename and "." in file.filename else "bin"
        key = f"{folder}/{uuid.uuid4()}.{extension}"

        if not settings.AWS_ACCESS_KEY_ID:
            # Dev mode — return a fake key so the flow continues
            print(f"[DEV S3] Would upload to s3://{settings.S3_BUCKET_NAME}/{key}")
            return key

        try:
            self.client.put_object(
                Bucket=settings.S3_BUCKET_NAME,
                Key=key,
                Body=contents,
                ContentType=file.content_type,
                ServerSideEncryption="AES256",
            )
        except ClientError as e:
            raise ServiceUnavailableError(f"File upload failed: {e}")

        return key

    def get_presigned_url(self, key: str) -> str:
        """
        Generates a short-lived presigned URL for private S3 objects.
        Never expose raw S3 keys to clients — always go through this.
        """
        if not settings.AWS_ACCESS_KEY_ID:
            return f"http://localhost:8000/dev-media/{key}"

        try:
            url = self.client.generate_presigned_url(
                "get_object",
                Params={"Bucket": settings.S3_BUCKET_NAME, "Key": key},
                ExpiresIn=settings.S3_PRESIGNED_URL_EXPIRE,
            )
            return url
        except ClientError as e:
            raise ServiceUnavailableError(f"Could not generate file URL: {e}")

    def build_public_url(self, key: str) -> str:
        """
        For avatar images served via CloudFront CDN (Phase 4+).
        Falls back to presigned URL if CDN not configured.
        """
        return self.get_presigned_url(key)


s3_service = S3Service()
