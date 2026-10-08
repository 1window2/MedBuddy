# File Name: __init__.py
# Role: Marks tests/support as the package of shared helpers for backend tests.
#   tests/conftest.py puts the tests directory on sys.path, so test files import the helpers as
#   `from support.db import ...` and `from support.fakes import ...`.
