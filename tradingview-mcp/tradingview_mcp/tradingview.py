"""Thin client over TradingView's publicly reachable data endpoints.

TradingView does not publish an official REST API for account data, so a
"custom connector" can only work against the endpoints their own web app
uses:

* the *scanner* endpoint that powers the technical-analysis widget, wrapped
  here through the maintained ``tradingview-ta`` library, and
* the public *symbol-search* endpoint used by the search box.

Nothing here needs your TradingView login. It reads the same market data the
website serves to anonymous visitors. Respect TradingView's Terms of Service
and rate limits when you deploy it.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import requests
from tradingview_ta import TA_Handler, Interval

# Human-friendly interval names -> tradingview_ta constants.
INTERVALS: dict[str, str] = {
    "1m": Interval.INTERVAL_1_MINUTE,
    "5m": Interval.INTERVAL_5_MINUTES,
    "15m": Interval.INTERVAL_15_MINUTES,
    "30m": Interval.INTERVAL_30_MINUTES,
    "1h": Interval.INTERVAL_1_HOUR,
    "2h": Interval.INTERVAL_2_HOURS,
    "4h": Interval.INTERVAL_4_HOURS,
    "1d": Interval.INTERVAL_1_DAY,
    "1W": Interval.INTERVAL_1_WEEK,
    "1M": Interval.INTERVAL_1_MONTH,
}

_SEARCH_URL = "https://symbol-search.tradingview.com/symbol_search/"
_SEARCH_HEADERS = {
    # TradingView's search endpoint checks Origin/Referer.
    "Origin": "https://www.tradingview.com",
    "Referer": "https://www.tradingview.com/",
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
}


class TradingViewError(RuntimeError):
    """Raised when a TradingView request cannot be fulfilled."""


@dataclass
class SymbolRef:
    """A resolved TradingView symbol."""

    symbol: str
    exchange: str
    screener: str
    description: str
    type: str


def _resolve_interval(interval: str) -> str:
    try:
        return INTERVALS[interval]
    except KeyError:
        valid = ", ".join(INTERVALS)
        raise TradingViewError(
            f"Unknown interval {interval!r}. Valid intervals: {valid}."
        ) from None


def get_analysis(
    symbol: str,
    exchange: str,
    screener: str = "america",
    interval: str = "1d",
) -> dict[str, Any]:
    """Return TradingView's technical-analysis summary for one symbol.

    Args:
        symbol: Ticker as TradingView spells it, e.g. ``AAPL``, ``BTCUSDT``.
        exchange: Exchange/data source, e.g. ``NASDAQ``, ``BINANCE``, ``FX_IDC``.
        screener: Market screener: ``america``, ``crypto``, ``forex``, etc.
        interval: One of the keys in :data:`INTERVALS` (default ``1d``).
    """
    handler = TA_Handler(
        symbol=symbol,
        exchange=exchange,
        screener=screener,
        interval=_resolve_interval(interval),
    )
    try:
        analysis = handler.get_analysis()
    except Exception as exc:  # tradingview_ta raises bare Exceptions
        raise TradingViewError(
            f"Could not load analysis for {exchange}:{symbol} "
            f"(screener={screener}, interval={interval}): {exc}"
        ) from exc

    if analysis is None:
        raise TradingViewError(
            f"No analysis returned for {exchange}:{symbol}. "
            "Check the symbol, exchange, and screener."
        )

    return {
        "symbol": symbol,
        "exchange": exchange,
        "screener": screener,
        "interval": interval,
        "time": str(analysis.time) if analysis.time else None,
        "summary": analysis.summary,          # overall RECOMMENDATION + counts
        "oscillators": analysis.oscillators,  # oscillator recommendation block
        "moving_averages": analysis.moving_averages,
    }


def get_indicators(
    symbol: str,
    exchange: str,
    screener: str = "america",
    interval: str = "1d",
    indicators: list[str] | None = None,
) -> dict[str, Any]:
    """Return raw indicator values (RSI, MACD, close, volume, ...).

    If ``indicators`` is given, only those keys are returned; otherwise the
    full indicator dictionary TradingView computed for the interval is
    returned.
    """
    handler = TA_Handler(
        symbol=symbol,
        exchange=exchange,
        screener=screener,
        interval=_resolve_interval(interval),
    )
    try:
        analysis = handler.get_analysis()
    except Exception as exc:
        raise TradingViewError(
            f"Could not load indicators for {exchange}:{symbol}: {exc}"
        ) from exc

    if analysis is None or analysis.indicators is None:
        raise TradingViewError(f"No indicator data for {exchange}:{symbol}.")

    values = analysis.indicators
    if indicators:
        missing = [key for key in indicators if key not in values]
        selected = {key: values[key] for key in indicators if key in values}
        return {
            "symbol": symbol,
            "exchange": exchange,
            "interval": interval,
            "indicators": selected,
            "missing": missing,
        }

    return {
        "symbol": symbol,
        "exchange": exchange,
        "interval": interval,
        "indicators": values,
    }


def search_symbol(query: str, exchange: str = "", limit: int = 10) -> list[dict[str, Any]]:
    """Resolve a free-text query to TradingView symbols via the search box API.

    Returns a list of candidates with ``symbol``, ``exchange``, ``type`` and a
    plain-text ``description`` you can feed back into :func:`get_analysis`.
    """
    params = {"text": query, "hl": "1", "lang": "en", "type": ""}
    if exchange:
        params["exchange"] = exchange
    try:
        resp = requests.get(
            _SEARCH_URL, params=params, headers=_SEARCH_HEADERS, timeout=15
        )
        resp.raise_for_status()
        payload = resp.json()
    except requests.RequestException as exc:
        raise TradingViewError(f"Symbol search failed: {exc}") from exc
    except ValueError as exc:
        raise TradingViewError("Symbol search returned invalid JSON.") from exc

    results: list[dict[str, Any]] = []
    for item in payload[:limit]:
        # TradingView wraps matched text in <em> tags; strip them.
        desc = (item.get("description") or "").replace("<em>", "").replace("</em>", "")
        sym = (item.get("symbol") or "").replace("<em>", "").replace("</em>", "")
        results.append(
            {
                "symbol": sym,
                "exchange": item.get("exchange", ""),
                "type": item.get("type", ""),
                "description": desc,
                "country": item.get("country", ""),
            }
        )
    return results
