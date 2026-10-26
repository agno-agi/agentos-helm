"""Reach OS Manager through MCP and, when configured, Slack."""

import re
from os import getenv
from urllib.parse import urlparse

from agno.os import AgentOS, AgentOSBuiltinAuth, MCPConfig


def mcp_auth(agentos_url: str) -> AgentOSBuiltinAuth | None:
    """Enable MCP OAuth when the MCP_CONNECT_SECRET is provided."""
    secret = getenv("MCP_CONNECT_SECRET")
    if not secret:
        return None
    return AgentOSBuiltinAuth(url=agentos_url, secret=secret)


# Plain hostnames only: no wildcard, port, scheme or trailing dot. The framework itself would read
# "*.x" as a wildcard and strip anything after a colon, so malformed entries must fail here.
_HOSTNAME = re.compile(r"(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))*")


def mcp_allowed_hosts() -> list[str]:
    """Hostnames /mcp answers to besides localhost: the AGENTOS_URL host plus MCP_ALLOWED_HOSTS."""
    hosts = [urlparse(getenv("AGENTOS_URL", "http://127.0.0.1:8000")).hostname or "localhost"]
    for entry in (getenv("MCP_ALLOWED_HOSTS") or "").split(","):
        host = entry.strip().lower()
        if not host:
            continue
        if not _HOSTNAME.fullmatch(host):
            raise ValueError(
                f"MCP_ALLOWED_HOSTS entry {entry.strip()!r} must be a plain hostname, not a wildcard, port or URL."
            )
        hosts.append(host)
    return list(dict.fromkeys(hosts))


def attach_interfaces(agent_os: AgentOS) -> None:
    """Publish agno alongside the built-in MCP tools; optionally attach Slack."""
    manager = agent_os.manager
    if manager is None:
        raise RuntimeError("OS Manager must be configured before attaching interfaces.")
    agent_os.mcp = MCPConfig(
        default_tools=True,
        # Without this, a request addressed to the public or in-cluster Service hostname is rejected as an
        # invalid host; localhost stays allowed.
        allowed_hosts=mcp_allowed_hosts(),
        tools=[
            manager.as_tool(
                name="agno",
                title="Agno",
                description="Talk to OS Manager of this AgentOS. Pass session_id back to continue the conversation.",
            )
        ],
    )
    token, secret = getenv("SLACK_BOT_TOKEN"), getenv("SLACK_SIGNING_SECRET")
    if token and secret:
        from agno.os.interfaces.slack import Slack

        agent_os.interfaces.append(
            Slack(
                team=manager,
                token=token,
                streaming=True,
                signing_secret=secret,
                resolve_user_identity=True,
                loading_text="Pulling the thread...",
            )
        )
