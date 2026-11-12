# broken-python fixture

A deliberately broken, dependency-free Python project used by Patchbeam's tests, headless demo and onboarding.

**Seeded bug:** `total(items, tax_rate)` in `calculator.py` *subtracts* the tax instead of adding it, so `test_total_adds_tax` fails with `AssertionError: 27.0 != 33.0`.

**Correct behavior:** `total([10.0, 20.0], tax_rate=0.1) == 33.0`.

**Check command:** `python3 -m unittest -v` (exits 1 on the broken baseline and 0 once fixed).

`gitignore.fixture` is copied to `.gitignore` when the fixture is turned into a Git repository. It isn't stored as `.gitignore` here, so that it doesn't affect the Patchbeam repository itself.
