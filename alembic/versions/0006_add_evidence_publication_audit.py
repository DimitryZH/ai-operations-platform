"""add durable evidence and publication audit fields

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
    # Legacy databases can have multiple evidence rows for one attempt. Retain the
    # newest row before enforcing the invariant used by the local evidence adapter.
    op.execute(
        "DELETE FROM evidence_artifacts WHERE id IN ("
        "SELECT id FROM (SELECT id, row_number() OVER "
        "(PARTITION BY attempt_id ORDER BY id DESC) AS row_number FROM evidence_artifacts) ranked "
        "WHERE ranked.row_number > 1)"
    )
    with op.batch_alter_table("evidence_artifacts") as batch_op:
        batch_op.create_unique_constraint("uq_evidence_artifacts_attempt_id", ["attempt_id"])
    op.create_table(
        "publication_intents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id"), nullable=False),
        # Pre-0006 publication audit rows may be task-scoped. Preserve their
        # NULL attempt identity rather than inventing a producing attempt.
        sa.Column("attempt_id", sa.Integer(), sa.ForeignKey("attempts.id"), nullable=True),
        sa.Column("idempotency_key", sa.String(length=128), nullable=False),
        sa.Column("payload_sha256", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("fencing_token", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("active_claim_token", sa.String(length=64), nullable=True),
        sa.Column("github_reference", sa.String(length=512), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("idempotency_key", name="uq_publication_intents_idempotency_key"),
    )
    with op.batch_alter_table("github_publications") as batch_op:
        batch_op.add_column(sa.Column("payload_sha256", sa.String(length=64), nullable=False, server_default=""))
        batch_op.add_column(sa.Column("error_category", sa.String(length=64), nullable=True))
        batch_op.add_column(sa.Column("publication_intent_id", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("attempt_sequence", sa.Integer(), nullable=False, server_default="1"))
        batch_op.alter_column("github_reference", existing_type=sa.String(length=512), nullable=True)
    op.execute(
        "INSERT INTO publication_intents "
        "(task_id, attempt_id, idempotency_key, payload_sha256, status, fencing_token, github_reference) "
        "SELECT task_id, attempt_id, idempotency_key, payload_sha256, "
        "CASE WHEN status = 'PUBLISHED' THEN 'PUBLISHED' ELSE 'FAILED' END, 0, github_reference "
        "FROM github_publications"
    )
    op.execute(
        "UPDATE github_publications SET publication_intent_id = publication_intents.id "
        "FROM publication_intents WHERE github_publications.idempotency_key = publication_intents.idempotency_key"
    )
    with op.batch_alter_table("github_publications") as batch_op:
        batch_op.drop_constraint("uq_github_publications_idempotency_key", type_="unique")
        batch_op.create_foreign_key(
            "fk_github_publications_publication_intent_id",
            "publication_intents", ["publication_intent_id"], ["id"],
        )
        batch_op.alter_column("publication_intent_id", nullable=False)
        batch_op.create_unique_constraint(
            "uq_github_publications_intent_sequence",
            ["publication_intent_id", "attempt_sequence"],
        )


def downgrade() -> None:
    # The old non-null reference cannot represent pending or failed records. Use a
    # deterministic marker and retain the latest record per logical publication.
    op.execute(
        "UPDATE github_publications SET github_reference = 'unpublished://publication/' || id "
        "WHERE github_reference IS NULL"
    )
    op.execute(
        "DELETE FROM github_publications WHERE id IN ("
        "SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY idempotency_key "
        "ORDER BY CASE WHEN status = 'PUBLISHED' THEN 0 ELSE 1 END, id DESC) AS row_number "
        "FROM github_publications) ranked WHERE ranked.row_number > 1)"
    )
    with op.batch_alter_table("github_publications") as batch_op:
        batch_op.drop_constraint("uq_github_publications_intent_sequence", type_="unique")
        batch_op.drop_constraint("fk_github_publications_publication_intent_id", type_="foreignkey")
        batch_op.drop_column("attempt_sequence")
        batch_op.drop_column("publication_intent_id")
        batch_op.alter_column("github_reference", existing_type=sa.String(length=512), nullable=False)
        batch_op.drop_column("error_category")
        batch_op.drop_column("payload_sha256")
        batch_op.create_unique_constraint("uq_github_publications_idempotency_key", ["idempotency_key"])
    op.drop_table("publication_intents")
    with op.batch_alter_table("evidence_artifacts") as batch_op:
        batch_op.drop_constraint("uq_evidence_artifacts_attempt_id", type_="unique")
