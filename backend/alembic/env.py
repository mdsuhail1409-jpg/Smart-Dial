"""
Alembic migration environment.

Reads DATABASE_URL from the application's config (loaded from .env),
and uses the SQLAlchemy metadata from our models for autogenerate support.

Note: We create the engine directly (not via config.set_main_option) so that
special characters in the DATABASE_URL (e.g. %40 for @) are not misinterpreted
by Python's configparser interpolation engine.
"""

import sys
import os
from logging.config import fileConfig

from sqlalchemy import create_engine, pool
from alembic import context

# Make sure the `app` package is importable from within alembic/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings
from app.database import Base
import app.models  # noqa: F401 — ensures all models are registered on Base.metadata

# Alembic Config object
config = context.config

# Set up logging from alembic.ini
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Load DATABASE_URL from .env — do NOT pass through set_main_option/configparser
# because special characters like % in URL-encoded passwords cause ValueError.
settings = get_settings()
DATABASE_URL = settings.DATABASE_URL

# Metadata used for autogenerate
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations without an active DB connection (generates SQL script)."""
    context.configure(
        url=DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations against a live database connection."""
    connectable = create_engine(DATABASE_URL, poolclass=pool.NullPool)

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
