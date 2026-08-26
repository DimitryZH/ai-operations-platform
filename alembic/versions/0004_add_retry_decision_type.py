"""Add retry decision type for semantic idempotency checks.

Revision ID: 0004_add_retry_decision_type
Revises: 0003_add_retry_decisions
Create Date: 2026-08-25 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0004_add_retry_decision_type"
down_revision = "0003_add_retry_decisions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "retry_decisions",
        sa.Column(
            "decision_type",
            sa.String(length=32),
            nullable=False,
            server_default="retry",
        ),
    )


def downgrade() -> None:
    op.drop_column("retry_decisions", "decision_type")
