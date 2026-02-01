"""MarginDash Python SDK — track AI usage and revenue."""

from margindash.client import MarginDash
from margindash.types import Event, MarginDashError

__all__ = [
    "MarginDash",
    "Event",
    "MarginDashError",
]

__version__ = "0.1.0"
