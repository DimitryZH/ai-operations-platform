"""normalize legacy retryable publication failures

Revision ID: 0007_publication_failure_states
Revises: 0006_evidence_publication
"""

from alembic import op


revision = "0007_publication_failure_states"
down_revision = "0006_evidence_publication"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Revision 0006 used FAILED for every non-published publication outcome.
    # Those durable records predate terminal failure classification, so they are
    # deterministically retryable rather than silently discarded.
    op.execute("UPDATE publication_intents SET status = 'FAILED_RETRYABLE' WHERE status = 'FAILED'")
    op.execute("UPDATE github_publications SET status = 'FAILED_RETRYABLE' WHERE status = 'FAILED'")


def downgrade() -> None:
    op.execute("UPDATE publication_intents SET status = 'FAILED' WHERE status = 'FAILED_RETRYABLE'")
    op.execute("UPDATE github_publications SET status = 'FAILED' WHERE status = 'FAILED_RETRYABLE'")
