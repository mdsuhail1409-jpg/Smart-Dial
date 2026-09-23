"""create communication_decisions table

Revision ID: b7e21a8f9c4d
Revises: a9f4896d337e
Create Date: 2026-09-18 21:25:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7e21a8f9c4d'
down_revision: Union[str, None] = 'a9f4896d337e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'communication_decisions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('decision_id', sa.String(length=20), nullable=False),
        sa.Column('pair_id', sa.String(length=20), nullable=False),
        sa.Column(
            'decision_type',
            sa.Enum('ALLOW_A_TO_B', 'ALLOW_B_TO_A', 'ASK_USER', 'BLOCK', name='decisiontype'),
            nullable=False,
        ),
        sa.Column('selected_request_id', sa.Integer(), nullable=True),
        sa.Column(
            'reason_code',
            sa.Enum(
                'DEFAULT_POLICY',
                'USER_PREFERENCE',
                'EXPLICIT_USER_CHOICE',
                'DND_ACTIVE',
                'VIP_PRIORITY',
                'USER_UNAVAILABLE',
                'NETWORK_CONDITION',
                name='reasoncode',
            ),
            nullable=False,
        ),
        sa.Column('context_snapshot', sa.Text(), nullable=False, server_default='{}'),
        sa.Column(
            'status',
            sa.Enum('PENDING', 'RESOLVED', 'EXPIRED', name='decisionstatus'),
            server_default='RESOLVED',
            nullable=False,
        ),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['pair_id'], ['reciprocal_pairs.pair_id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['selected_request_id'], ['communication_requests.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('pair_id', name='uq_communication_decisions_pair_id'),
    )
    op.create_index(op.f('ix_communication_decisions_id'), 'communication_decisions', ['id'], unique=False)
    op.create_index(op.f('ix_communication_decisions_decision_id'), 'communication_decisions', ['decision_id'], unique=True)
    op.create_index(op.f('ix_communication_decisions_pair_id'), 'communication_decisions', ['pair_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_communication_decisions_pair_id'), table_name='communication_decisions')
    op.drop_index(op.f('ix_communication_decisions_decision_id'), table_name='communication_decisions')
    op.drop_index(op.f('ix_communication_decisions_id'), table_name='communication_decisions')
    op.drop_table('communication_decisions')
