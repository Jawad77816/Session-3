"""TradingView MCP server.

Exposes TradingView technical-analysis data as MCP tools. Runs in two modes:

* ``stdio`` (default) — for local clients such as Claude Desktop / Claude Code.
* ``http``            — streamable-HTTP, the transport claude.ai "Custom
                        Connectors" require. Deploy it behind HTTPS and paste
                        the ``/mcp`` URL into the custom-connector dialog.

Choose the mode with the ``TRADINGVIEW_MCP_TRANSPORT`` env var or ``--transport``.
"""

from __future__ import annotations

import argparse
import os
from typing import Any

try:
    # mcp SDK 1.x
    from mcp.server.fastmcp import FastMCP
    _MCP_MAJOR = 1
except ImportError:
    # mcp SDK 2.x renamed FastMCP -> MCPServer (same tool()/run() surface)
    from mcp.server.mcpserver import MCPServer as FastMCP
    _MCP_MAJOR = 2

from .tradingview import (
    INTERVALS,
    TradingViewError,
    get_analysis as tv_get_analysis,
    get_indicators as tv_get_indicators,
    search_symbol as tv_search_symbol,
)

mcp = FastMCP(
    "tradingview",
    instructions=(
        "Tools for TradingView technical-analysis data. Symbols need an "
        "exchange and a screener (america, crypto, forex, ...). Use "
        "`search_symbol` first when you are unsure how TradingView spells a "
        "ticker or which exchange to use."
    ),
)


@mcp.tool()
def search_symbol(query: str, exchange: str = "", limit: int = 10) -> list[dict[str, Any]]:
    """Find TradingView symbols matching free text (company name or ticker).

    Args:
        query: What to search for, e.g. "apple", "bitcoin", "eurusd".
        exchange: Optional exchange filter, e.g. "NASDAQ", "BINANCE".
        limit: Max results (default 10).
    """
    return tv_search_symbol(query, exchange=exchange, limit=limit)


@mcp.tool()
def get_analysis(
    symbol: str,
    exchange: str,
    screener: str = "america",
    interval: str = "1d",
) -> dict[str, Any]:
    """Get TradingView's buy/sell/neutral technical summary for a symbol.

    Args:
        symbol: Ticker as TradingView spells it, e.g. "AAPL", "BTCUSDT".
        exchange: Exchange/data source, e.g. "NASDAQ", "BINANCE", "FX_IDC".
        screener: Market screener: "america", "crypto", "forex", "india", ...
        interval: Timeframe: 1m, 5m, 15m, 30m, 1h, 2h, 4h, 1d, 1W, 1M.

    Returns the overall recommendation plus the oscillator and moving-average
    breakdowns (each a RECOMMENDATION with BUY / SELL / NEUTRAL counts).
    """
    return tv_get_analysis(symbol, exchange, screener=screener, interval=interval)


@mcp.tool()
def get_indicators(
    symbol: str,
    exchange: str,
    screener: str = "america",
    interval: str = "1d",
    indicators: list[str] | None = None,
) -> dict[str, Any]:
    """Get raw indicator values (RSI, MACD, close, volume, EMAs, ...).

    Args:
        symbol: Ticker as TradingView spells it.
        exchange: Exchange/data source.
        screener: Market screener.
        interval: Timeframe (see get_analysis).
        indicators: Optional list of indicator keys to return, e.g.
            ["RSI", "MACD.macd", "close", "volume"]. Omit for all indicators.
    """
    return tv_get_indicators(
        symbol, exchange, screener=screener, interval=interval, indicators=indicators
    )


@mcp.tool()
def get_multiple_analysis(
    symbols: list[dict[str, str]],
    screener: str = "america",
    interval: str = "1d",
) -> dict[str, Any]:
    """Get technical summaries for several symbols at once.

    Args:
        symbols: List of {"symbol": ..., "exchange": ...} objects. Each item
            may also override "screener" and "interval".
        screener: Default screener for items that do not set their own.
        interval: Default interval for items that do not set their own.

    Returns a dict with a "results" list; any failures are reported per-symbol
    under "error" instead of aborting the whole call.
    """
    results: list[dict[str, Any]] = []
    for item in symbols:
        sym = item.get("symbol", "")
        exch = item.get("exchange", "")
        scr = item.get("screener", screener)
        itv = item.get("interval", interval)
        try:
            results.append(tv_get_analysis(sym, exch, screener=scr, interval=itv))
        except TradingViewError as exc:
            results.append(
                {"symbol": sym, "exchange": exch, "error": str(exc)}
            )
    return {"count": len(results), "results": results}


@mcp.tool()
def list_intervals() -> list[str]:
    """List the timeframe strings accepted by the analysis/indicator tools."""
    return list(INTERVALS)


def main() -> None:
    parser = argparse.ArgumentParser(description="TradingView MCP server")
    parser.add_argument(
        "--transport",
        choices=["stdio", "http", "sse"],
        default=os.environ.get("TRADINGVIEW_MCP_TRANSPORT", "stdio"),
        help="MCP transport (default: stdio, or $TRADINGVIEW_MCP_TRANSPORT).",
    )
    args = parser.parse_args()

    if args.transport == "http":
        host = os.environ.get("HOST", "0.0.0.0")
        port = int(os.environ.get("PORT", "8000"))
        if _MCP_MAJOR >= 2:
            # mcp 2.x takes host/port as run() kwargs.
            mcp.run(transport="streamable-http", host=host, port=port)
        else:
            # mcp 1.x reads them from the settings object.
            mcp.settings.host = host
            mcp.settings.port = port
            mcp.run(transport="streamable-http")
    else:
        mcp.run(transport=args.transport)


if __name__ == "__main__":
    main()
