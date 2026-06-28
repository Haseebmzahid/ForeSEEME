"""Pytest configuration for the ForeSeeMe backend.

Adds the ``backend/`` directory (this file's directory) to ``sys.path`` so the
tests can ``from app.schemas import ...`` whether pytest is invoked from the
repository root (``pytest backend/tests/test_schemas.py``) or from ``backend/``.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
