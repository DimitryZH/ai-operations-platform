"""Add fenced sequential dispatcher state.

Revision ID: 0005_add_dispatch_lease_fencing
Revises: 0004_add_retry_decision_type
Create Date: 2026-08-26 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0005_add_dispatch_lease_fencing"
down_revision = "0004_add_retry_decision_type"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "task_transitions",
        sa.Column("fencing_token", sa.Integer(), nullable=True),
    )
    op.execute(
        sa.text(
            "INSERT INTO dispatch_leases "
            "(lease_name, lease_owner, expires_at, heartbeat_at, fencing_token) "
            "VALUES ('first_sre_dispatch', 'unclaimed', CURRENT_TIMESTAMP, "
            "CURRENT_TIMESTAMP, 0) "
            "ON CONFLICT (lease_name) DO NOTHING"
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            "DELETE FROM dispatch_leases WHERE lease_name = 'first_sre_dispatch'"
        )
    )
    op.drop_column("task_transitions", "fencing_token")
