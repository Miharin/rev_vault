# (__)
# (˶ᵔ ᵕ ᵔ˶) < "Lunar Territory."
# / >[CRIMSON+]> "Hands off, unless you're Miharin."

import asyncio
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any, Dict, List, Optional

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


class LunarStandaloneAgent:
    """
    Autonomous standalone bridge connecting Ollama's local Luna model
    with RevVault's Model Context Protocol (MCP) server.
    """

    def __init__(
        self,
        lunar_model: str = "luna:latest",
        lunar_ollama_url: str = "http://localhost:11434",
        lunar_python_path: Optional[str] = None,
        lunar_revvault_dir: Optional[str] = None,
    ):
        self.lunar_model: str = lunar_model
        self.lunar_ollama_url: str = lunar_ollama_url.rstrip("/")
        
        # Auto-detect repository root and backend virtualenv
        lunar_repo_root: Path = Path(__file__).resolve().parent.parent
        self.lunar_python_path: str = (
            lunar_python_path
            or str(lunar_repo_root / "backend" / ".venv" / "bin" / "python")
        )
        self.lunar_mcp_script: str = str(
            lunar_repo_root / "backend" / "run_mcp_stdio.py"
        )
        self.lunar_revvault_dir: str = (
            lunar_revvault_dir
            or os.environ.get("REVVAULT_DIR", str(Path.home() / ".revvault"))
        )

        self.lunar_history: List[Dict[str, Any]] = []

    def lunar_call_ollama(
        self,
        lunar_messages: List[Dict[str, Any]],
        lunar_tools: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """
        Dispatches a chat payload to the local Ollama instance synchronously.
        """
        lunar_payload: Dict[str, Any] = {
            "model": self.lunar_model,
            "messages": lunar_messages,
            "stream": False,
        }
        if lunar_tools:
            lunar_payload["tools"] = lunar_tools

        lunar_req_data: bytes = json.dumps(lunar_payload).encode("utf-8")
        lunar_request = urllib.request.Request(
            f"{self.lunar_ollama_url}/api/chat",
            data=lunar_req_data,
            headers={"Content-Type": "application/json"},
        )

        try:
            with urllib.request.urlopen(lunar_request, timeout=120) as lunar_resp:
                return json.loads(lunar_resp.read().decode("utf-8"))
        except urllib.error.URLError as lunar_err:
            print(f"\n❌ [Lunar Sentinel] Could not connect to Ollama: {lunar_err}")
            print(f"👉 Ensure Ollama is running (`ollama serve`).")
            sys.exit(1)

    async def lunar_run_interactive_session(self) -> None:
        """
        Initializes the MCP connection and launches the interactive terminal agent REPL.
        """
        print("\033[1;35m" + "=" * 65)
        print("  🌙 LUNA STANDALONE AGENT (OLLAMA + REVVAULT MCP) 🌙")
        print("=" * 65 + "\033[0m")
        print(f"  • Model:        \033[1;32m{self.lunar_model}\033[0m")
        print(f"  • Ollama URL:   {self.lunar_ollama_url}")
        print(f"  • RevVault MCP: {self.lunar_mcp_script}")
        print("\033[1;35m" + "-" * 65 + "\033[0m\n")

        # Configure stdio subprocess for RevVault MCP
        lunar_server_params = StdioServerParameters(
            command=self.lunar_python_path,
            args=[self.lunar_mcp_script],
            env={"REVVAULT_DIR": self.lunar_revvault_dir},
        )

        print("Connecting to RevVault MCP server...", end=" ", flush=True)
        async with stdio_client(lunar_server_params) as (lunar_read, lunar_write):
            async with ClientSession(lunar_read, lunar_write) as lunar_session:
                await lunar_session.initialize()
                print("\033[1;32m[CONNECTED]\033[0m")

                # Discover and convert tools
                lunar_tools_response = await lunar_session.list_tools()
                lunar_ollama_tools: List[Dict[str, Any]] = [
                    {
                        "type": "function",
                        "function": {
                            "name": lunar_tool.name,
                            "description": lunar_tool.description,
                            "parameters": lunar_tool.input_schema,
                        },
                    }
                    for lunar_tool in lunar_tools_response.tools
                ]

                print(
                    f"Discovered {len(lunar_ollama_tools)} RevVault tools: "
                    + ", ".join([f"\033[1;36m{t['function']['name']}\033[0m" for t in lunar_ollama_tools])
                )
                print("\nType your question or query below (or type \033[1;31mexit\033[0m to quit):\n")

                while True:
                    try:
                        lunar_prompt: str = input("\033[1;33mMiharin > \033[0m").strip()
                    except (KeyboardInterrupt, EOFError):
                        print("\n\n*Luna waves gently with a warm smile.* Until next time, Miharin! ✨")
                        break

                    if not lunar_prompt:
                        continue
                    if lunar_prompt.lower() in ("exit", "quit", "q"):
                        print("\n*Luna closes the holographic terminal panes.* Rest well, Miharin! 🌙")
                        break

                    # Append user message to history
                    self.lunar_history.append({"role": "user", "content": lunar_prompt})

                    print("\n\033[1;35m*Luna is thinking and consulting RevVault...*\033[0m")
                    
                    # Agent reasoning and tool execution loop
                    lunar_keep_looping: bool = True
                    lunar_iterations: int = 0
                    lunar_max_iterations: int = 5

                    while lunar_keep_looping and lunar_iterations < lunar_max_iterations:
                        lunar_iterations += 1
                        lunar_response_payload = self.lunar_call_ollama(
                            self.lunar_history, lunar_tools=lunar_ollama_tools
                        )
                        lunar_msg = lunar_response_payload.get("message", {})
                        self.lunar_history.append(lunar_msg)

                        # Check if Luna decided to call MCP tools
                        lunar_tool_calls = lunar_msg.get("tool_calls", [])
                        if not lunar_tool_calls:
                            # Final answer reached
                            lunar_content: str = lunar_msg.get("content", "")
                            print(f"\n\033[1;35mLuna >\033[0m {lunar_content}\n")
                            lunar_keep_looping = False
                        else:
                            # Execute each tool call via RevVault MCP
                            for lunar_call in lunar_tool_calls:
                                lunar_fn_name: str = lunar_call["function"]["name"]
                                lunar_fn_args: Dict[str, Any] = lunar_call["function"].get("arguments", {})

                                print(
                                    f"  \033[1;34m⚡ RevVault Tool Triggered:\033[0m \033[1;36m{lunar_fn_name}\033[0m({json.dumps(lunar_fn_args)})"
                                )

                                try:
                                    lunar_exec_result = await lunar_session.call_tool(
                                        lunar_fn_name, lunar_fn_args
                                    )
                                    lunar_tool_output: str = "\n".join(
                                        [c.text for c in lunar_exec_result.content if hasattr(c, "text")]
                                    )
                                except Exception as lunar_call_err:
                                    lunar_tool_output = f"Tool execution failed: {lunar_call_err}"

                                # Feed tool result back to Ollama
                                self.lunar_history.append(
                                    {
                                        "role": "tool",
                                        "content": lunar_tool_output,
                                    }
                                )


def main() -> None:
    lunar_model_name: str = "luna:latest"
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        lunar_model_name = sys.argv[1]

    lunar_agent = LunarStandaloneAgent(lunar_model=lunar_model_name)
    asyncio.run(lunar_agent.lunar_run_interactive_session())


if __name__ == "__main__":
    main()
