#!/usr/bin/env python3
"""
RevVault AI CLI Agent (Ollama + RevVault MCP)
Standalone terminal agent bridging local Ollama with RevVault Model Context Protocol (MCP) server.
"""

import asyncio
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
except ImportError:
    print("❌ 'mcp' package is missing. Install via: pip install mcp")
    sys.exit(1)

DEFAULT_MODEL = "gemma4:e4b"
DEFAULT_OLLAMA_URL = "http://localhost:11434"

SYSTEM_PROMPT = (
    "You are the RevVault AI Database Assistant, developed by Relva. "
    "Your objective is to assist developers with database exploration, schema inspection, "
    "SQL query construction, performance optimization, and safe data exploration. "
    "You have access to read-only database tools to inspect tables and execute safe queries. "
    "Be precise, objective, and professional. "
    "Format all SQL queries within ```sql markdown code blocks. "
    "Never attempt destructive operations (DROP, DELETE, TRUNCATE, ALTER, UPDATE, INSERT); "
    "only read-only analysis is permitted."
)


class RevVaultStandaloneAgent:
    """
    Autonomous terminal agent bridging local Ollama with RevVault Model Context Protocol (MCP) server.
    """

    def __init__(
        self,
        model: str = DEFAULT_MODEL,
        ollama_url: str = DEFAULT_OLLAMA_URL,
        revvault_dir: Optional[str] = None,
    ):
        self.model: str = model
        self.ollama_url: str = ollama_url.rstrip("/")

        repo_root = Path(__file__).resolve().parent.parent
        self.python_path: str = str(repo_root / "backend" / ".venv" / "bin" / "python")
        if not Path(self.python_path).exists():
            self.python_path = sys.executable

        self.mcp_script: str = str(
            repo_root / "backend" / "run_mcp_stdio.py"
        )
        self.revvault_dir: str = (
            revvault_dir
            or os.environ.get("REVVAULT_DIR")
            or str(Path.home() / ".revvault")
        )

        self.history: List[Dict[str, Any]] = []

    def call_ollama(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """
        Sends conversational messages and MCP tools schema to the local Ollama daemon.
        """
        payload: Dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {
                "num_ctx": 8192,
            },
        }
        if tools:
            payload["tools"] = tools

        req_data: bytes = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{self.ollama_url}/api/chat",
            data=req_data,
            headers={"Content-Type": "application/json"},
        )

        try:
            with urllib.request.urlopen(request, timeout=120) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as err:
            print(f"\n❌ Could not connect to Ollama: {err}")
            print(f"👉 Ensure Ollama is running (`ollama serve`).")
            sys.exit(1)

    async def run_interactive_session(self) -> None:
        """
        Initializes the MCP connection and launches the interactive terminal agent REPL.
        """
        print("\033[1;36m" + "=" * 65)
        print("  REVVAULT AI STANDALONE AGENT (OLLAMA + MCP)  ")
        print("=" * 65 + "\033[0m")
        print(f"  • Model:        \033[1;32m{self.model}\033[0m")
        print(f"  • Ollama URL:   {self.ollama_url}")
        print(f"  • RevVault MCP: {self.mcp_script}")
        print("\033[1;36m" + "-" * 65 + "\033[0m\n")

        # Configure stdio subprocess for RevVault MCP
        server_params = StdioServerParameters(
            command=self.python_path,
            args=[self.mcp_script],
            env={"REVVAULT_DIR": self.revvault_dir},
        )

        print("Connecting to RevVault MCP server...", end=" ", flush=True)
        async with stdio_client(server_params) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                print("\033[1;32m[CONNECTED]\033[0m")

                # Discover and convert tools
                tools_response = await session.list_tools()
                ollama_tools: List[Dict[str, Any]] = [
                    {
                        "type": "function",
                        "function": {
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": tool.input_schema,
                        },
                    }
                    for tool in tools_response.tools
                ]

                print(
                    f"Discovered {len(ollama_tools)} RevVault tools: "
                    + ", ".join([f"\033[1;36m{t['function']['name']}\033[0m" for t in ollama_tools])
                )
                print("\nType your question or query below (or type \033[1;31mexit\033[0m to quit):\n")

                if not self.history:
                    self.history.append({
                        "role": "system",
                        "content": SYSTEM_PROMPT,
                    })

                while True:
                    try:
                        prompt: str = input("\033[1;33mUser > \033[0m").strip()
                    except (KeyboardInterrupt, EOFError):
                        print("\nSession ended.")
                        break

                    if not prompt:
                        continue
                    if prompt.lower() in ("exit", "quit", "q"):
                        print("\nExiting RevVault AI.")
                        break

                    # Append user message to history
                    self.history.append({"role": "user", "content": prompt})

                    print("\n\033[1;34m*Querying database and reasoning...*\033[0m")

                    # Agent reasoning and tool execution loop
                    keep_looping: bool = True
                    iterations: int = 0
                    max_iterations: int = 5

                    while keep_looping and iterations < max_iterations:
                        iterations += 1
                        response_payload = self.call_ollama(
                            self.history, tools=ollama_tools
                        )
                        msg = response_payload.get("message", {})
                        self.history.append(msg)

                        tool_calls = msg.get("tool_calls", [])
                        if not tool_calls:
                            # Final answer reached
                            content: str = msg.get("content", "")
                            print(f"\n\033[1;36mRevVault AI >\033[0m {content}\n")
                            keep_looping = False
                        else:
                            # Execute each tool call via RevVault MCP
                            for call in tool_calls:
                                fn_name: str = call["function"]["name"]
                                fn_args: Dict[str, Any] = call["function"].get("arguments", {})

                                print(
                                    f"  \033[1;34m⚡ RevVault Tool Triggered:\033[0m \033[1;36m{fn_name}\033[0m({json.dumps(fn_args)})"
                                )

                                try:
                                    exec_result = await session.call_tool(
                                        fn_name, fn_args
                                    )
                                    tool_output: str = "\n".join(
                                        [c.text for c in exec_result.content if hasattr(c, "text")]
                                    )
                                except Exception as call_err:
                                    tool_output = f"Tool execution failed: {call_err}"

                                # Feed tool result back to Ollama
                                self.history.append(
                                    {
                                        "role": "tool",
                                        "content": tool_output,
                                    }
                                )


def main() -> None:
    model_name: str = DEFAULT_MODEL
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        model_name = sys.argv[1]

    agent = RevVaultStandaloneAgent(model=model_name)
    asyncio.run(agent.run_interactive_session())


if __name__ == "__main__":
    main()
