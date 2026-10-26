from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from app.core.agent_service import agent_service, DEFAULT_MODEL, DEFAULT_OLLAMA_URL

router = APIRouter(prefix="/api/agent", tags=["AI Agent"])


class AgentChatRequest(BaseModel):
    message: str = Field(..., description="User message or prompt")
    model: str = Field(default=DEFAULT_MODEL, description="Target Ollama model")
    history: List[Dict[str, Any]] = Field(default=[], description="Previous conversation messages")
    ollama_url: Optional[str] = Field(default=DEFAULT_OLLAMA_URL, description="Ollama API base URL")


class ToolExecutionDto(BaseModel):
    name: str
    arguments: Dict[str, Any]
    output_preview: str
    success: bool


class AgentChatResponse(BaseModel):
    reply: str
    tool_executions: List[ToolExecutionDto]
    history: List[Dict[str, Any]]
    error: Optional[str] = None


@router.get("/status")
async def get_agent_status(url: str = Query(default=DEFAULT_OLLAMA_URL)):
    """
    Check if local Ollama daemon is reachable and list installed models.
    """
    return await agent_service.check_status(ollama_url=url)


@router.post("/chat", response_model=AgentChatResponse)
async def chat_with_agent(req: AgentChatRequest):
    """
    Dispatch user query to the in-app AI Database Assistant.
    Executes tool calls against RevVault's AST guardrails and active database.
    """
    res = await agent_service.chat(
        user_message=req.message,
        conversation_history=req.history,
        model=req.model,
        ollama_url=req.ollama_url or DEFAULT_OLLAMA_URL
    )

    return AgentChatResponse(
        reply=res.get("content", ""),
        tool_executions=res.get("tool_executions", []),
        history=res.get("history", []),
        error=res.get("error")
    )
