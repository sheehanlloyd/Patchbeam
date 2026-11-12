import unittest

from calculator import subtotal, total


class CalculatorTests(unittest.TestCase):
    def test_subtotal(self):
        self.assertEqual(subtotal([10.0, 20.0]), 30.0)

    def test_total_adds_tax(self):
        self.assertEqual(total([10.0, 20.0], tax_rate=0.1), 33.0)

    def test_total_without_tax(self):
        self.assertEqual(total([5.0], tax_rate=0.0), 5.0)


if __name__ == "__main__":
    unittest.main()
