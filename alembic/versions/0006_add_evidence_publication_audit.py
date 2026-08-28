"""add evidence and publication audit fields

Revision ID: 0006_evidence_publication
Revises: 0005_add_dispatch_lease_fencing
"""

from alembic import op
import sqlalchemy as sa

revision = "0006_evidence_publication"
down_revision = "0005_add_dispatch_lease_fencing"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("evidence_artifacts") as batch_op:
        batch_op.create_unique_constraint("uq_evidence_artifacts_attempt_id", ["attempt_id"])
    with op.batch_alter_table("github_publications") as batch_op:
        batch_op.add_column(sa.Column("payload_sha256", sa.String(length=64), nullable=False, server_default=""))
        batch_op.add_column(sa.Column("error_category", sa.String(length=64), nullable=True))
        batch_op.alter_column("github_reference", existing_type=sa.String(length=512), nullable=True)


def downgrade() -> None:
    with op.batch_alter_table("github_publications") as batch_op:
        batch_op.alter_column("github_reference", existing_type=sa.String(length=512), nullable=False)
        batch_op.drop_column("error_category")
        batch_op.drop_column("payload_sha256")
    with op.batch_alter_table("evidence_artifacts") as batch_op:
        batch_op.drop_constraint("uq_evidence_artifacts_attempt_id", type_="unique")
