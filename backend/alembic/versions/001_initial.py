"""Initial Phase 1 schema — users, agent_profiles, verifications, auth tokens

Revision ID: 001_initial
Revises:
Create Date: 2025-01-01 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create enums safely — DO NOT use IF NOT EXISTS, it is not valid PostgreSQL syntax
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE user_role AS ENUM ('client', 'agent', 'business', 'admin');
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE trust_level AS ENUM ('bronze', 'silver', 'gold', 'platinum');
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE verification_status AS ENUM ('pending', 'approved', 'rejected', 'resubmitted');
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), unique=True, nullable=True),
        sa.Column("phone", sa.String(20), unique=True, nullable=False),
        sa.Column("phone_verified", sa.Boolean, nullable=False, default=False),
        sa.Column("full_name", sa.String(100), nullable=False),
        sa.Column("password_hash", sa.Text, nullable=False),
        sa.Column("role", sa.Enum("client", "agent", "business", "admin", name="user_role"), nullable=False),
        sa.Column("is_active", sa.Boolean, nullable=False, default=True),
        sa.Column("is_verified", sa.Boolean, nullable=False, default=False),
        sa.Column("avatar_url", sa.Text, nullable=True),
        sa.Column("fcm_token", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_users_phone", "users", ["phone"])
    op.create_index("ix_users_email", "users", ["email"])

    op.create_table(
        "agent_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False),
        sa.Column("trust_level", sa.Enum("bronze", "silver", "gold", "platinum", name="trust_level"), nullable=False, default="bronze"),
        sa.Column("trust_score", sa.Numeric(4, 2), nullable=False, default=0.0),
        sa.Column("total_tasks", sa.Integer, nullable=False, default=0),
        sa.Column("completed_tasks", sa.Integer, nullable=False, default=0),
        sa.Column("cancelled_tasks", sa.Integer, nullable=False, default=0),
        sa.Column("success_rate", sa.Numeric(5, 2), nullable=False, default=0.0),
        sa.Column("punctuality_rate", sa.Numeric(5, 2), nullable=False, default=0.0),
        sa.Column("repeat_client_count", sa.Integer, nullable=False, default=0),
        sa.Column("bio", sa.Text, nullable=True),
        sa.Column("skill_tags", postgresql.ARRAY(sa.String), nullable=True),
        sa.Column("years_active", sa.Numeric(4, 1), nullable=False, default=0.0),
        sa.Column("is_available", sa.Boolean, nullable=False, default=False),
        sa.Column("current_lat", sa.Numeric(10, 8), nullable=True),
        sa.Column("current_lng", sa.Numeric(11, 8), nullable=True),
        sa.Column("gender", sa.String(10), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_agent_profiles_user_id", "agent_profiles", ["user_id"])

    op.create_table(
        "agent_verifications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("agent_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("agent_profiles.id", ondelete="CASCADE"), unique=True, nullable=False),
        sa.Column("nin_number", sa.String(20), nullable=True),
        sa.Column("nin_doc_url", sa.Text, nullable=True),
        sa.Column("selfie_url", sa.Text, nullable=True),
        sa.Column("address_doc_url", sa.Text, nullable=True),
        sa.Column("address_text", sa.Text, nullable=True),
        sa.Column("guarantor_name", sa.String(100), nullable=True),
        sa.Column("guarantor_phone", sa.String(20), nullable=True),
        sa.Column("guarantor_relationship", sa.String(50), nullable=True),
        sa.Column("bvn_number", sa.String(20), nullable=True),
        sa.Column("status", sa.Enum("pending", "approved", "rejected", "resubmitted", name="verification_status"), nullable=False, default="pending"),
        sa.Column("reviewed_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("rejection_reason", sa.Text, nullable=True),
        sa.Column("submission_count", sa.Integer, nullable=False, default=1),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_agent_verifications_status", "agent_verifications", ["status"])

    op.create_table(
        "otp_codes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("phone", sa.String(20), nullable=False),
        sa.Column("code", sa.String(10), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used", sa.Boolean, nullable=False, default=False),
        sa.Column("attempt_count", sa.Integer, nullable=False, default=0),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_otp_codes_phone", "otp_codes", ["phone"])
    op.create_index("ix_otp_codes_user_id", "otp_codes", ["user_id"])

    op.create_table(
        "refresh_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.Text, nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked", sa.Boolean, nullable=False, default=False),
        sa.Column("device_info", sa.String(255), nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index("ix_refresh_tokens_token_hash", "refresh_tokens", ["token_hash"])


def downgrade() -> None:
    op.drop_table("refresh_tokens")
    op.drop_table("otp_codes")
    op.drop_table("agent_verifications")
    op.drop_table("agent_profiles")
    op.drop_table("users")

    op.execute("DROP TYPE IF EXISTS verification_status")
    op.execute("DROP TYPE IF EXISTS trust_level")
    op.execute("DROP TYPE IF EXISTS user_role")
