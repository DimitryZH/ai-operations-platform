"""Add normalized investigation result records.

Revision ID: 0002_add_investigation_results
Revises: 0001_initial_sre_control_plane
Create Date: 2026-08-25 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0002_add_investigation_results"
down_revision = "0001_initial_sre_control_plane"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "investigation_results",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("result_id", sa.String(length=128), nullable=False),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id"), nullable=False),
        sa.Column("attempt_id", sa.Integer(), sa.ForeignKey("attempts.id"), nullable=False),
        sa.Column("executor_id", sa.String(length=128), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("result_id", name="uq_investigation_results_result_id"),
        sa.UniqueConstraint("attempt_id", name="uq_investigation_results_attempt_id"),
    )


def downgrade() -> None:
    op.drop_table("investigation_results")
