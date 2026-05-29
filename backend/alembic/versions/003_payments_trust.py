"""Phase 3 — escrow_transactions, reviews, disputes, notifications

Revision ID: 003_payments_trust
Revises: 002_tasks
Create Date: 2025-01-15 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "003_payments_trust"
down_revision: Union[str, None] = "002_tasks"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── ENUMS ──────────────────────────────────────────────────────────────
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE escrow_status AS ENUM (
                'pending','held','released','refunded','failed'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE dispute_status AS ENUM (
                'open','under_review','resolved_refund',
                'resolved_release','resolved_partial','closed'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE notification_type AS ENUM (
                'task_posted','agent_applied','application_accepted',
                'application_rejected','task_started','proof_submitted',
                'task_completed','payment_received','payment_released',
                'review_received','level_up','verification_approved',
                'verification_rejected','dispute_raised','dispute_resolved'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    # ── ESCROW TRANSACTIONS ────────────────────────────────────────────────
    op.create_table(
        "escrow_transactions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tasks.id", ondelete="CASCADE"), unique=True, nullable=False),
        sa.Column("client_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("agent_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("agent_profiles.id", ondelete="SET NULL"), nullable=True),
        sa.Column("paystack_reference", sa.String(100), unique=True, nullable=False),
        sa.Column("paystack_authorization_url", sa.Text, nullable=True),
        sa.Column("paystack_access_code", sa.String(100), nullable=True),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("platform_fee", sa.Numeric(12, 2), nullable=False, default=0),
        sa.Column("agent_payout", sa.Numeric(12, 2), nullable=False, default=0),
        sa.Column("status", sa.Enum("pending","held","released","refunded","failed", name="escrow_status"), nullable=False, server_default="pending"),
        sa.Column("paid_at", sa.String(50), nullable=True),
        sa.Column("released_at", sa.String(50), nullable=True),
        sa.Column("refunded_at", sa.String(50), nullable=True),
        sa.Column("payout_reference", sa.String(100), nullable=True),
        sa.Column("payout_status", sa.String(30), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_escrow_task_id", "escrow_transactions", ["task_id"])
    op.create_index("ix_escrow_client_id", "escrow_transactions", ["client_id"])
    op.create_index("ix_escrow_reference", "escrow_transactions", ["paystack_reference"])
    op.create_index("ix_escrow_status", "escrow_transactions", ["status"])

    # ── REVIEWS ────────────────────────────────────────────────────────────
    op.create_table(
        "reviews",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("reviewer_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("reviewee_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("overall_rating", sa.Integer, nullable=False),
        sa.Column("punctuality", sa.Integer, nullable=False),
        sa.Column("trustworthiness", sa.Integer, nullable=False),
        sa.Column("communication", sa.Integer, nullable=False),
        sa.Column("professionalism", sa.Integer, nullable=False),
        sa.Column("comment", sa.Text, nullable=True),
        sa.Column("is_public", sa.Boolean, nullable=False, default=True),
        sa.Column("weighted_score", sa.Numeric(4, 2), nullable=False, default=0),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_reviews_task_id", "reviews", ["task_id"])
    op.create_index("ix_reviews_reviewer_id", "reviews", ["reviewer_id"])
    op.create_index("ix_reviews_reviewee_id", "reviews", ["reviewee_id"])

    # ── DISPUTES ───────────────────────────────────────────────────────────
    op.create_table(
        "disputes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tasks.id", ondelete="CASCADE"), unique=True, nullable=False),
        sa.Column("raised_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("reason", sa.String(200), nullable=False),
        sa.Column("description", sa.Text, nullable=False),
        sa.Column("evidence_urls", sa.Text, nullable=True),
        sa.Column("status", sa.Enum("open","under_review","resolved_refund","resolved_release","resolved_partial","closed", name="dispute_status"), nullable=False, server_default="open"),
        sa.Column("resolved_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("resolution_note", sa.Text, nullable=True),
        sa.Column("resolved_at", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_disputes_task_id", "disputes", ["task_id"])
    op.create_index("ix_disputes_status", "disputes", ["status"])

    # ── NOTIFICATIONS ──────────────────────────────────────────────────────
    op.create_table(
        "notifications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("type", sa.Enum("task_posted","agent_applied","application_accepted","application_rejected","task_started","proof_submitted","task_completed","payment_received","payment_released","review_received","level_up","verification_approved","verification_rejected","dispute_raised","dispute_resolved", name="notification_type"), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("data", sa.Text, nullable=True),
        sa.Column("is_read", sa.Boolean, nullable=False, default=False),
        sa.Column("sent_push", sa.Boolean, nullable=False, default=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_notifications_user_id", "notifications", ["user_id"])
    op.create_index("ix_notifications_type", "notifications", ["type"])
    op.create_index("ix_notifications_is_read", "notifications", ["is_read"])


def downgrade() -> None:
    op.drop_table("notifications")
    op.drop_table("disputes")
    op.drop_table("reviews")
    op.drop_table("escrow_transactions")
    op.execute("DROP TYPE IF EXISTS notification_type")
    op.execute("DROP TYPE IF EXISTS dispute_status")
    op.execute("DROP TYPE IF EXISTS escrow_status")