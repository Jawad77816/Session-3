# TradingView MCP — Custom Connector

A custom [Model Context Protocol](https://modelcontextprotocol.io) server that
exposes **TradingView technical-analysis data** to Claude. Add it as a
**Custom Connector** in claude.ai, or run it locally in Claude Desktop / Claude
Code.

> **Why "custom"?** TradingView does not publish an official REST API for
> account data, so there is no ready-made TradingView connector in the Claude
> directory. This server wraps the same public endpoints TradingView's own web
> app uses (technical-analysis scanner + symbol search) via the maintained
> [`tradingview-ta`](https://pypi.org/project/tradingview-ta/) library. It needs
> **no TradingView login** and reads only publicly available market data.
> Respect TradingView's Terms of Service and rate limits when you deploy it.

## Tools

| Tool | What it does |
|------|--------------|
| `search_symbol` | Resolve a company name / ticker to TradingView symbol + exchange |
| `get_analysis` | Buy / Sell / Neutral technical summary (oscillators + moving averages) |
| `get_indicators` | Raw indicator values — RSI, MACD, close, volume, EMAs, … |
| `get_multiple_analysis` | Technical summaries for many symbols in one call |
| `list_intervals` | The timeframe strings the tools accept |

Symbols are addressed by `symbol` + `exchange` + `screener`
(e.g. `AAPL` / `NASDAQ` / `america`, `BTCUSDT` / `BINANCE` / `crypto`,
`EURUSD` / `FX_IDC` / `forex`). Timeframes: `1m 5m 15m 30m 1h 2h 4h 1d 1W 1M`.

## Quick start (local — Claude Desktop / Claude Code)

```bash
cd tradingview-mcp
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m tradingview_mcp.server          # stdio transport (default)
```

Register it with Claude Code:

```bash
claude mcp add tradingview -- python -m tradingview_mcp.server
```

Or add to a Claude Desktop `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tradingview": {
      "command": "python",
      "args": ["-m", "tradingview_mcp.server"],
      "cwd": "/absolute/path/to/tradingview-mcp"
    }
  }
}
```

## Deploy as a claude.ai Custom Connector

claude.ai custom connectors talk **streamable-HTTP over HTTPS**, so the server
must be reachable at a public `https://…/mcp` URL.

1. Run the server in HTTP mode (binds `0.0.0.0`, path `/mcp`):

   ```bash
   pip install -r requirements.txt
   TRADINGVIEW_MCP_TRANSPORT=http PORT=8000 python -m tradingview_mcp.server
   # or: python -m tradingview_mcp.server --transport http
   ```

   Or with Docker:

   ```bash
   docker build -t tradingview-mcp .
   docker run -p 8000:8000 tradingview-mcp
   ```

2. Put it behind HTTPS — deploy to any host that gives you a public TLS URL
   (Render, Railway, Fly.io, Cloud Run, a reverse proxy with a cert, an
   ngrok/Cloudflare tunnel for testing, …). The MCP endpoint is
   `https://<your-host>/mcp`.

3. In **claude.ai → Settings → Connectors → Add custom connector**, paste the
   `https://<your-host>/mcp` URL and save. The five tools above then appear in
   chat.

> This server is **authless** — anyone with the URL can call it. Keep the URL
> private, or put your own auth/proxy in front before exposing it publicly.

### Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `TRADINGVIEW_MCP_TRANSPORT` | `stdio` | `stdio`, `http`, or `sse` |
| `HOST` | `0.0.0.0` | Bind address (HTTP mode) |
| `PORT` | `8000` | Bind port (HTTP mode) |

## Example prompts

- "Search TradingView for Nvidia and give me the 1-day technical summary."
- "What's the 4-hour recommendation for BTCUSDT on Binance?"
- "Compare the daily analysis for AAPL, MSFT and GOOGL on NASDAQ."
- "Get the RSI and MACD for TSLA on the 1-hour timeframe."

## Notes & limitations

- Data is TradingView's computed technical analysis, **not** a live order feed
  or your personal watchlist/alerts (those require a logged-in session and are
  out of scope for a public, TOS-friendly connector).
- Requires network egress to `*.tradingview.com`. In sandboxes that block it,
  the tools raise a clear `TradingViewError`.
- Compatible with `mcp` SDK **1.x and 2.x** (the server auto-detects which is
  installed).
