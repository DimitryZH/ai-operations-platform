"""Add explicit retry decision records.

Revision ID: 0003_add_retry_decisions
Revises: 0002_add_investigation_results
Create Date: 2026-08-26 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0003_add_retry_decisions"
down_revision = "0002_add_investigation_results"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "retry_decisions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("retry_id", sa.String(length=128), nullable=False),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id"), nullable=False),
        sa.Column("previous_attempt_id", sa.Integer(), sa.ForeignKey("attempts.id"), nullable=True),
        sa.Column("new_attempt_id", sa.Integer(), sa.ForeignKey("attempts.id"), nullable=True),
        sa.Column("actor", sa.String(length=128), nullable=False),
        sa.Column("rationale", sa.Text(), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("github_reference", sa.String(length=512), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("retry_id", name="uq_retry_decisions_retry_id"),
    )


def downgrade() -> None:
    op.drop_table("retry_decisions")
