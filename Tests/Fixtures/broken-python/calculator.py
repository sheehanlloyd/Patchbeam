"""Tiny checkout calculator used as Patchbeam's deterministic repair fixture."""


def subtotal(items):
    """Sum of item prices."""
    return sum(items)


def total(items, tax_rate):
    """Return the order total including tax, rounded to cents."""
    base = subtotal(items)
    tax = base * tax_rate
    return round(base - tax, 2)
