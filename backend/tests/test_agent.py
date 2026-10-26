import pytest
from app.core.agent_service import agent_service, DEFAULT_MODEL, DEFAULT_OLLAMA_URL
from app.api.routes_agent import AgentChatRequest, AgentChatResponse


@pytest.mark.asyncio
async def test_agent_status_structure():
    status = await agent_service.check_status(ollama_url=DEFAULT_OLLAMA_URL)
    assert "online" in status
    assert "models" in status
    assert status["default_model"] == DEFAULT_MODEL
    assert isinstance(status["models"], list)


@pytest.mark.asyncio
async def test_agent_tool_execution_safety():
    # Attempt dangerous destructive statement via execute_safe_query tool
    output, success = await agent_service.execute_tool(
        "execute_safe_query",
        {"sql": "DROP TABLE users;"}
    )
    assert success is False
    assert "SECURITY GUARDRAIL BLOCKED" in output
