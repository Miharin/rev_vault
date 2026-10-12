import pytest
import sqlite3
from datetime import datetime, timezone, timedelta
from fastapi.testclient import TestClient
from app.main import app
from app.config import settings_manager, ConnectionConfig
from app.core.history_manager import HistoryManager, MutationRecord, history_manager

client = TestClient(app)

def test_history_manager_inverse_sql():
    hm = HistoryManager()

    # Test update inverse SQL for sqlite
    inv_update = hm.build_inverse_sql(
        table_name="products",
        operation="update",
        primary_keys={"id": 42},
        old_values={"price": 19.99, "status": "pending"},
        engine="sqlite"
    )
    assert "UPDATE `products` SET" in inv_update
    assert "`price` = 19.99" in inv_update
    assert "`status` = 'pending'" in inv_update
    assert "WHERE `id` = 42;" in inv_update

    # Test delete inverse SQL for postgres
    inv_delete = hm.build_inverse_sql(
        table_name="public.users",
        operation="delete",
        primary_keys={"id": 10},
        old_values={"id": 10, "username": "neo", "active": True},
        engine="postgres"
    )
    assert 'INSERT INTO "public"."users"' in inv_delete
    assert '"id", "username", "active"' in inv_delete
    assert "10, 'neo', TRUE" in inv_delete

def test_history_manager_pruning(tmp_path):
    test_hm = HistoryManager(data_dir=tmp_path)
    now = datetime.now(timezone.utc)

    records = []
    # Add 60 updates
    for i in range(60):
        ts = (now - timedelta(minutes=60 - i)).isoformat()
        records.append(
            MutationRecord(
                id=f"up_{i}",
                timestamp=ts,
                table_name="tbl",
                operation="update",
                primary_keys={"id": i},
                old_values={"v": i},
                inverse_sql=f"-- up {i}"
            )
        )

    # Add 60 deletes
    for i in range(60):
        ts = (now - timedelta(minutes=60 - i)).isoformat()
        records.append(
            MutationRecord(
                id=f"del_{i}",
                timestamp=ts,
                table_name="tbl",
                operation="delete",
                primary_keys={"id": i},
                old_values={"v": i},
                inverse_sql=f"-- del {i}"
            )
        )

    # Add 5 expired records (>365 days ago)
    old_ts = (now - timedelta(days=400)).isoformat()
    for i in range(5):
        records.append(
            MutationRecord(
                id=f"expired_{i}",
                timestamp=old_ts,
                table_name="tbl",
                operation="update",
                primary_keys={"id": 999},
                old_values={"v": 999},
                inverse_sql=f"-- expired {i}"
            )
        )

    pruned = test_hm.prune_records(records)
    updates_retained = [r for r in pruned if r.operation == "update"]
    deletes_retained = [r for r in pruned if r.operation == "delete"]

    # Exactly 50 updates and 50 deletes
    assert len(updates_retained) == 50
    assert len(deletes_retained) == 50
    # No expired records retained
    assert not any(r.id.startswith("expired_") for r in pruned)
    # Most recent 50 are retained (up_10 to up_59)
    assert updates_retained[0].id == "up_10"
    assert updates_retained[-1].id == "up_59"

@pytest.mark.asyncio
async def test_mutation_and_recovery_flow(tmp_path, monkeypatch):
    # Setup test sqlite db
    db_file = tmp_path / "test_store.db"
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("CREATE TABLE inventory (id INTEGER PRIMARY KEY, sku TEXT, quantity INTEGER, price REAL);")
    cur.execute("INSERT INTO inventory VALUES (1, 'SKU-001', 10, 49.99);")
    cur.execute("INSERT INTO inventory VALUES (2, 'SKU-002', 5, 99.50);")
    conn.commit()
    conn.close()

    # Configure connection and history manager mocks
    test_settings = type(settings_manager)(data_dir=tmp_path / "settings")
    conn_cfg = ConnectionConfig(
        id="test_sqlite_conn",
        name="Test SQLite",
        engine="sqlite",
        filepath=str(db_file),
        is_active=True
    )
    test_settings.save_connections([conn_cfg])

    test_history = HistoryManager(data_dir=tmp_path / "history")

    monkeypatch.setattr("app.api.routes_query.settings_manager", test_settings)
    monkeypatch.setattr("app.api.routes_query.history_manager", test_history)

    # 1. Update row 1 quantity and price
    update_payload = {
        "table_name": "inventory",
        "operation": "update",
        "primary_keys": {"id": 1},
        "updated_values": {"quantity": 25, "price": 39.99}
    }
    res = client.post("/api/query/row/mutate", json=update_payload)
    assert res.status_code == 200
    res_data = res.json()
    assert res_data["success"] is True
    assert res_data["affected_rows"] == 1
    update_history_id = res_data["history_id"]
    assert update_history_id is not None

    # Verify db has updated values
    chk = sqlite3.connect(str(db_file))
    row1 = chk.execute("SELECT quantity, price FROM inventory WHERE id = 1").fetchone()
    chk.close()
    assert row1 == (25, 39.99)

    # Verify history list contains the update
    hist_res = client.get("/api/query/history")
    assert hist_res.status_code == 200
    history_list = hist_res.json()
    assert len(history_list) == 1
    assert history_list[0]["id"] == update_history_id
    assert history_list[0]["operation"] == "update"
    assert history_list[0]["old_values"] == {"quantity": 10, "price": 49.99}
    assert history_list[0]["is_recovered"] is False

    # 2. Recover update row 1
    rec_res = client.post(f"/api/query/history/recover/{update_history_id}")
    assert rec_res.status_code == 200
    assert rec_res.json()["success"] is True

    # Verify db has been rolled back to original values!
    chk = sqlite3.connect(str(db_file))
    row1_rolled = chk.execute("SELECT quantity, price FROM inventory WHERE id = 1").fetchone()
    chk.close()
    assert row1_rolled == (10, 49.99)

    # Verify history record is marked as recovered
    hist_res2 = client.get("/api/query/history")
    assert hist_res2.json()[0]["is_recovered"] is True

    # 3. Delete row 2
    del_payload = {
        "table_name": "inventory",
        "operation": "delete",
        "primary_keys": {"id": 2}
    }
    del_res = client.post("/api/query/row/mutate", json=del_payload)
    assert del_res.status_code == 200
    del_data = del_res.json()
    assert del_data["success"] is True
    assert del_data["affected_rows"] == 1
    del_history_id = del_data["history_id"]
    assert del_history_id is not None

    # Verify row 2 is gone from db
    chk = sqlite3.connect(str(db_file))
    row2 = chk.execute("SELECT * FROM inventory WHERE id = 2").fetchone()
    chk.close()
    assert row2 is None

    # Verify history has 2 records now, newest is delete
    hist_res3 = client.get("/api/query/history")
    items = hist_res3.json()
    assert len(items) == 2
    assert items[0]["id"] == del_history_id
    assert items[0]["operation"] == "delete"
    assert items[0]["old_values"]["sku"] == "SKU-002"
    assert items[0]["old_values"]["quantity"] == 5
    assert items[0]["old_values"]["price"] == 99.50

    # 4. Recover deleted row 2
    rec_del_res = client.post(f"/api/query/history/recover/{del_history_id}")
    assert rec_del_res.status_code == 200
    assert rec_del_res.json()["success"] is True

    # Verify row 2 is restored in database!
    chk = sqlite3.connect(str(db_file))
    row2_restored = chk.execute("SELECT id, sku, quantity, price FROM inventory WHERE id = 2").fetchone()
    chk.close()
    assert row2_restored == (2, "SKU-002", 5, 99.50)

    # 5. Insert new row (id=3)
    ins_payload = {
        "table_name": "inventory",
        "operation": "insert",
        "updated_values": {"sku": "SKU-003", "quantity": 100, "price": 12.50}
    }
    ins_res = client.post("/api/query/row/mutate", json=ins_payload)
    assert ins_res.status_code == 200
    ins_data = ins_res.json()
    assert ins_data["success"] is True
    assert ins_data["affected_rows"] == 1

    # Verify row 3 was inserted in database
    chk = sqlite3.connect(str(db_file))
    row3 = chk.execute("SELECT sku, quantity, price FROM inventory WHERE sku = 'SKU-003'").fetchone()
    chk.close()
    assert row3 == ("SKU-003", 100, 12.50)
