"""Small cross-platform operating-system adapters."""

from __future__ import annotations

import webbrowser


def open_url(url: str) -> bool:
    try:
        return webbrowser.open(url, new=2)
    except webbrowser.Error:
        return False
