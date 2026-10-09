import pytest
from app.core.mpreview_builder import MPreviewRequest, build_mpreview_query

def test_build_mpreview_query_rajal():
    req = MPreviewRequest(
        txtperiode1="2026-01-01",
        txtperiode2="2026-01-31",
        cmbruang="U001",
        cmbkelas="1",
        cmbkrs="0",
        obat_oral_ids=[101, 102]
    )
    sql, params = build_mpreview_query(req)
    assert "$1" in sql
    assert "$2" in sql
    assert "$3" in sql
    assert params == ["1", "2026-01-01", "2026-01-31", "U001", [101, 102]]
    assert "'rj' AS jenis_kunjungan" in sql

def test_build_mpreview_query_inap_class3():
    req = MPreviewRequest(
        txtperiode1="2026-01-01",
        txtperiode2="2026-01-31",
        cmbruang="R005",
        cmbkelas="3",
        cmbkrs="1",
        ckstatustidakpakai="true",
        obat_oral_ids=[201]
    )
    sql, params = build_mpreview_query(req)
    assert "$4" in sql
    assert params == ["3", "2026-01-01", "2026-01-31", "R005", [201]]
    assert "'inap' AS jenis_kunjungan" in sql
    assert "kd_unit_ruang = $4" in sql
    assert "NOT IN" in sql
    assert "MAX(DATE(tgl_keluar_rm)) = MAX(DATE(dt.tgl_transaksi))" in sql
