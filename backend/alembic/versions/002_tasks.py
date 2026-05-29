"""Phase 2 — tasks, task_applications, completion_proofs tables

Revision ID: 002_tasks
Revises: 001_initial
Create Date: 2025-01-08 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "002_tasks"
down_revision: Union[str, None] = "001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── ENUMS ──────────────────────────────────────────────────────────────
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE task_category AS ENUM (
                'shopping','food_pickup','cleaning','delivery','office_errand',
                'car_wash','document_submission','pharmacy','market_shopping',
                'personal_assistance','queue_standing','moving_items',
                'cooking_help','elderly_care','custom'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE task_status AS ENUM (
                'posted','agents_applied','accepted','in_progress',
                'proof_submitted','completed','disputed','cancelled','expired'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE application_status AS ENUM (
                'pending','accepted','rejected','withdrawn'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    op.execute("""
        DO $$ BEGIN
            CREATE TYPE gender_preference AS ENUM (
                'any','female','male'
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)

    # ── TASKS ──────────────────────────────────────────────────────────────
    op.create_table(
        "tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("client_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("agent_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("agent_profiles.id", ondelete="SET NULL"), nullable=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text, nullable=False),
        sa.Column("category", sa.Enum("shopping","food_pickup","cleaning","delivery","office_errand","car_wash","document_submission","pharmacy","market_shopping","personal_assistance","queue_standing","moving_items","cooking_help","elderly_care","custom", name="task_category"), nullable=False),
        sa.Column("special_instructions", sa.Text, nullable=True),
        sa.Column("status", sa.Enum("posted","agents_applied","accepted","in_progress","proof_submitted","completed","disputed","cancelled","expired", name="task_status"), nullable=False, server_default="posted"),
        sa.Column("is_emergency", sa.Boolean, nullable=False, default=False),
        sa.Column("emergency_fee", sa.Numeric(12, 2), nullable=False, default=0),
        sa.Column("budget", sa.Numeric(12, 2), nullable=False),
        sa.Column("final_price", sa.Numeric(12, 2), nullable=True),
        sa.Column("pickup_address", sa.Text, nullable=False),
        sa.Column("pickup_lat", sa.Numeric(10, 8), nullable=False),
        sa.Column("pickup_lng", sa.Numeric(11, 8), nullable=False),
        sa.Column("destination_address", sa.Text, nullable=True),
        sa.Column("destination_lat", sa.Numeric(10, 8), nullable=True),
        sa.Column("destination_lng", sa.Numeric(11, 8), nullable=True),
        sa.Column("gender_preference", sa.Enum("any","female","male", name="gender_preference"), nullable=False, server_default="any"),
        sa.Column("preferred_agents_only", sa.Boolean, nullable=False, default=False),
        sa.Column("scheduled_at", sa.String(50), nullable=True),
        sa.Column("accepted_at", sa.String(50), nullable=True),
        sa.Column("started_at", sa.String(50), nullable=True),
        sa.Column("completed_at", sa.String(50), nullable=True),
        sa.Column("expires_at", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_tasks_client_id", "tasks", ["client_id"])
    op.create_index("ix_tasks_agent_id", "tasks", ["agent_id"])
    op.create_index("ix_tasks_status", "tasks", ["status"])
    op.create_index("ix_tasks_category", "tasks", ["category"])

    # ── TASK APPLICATIONS ──────────────────────────────────────────────────
    op.create_table(
        "task_applications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
        sa.Column("agent_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("agent_profiles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("proposed_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("message", sa.Text, nullable=True),
        sa.Column("eta_minutes", sa.Integer, nullable=True),
        sa.Column("status", sa.Enum("pending","accepted","rejected","withdrawn", name="application_status"), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_task_applications_task_id", "task_applications", ["task_id"])
    op.create_index("ix_task_applications_agent_id", "task_applications", ["agent_id"])
    op.create_index("ix_task_applications_status", "task_applications", ["status"])

    # ── COMPLETION PROOFS ──────────────────────────────────────────────────
    op.create_table(
        "completion_proofs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tasks.id", ondelete="CASCADE"), unique=True, nullable=False),
        sa.Column("photo_urls", sa.Text, nullable=True),
        sa.Column("video_url", sa.Text, nullable=True),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("otp_code", sa.String(6), nullable=True),
        sa.Column("otp_verified", sa.Boolean, nullable=False, default=False),
        sa.Column("otp_verified_at", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_completion_proofs_task_id", "completion_proofs", ["task_id"])


def downgrade() -> None:
    op.drop_table("completion_proofs")
    op.drop_table("task_applications")
    op.drop_table("tasks")
    op.execute("DROP TYPE IF EXISTS gender_preference")
    op.execute("DROP TYPE IF EXISTS application_status")
    op.execute("DROP TYPE IF EXISTS task_status")
    op.execute("DROP TYPE IF EXISTS task_category")