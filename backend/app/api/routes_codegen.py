import io
import json
import zipfile
from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from app.core.backend_codegen import BackendCodeGen

router = APIRouter(prefix="/api/codegen", tags=["Code Generation"])


class ParameterSchema(BaseModel):
    name: str
    type: str = "string"
    required: bool = True
    default: Optional[str] = ""

class CodegenRequest(BaseModel):
    framework: str = Field(..., description="Target framework e.g. php_native, ci4, ci3, fastapi, python_native, express, elysia")
    query: str = Field(..., description="The verified SQL query string")
    endpoint_name: str = Field(default="get_records", description="Function / controller method name")
    route_path: str = Field(default="/api/v1/records", description="HTTP Route path")
    method: str = Field(default="GET", description="HTTP Method: GET, POST, PUT, DELETE")
    parameters: Optional[List[ParameterSchema]] = None
    db_type: str = Field(default="postgresql", description="Engine type: postgresql or sqlite or mysql")
    operation_type: Optional[str] = Field(default=None, description="CRUD operation: select, insert, update, or delete")
    operation_types: Optional[List[str]] = Field(default=None, description="Multiple CRUD operations: select, insert, update, delete")
    operation_queries: Optional[Dict[str, str]] = Field(default=None, description="Mapping of operation type (select, insert, update, delete) to specific SQL query")

@router.post("/backend/generate")
async def generate_backend_api(req: CodegenRequest):
    """
    Generates backend API source code files and isolated function snippet for the selected framework and operation(s).
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        detected_op = req.operation_type or (req.operation_types[0] if req.operation_types else BackendCodeGen.detect_operation_type(req.query))

        files = BackendCodeGen.generate_project(
            framework=req.framework,
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            db_type=req.db_type,
            operation_type=detected_op,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )

        snippet = BackendCodeGen.generate_function_snippet(
            framework=req.framework,
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            db_type=req.db_type,
            operation_type=detected_op,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )
        
        # Determine primary file for preview
        primary_file = list(files.keys())[0]
        for key in files.keys():
            if any(key.endswith(ext) for ext in [".php", ".py", ".js", ".ts"]):
                primary_file = key
                break

        return {
            "status": "success",
            "framework": req.framework,
            "operation_type": detected_op,
            "endpoint_name": req.endpoint_name,
            "route_path": req.route_path,
            "method": req.method,
            "primary_file": primary_file,
            "function_snippet": snippet,
            "files": files
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Generation failed: {str(e)}")

@router.post("/backend/snippet")
async def generate_snippet_only(req: CodegenRequest):
    """
    Returns only the isolated copy-pasteable function/method definition for existing projects.
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        detected_op = req.operation_type or (req.operation_types[0] if req.operation_types else BackendCodeGen.detect_operation_type(req.query))
        snippet = BackendCodeGen.generate_function_snippet(
            framework=req.framework,
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            db_type=req.db_type,
            operation_type=detected_op,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )
        return {
            "status": "success",
            "framework": req.framework,
            "operation_type": detected_op,
            "function_snippet": snippet
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Snippet generation failed: {str(e)}")

@router.post("/backend/export-zip")
async def export_backend_zip(req: CodegenRequest):
    """
    Builds and downloads a complete scaffolded project ZIP archive.
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        detected_op = req.operation_type or (req.operation_types[0] if req.operation_types else BackendCodeGen.detect_operation_type(req.query))
        files = BackendCodeGen.generate_project(
            framework=req.framework,
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            db_type=req.db_type,
            operation_type=detected_op,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )

        # Create in-memory zip
        mem_zip = io.BytesIO()
        with zipfile.ZipFile(mem_zip, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
            for filepath, content in files.items():
                zf.writestr(filepath, content)

        mem_zip.seek(0)
        clean_name = req.endpoint_name.strip().replace(" ", "_")
        ops_suffix = (
            f"multi_{len(req.operation_types)}"
            if req.operation_types and len(req.operation_types) > 1
            else detected_op
        )
        filename = f"{clean_name}_{ops_suffix}_{req.framework}.zip"

        return Response(
            content=mem_zip.getvalue(),
            media_type="application/zip",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "Access-Control-Expose-Headers": "Content-Disposition"
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Zip export failed: {str(e)}")

@router.post("/openapi/generate")
async def generate_openapi(req: CodegenRequest):
    """
    Generates standard OpenAPI 3.1.0 specification JSON from database query.
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        spec = BackendCodeGen.generate_openapi_spec(
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            db_type=req.db_type,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )
        return {
            "status": "success",
            "spec": spec
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAPI generation failed: {str(e)}")

@router.post("/postman/generate")
async def generate_postman(req: CodegenRequest):
    """
    Generates standard Postman v2.1.0 Collection JSON with automated assertions.
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        collection = BackendCodeGen.generate_postman_collection(
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )
        return {
            "status": "success",
            "collection": collection
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Postman collection generation failed: {str(e)}")

@router.post("/openapi/download")
async def download_openapi(req: CodegenRequest):
    """
    Downloads openapi.json file directly.
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        spec = BackendCodeGen.generate_openapi_spec(
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            db_type=req.db_type,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )
        content = json.dumps(spec, indent=2)
        clean_name = req.endpoint_name.strip().replace(" ", "_")
        filename = f"{clean_name}_openapi.json"
        return Response(
            content=content,
            media_type="application/json",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "Access-Control-Expose-Headers": "Content-Disposition"
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAPI download failed: {str(e)}")

@router.post("/postman/download")
async def download_postman(req: CodegenRequest):
    """
    Downloads postman_collection.json file directly.
    """
    try:
        params_dict = [p.model_dump() for p in req.parameters] if req.parameters else None
        col = BackendCodeGen.generate_postman_collection(
            query=req.query,
            endpoint_name=req.endpoint_name,
            route_path=req.route_path,
            method=req.method,
            parameters=params_dict,
            operation_types=req.operation_types,
            operation_queries=req.operation_queries
        )
        content = json.dumps(col, indent=2)
        clean_name = req.endpoint_name.strip().replace(" ", "_")
        filename = f"{clean_name}.postman_collection.json"
        return Response(
            content=content,
            media_type="application/json",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "Access-Control-Expose-Headers": "Content-Disposition"
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Postman download failed: {str(e)}")

