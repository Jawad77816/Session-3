FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY tradingview_mcp ./tradingview_mcp
COPY pyproject.toml README.md ./

# claude.ai custom connectors use streamable-HTTP.
ENV TRADINGVIEW_MCP_TRANSPORT=http \
    HOST=0.0.0.0 \
    PORT=8000

EXPOSE 8000

CMD ["python", "-m", "tradingview_mcp.server"]
