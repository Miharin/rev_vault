import pytest
import io
import zipfile
from fastapi.testclient import TestClient
from app.main import app
from app.core.backend_codegen import BackendCodeGen

client = TestClient(app)

def test_extract_parameters():
    query = "SELECT * FROM users WHERE id = :user_id AND status = :status AND org_id = $1 AND role = ?;"
    params = BackendCodeGen.extract_parameters(query)
    assert "user_id" in params
    assert "status" in params
    assert "param_1" in params

def test_generate_all_frameworks():
    query = "SELECT id, username, email FROM users WHERE id = :id AND status = :status;"
    frameworks = ["php_native", "ci4", "ci3", "fastapi", "python_native", "express", "elysia"]
    
    for fw in frameworks:
        files = BackendCodeGen.generate_project(
            framework=fw,
            query=query,
            endpoint_name="get_active_users",
            route_path="/api/v1/users",
            method="GET"
        )
        assert len(files) >= 2, f"Framework {fw} should return at least 2 files"
        assert "README.md" in files, f"Framework {fw} should have README.md"
        
        # Verify query content is preserved
        combined_code = "\n".join(files.values())
        assert "SELECT id, username, email FROM users" in combined_code

def test_api_generate_endpoint():
    payload = {
        "framework": "fastapi",
        "query": "SELECT * FROM orders WHERE user_id = :user_id;",
        "endpoint_name": "get_orders_by_user",
        "route_path": "/api/v1/orders",
        "method": "GET",
        "parameters": [
            {"name": "user_id", "type": "int", "required": True, "default": "1"}
        ]
    }
    res = client.post("/api/codegen/backend/generate", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert data["framework"] == "fastapi"
    assert "main.py" in data["files"]
    assert "get_orders_by_user" in data["files"]["main.py"]

def test_api_export_zip_endpoint():
    payload = {
        "framework": "express",
        "query": "SELECT * FROM products WHERE category = :cat;",
        "endpoint_name": "get_products",
        "route_path": "/api/products",
        "method": "GET"
    }
    res = client.post("/api/codegen/backend/export-zip", json=payload)
    assert res.status_code == 200
    assert res.headers["content-type"] == "application/zip"
    assert "attachment; filename=\"get_products_select_express.zip\"" in res.headers["content-disposition"]
    
    # Verify valid zip archive
    zip_bytes = io.BytesIO(res.content)
    with zipfile.ZipFile(zip_bytes, "r") as zf:
        namelist = zf.namelist()
        assert "server.js" in namelist
        assert "package.json" in namelist
        assert "README.md" in namelist

def test_detect_operation_type_and_crud_snippets():
    assert BackendCodeGen.detect_operation_type("SELECT * FROM users") == "select"
    assert BackendCodeGen.detect_operation_type("INSERT INTO users (name) VALUES (:name)") == "insert"
    assert BackendCodeGen.detect_operation_type("UPDATE users SET name = :name WHERE id = :id") == "update"
    assert BackendCodeGen.detect_operation_type("DELETE FROM users WHERE id = :id") == "delete"

    # Test function snippets across frameworks
    insert_sql = "INSERT INTO users (username, email) VALUES (:username, :email);"
    snippet_php = BackendCodeGen.generate_function_snippet(
        framework="php_native",
        query=insert_sql,
        endpoint_name="insert_user",
        operation_type="insert"
    )
    assert "function insert_user(" in snippet_php
    assert "INSERT INTO users" in snippet_php
    assert "lastInsertId" in snippet_php

    snippet_ci4 = BackendCodeGen.generate_function_snippet(
        framework="ci4",
        query=insert_sql,
        endpoint_name="insert_user",
        operation_type="insert"
    )
    assert "public function insert_user(" in snippet_ci4
    assert "insertID" in snippet_ci4

    snippet_fastapi = BackendCodeGen.generate_function_snippet(
        framework="fastapi",
        query=insert_sql,
        endpoint_name="create_user",
        method="POST",
        operation_type="insert"
    )
    assert "@app.post" in snippet_fastapi
    assert "async def create_user" in snippet_fastapi

def test_api_snippet_endpoint():
    payload = {
        "framework": "php_native",
        "query": "UPDATE products SET price = :price WHERE id = :id;",
        "endpoint_name": "update_product_price",
        "route_path": "/api/products/price",
        "method": "PUT",
        "operation_type": "update"
    }
    res = client.post("/api/codegen/backend/snippet", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert data["operation_type"] == "update"
    assert "function update_product_price" in data["function_snippet"]

def test_multi_operation_codegen_and_zip():
    # Multi-choice operations: select and insert
    query = "SELECT id, name FROM users WHERE id = :id;"
    snippet_multi = BackendCodeGen.generate_function_snippet(
        framework="fastapi",
        query=query,
        endpoint_name="manage_users",
        operation_types=["select", "insert"]
    )
    assert "1. SELECT Operation" in snippet_multi
    assert "2. INSERT Operation" in snippet_multi
    assert "@app.get" in snippet_multi
    assert "@app.post" in snippet_multi

    # Multi-choice export ZIP
    payload = {
        "framework": "fastapi",
        "query": query,
        "endpoint_name": "users_api",
        "route_path": "/api/v1/users",
        "operation_types": ["select", "insert", "update", "delete"]
    }
    res = client.post("/api/codegen/backend/export-zip", json=payload)
    assert res.status_code == 200
    assert "users_api_multi_4_fastapi.zip" in res.headers["content-disposition"]
    zip_bytes = io.BytesIO(res.content)
    with zipfile.ZipFile(zip_bytes, "r") as zf:
        assert "main.py" in zf.namelist()

def test_tailored_per_operation_queries():
    custom_queries = {
        "select": "SELECT id, full_name, email FROM accounts WHERE is_active = true;",
        "insert": "INSERT INTO accounts (full_name, email) VALUES (:full_name, :email);",
        "update": "UPDATE accounts SET full_name = :full_name WHERE id = :id;",
        "delete": "DELETE FROM accounts WHERE id = :id AND is_system = false;"
    }

    # 1. Test function snippet generator
    snippet = BackendCodeGen.generate_function_snippet(
        framework="fastapi",
        query="SELECT * FROM fallback;",
        endpoint_name="manage_accounts",
        operation_types=["select", "insert", "update", "delete"],
        operation_queries=custom_queries
    )
    assert "SELECT id, full_name, email FROM accounts WHERE is_active = true;" in snippet
    assert "INSERT INTO accounts (full_name, email) VALUES (:full_name, :email);" in snippet
    assert "UPDATE accounts SET full_name = :full_name WHERE id = :id;" in snippet
    assert "DELETE FROM accounts WHERE id = :id AND is_system = false;" in snippet

    # 2. Test /api/codegen/backend/generate endpoint
    payload = {
        "framework": "fastapi",
        "query": "SELECT * FROM fallback;",
        "endpoint_name": "manage_accounts",
        "operation_types": ["select", "insert"],
        "operation_queries": custom_queries
    }
    res = client.post("/api/codegen/backend/generate", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert "SELECT id, full_name, email FROM accounts WHERE is_active = true;" in data["function_snippet"]
    assert "INSERT INTO accounts (full_name, email) VALUES (:full_name, :email);" in data["function_snippet"]

    # 3. Test /api/codegen/backend/export-zip endpoint
    payload_zip = {
        "framework": "express",
        "query": "SELECT * FROM fallback;",
        "endpoint_name": "accounts_api",
        "operation_types": ["select", "insert", "update", "delete"],
        "operation_queries": custom_queries
    }
    res_zip = client.post("/api/codegen/backend/export-zip", json=payload_zip)
    assert res_zip.status_code == 200
    assert "accounts_api_multi_4_express.zip" in res_zip.headers["content-disposition"]

def test_openapi_and_postman_codegen():
    payload = {
        "framework": "fastapi",
        "query": "SELECT id, email FROM users WHERE id = :user_id;",
        "endpoint_name": "get_user_profile",
        "route_path": "/api/v1/users",
        "method": "GET",
        "parameters": [{"name": "user_id", "type": "int", "required": True, "default": "1"}],
        "operation_types": ["select", "insert"]
    }

    # 1. Test OpenAPI generation
    res_oa = client.post("/api/codegen/openapi/generate", json=payload)
    assert res_oa.status_code == 200
    data_oa = res_oa.json()
    assert data_oa["status"] == "success"
    spec = data_oa["spec"]
    assert spec["openapi"] == "3.1.0"
    assert "/api/v1/users" in spec["paths"]
    assert "get" in spec["paths"]["/api/v1/users"]
    assert "post" in spec["paths"]["/api/v1/users"]
    assert spec["paths"]["/api/v1/users"]["get"]["parameters"][0]["name"] == "user_id"

    # 2. Test Postman generation
    res_pm = client.post("/api/codegen/postman/generate", json=payload)
    assert res_pm.status_code == 200
    data_pm = res_pm.json()
    assert data_pm["status"] == "success"
    collection = data_pm["collection"]
    assert "collection.json" in collection["info"]["schema"]
    assert len(collection["item"]) == 2
    assert collection["item"][0]["name"].startswith("SELECT")
    assert collection["item"][1]["name"].startswith("INSERT")
    assert len(collection["item"][0]["event"][0]["script"]["exec"]) > 0




