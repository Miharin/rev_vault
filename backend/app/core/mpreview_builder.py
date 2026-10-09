from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
import asyncpg

class MPreviewRequest(BaseModel):
    txtperiode1: str = Field(..., description="Start date (YYYY-MM-DD)")
    txtperiode2: str = Field(..., description="End date (YYYY-MM-DD)")
    cmbruang: Optional[str] = Field(None, description="Room / Unit ID filter")
    namaruang: Optional[str] = Field(None, description="Room name")
    ckstatustidakpakai: Optional[str] = Field("false", description="Exclude unused status flag ('true'/'false')")
    cmbkelas: str = Field(..., description="Instalasi / Class ID ('1' for Rajal, others for Inap)")
    cmbkrs: Optional[str] = Field("0", description="KRS status flag ('1' = matched KRS date, '0' = non-matched)")
    obat_oral_ids: List[int] = Field(default_factory=list, description="Array of oral drug IDs")

def build_mpreview_query(req: MPreviewRequest) -> tuple[str, list[Any]]:
    """
    Constructs a safe, parameterized SQL query string and parameter values list for mpreview.
    Compatible with PostgreSQL (asyncpg positional parameters: $1, $2, ...).
    """
    bind_values: List[Any] = [req.cmbkelas, req.txtperiode1, req.txtperiode2]
    param_idx = 4  # Next parameter index

    # Build unit / ruang filter
    unit_filter_sql = ""
    if req.cmbruang and req.cmbruang.strip():
        p_ruang = f"${param_idx}"
        param_idx += 1
        bind_values.append(req.cmbruang.strip())

        if req.cmbkelas == "3":
            unit_filter_sql = f" AND kr.kd_ruangperawatan IN (SELECT kd_ruangperawatan FROM ruang_perawatan WHERE kd_unit_ruang = {p_ruang})"
        else:
            unit_filter_sql = f" AND u.kd_unit = {p_ruang}"

    # Build filter logic (resolving the recursive duplication bug in PHP)
    filter_sql = unit_filter_sql
    if req.ckstatustidakpakai == "true":
        filter_sql += f""" AND dt.no_transaksi_asal NOT IN (
            SELECT DISTINCT dt_sub.no_transaksi_asal
            FROM detail_transaksi_obat dt_sub
            JOIN transaksi t ON dt_sub.no_transaksi_asal = t.no_transaksi
            JOIN unit u ON t.kd_unit = u.kd_unit
            JOIN pasien p ON p.no_medicalrecord = t.no_medicalrecord
            LEFT JOIN history_gantikamar gk ON gk.no_transaksi = t.no_transaksi
            JOIN kunjungan k ON k.no_registrasikunjungan = t.no_registrasikunjungan
            LEFT JOIN kamar_perawatan kr ON kr.kd_kamarperawatan = gk.kd_kamarperawatan
            LEFT JOIN ruang_perawatan rp ON rp.kd_ruangperawatan = kr.kd_ruangperawatan
            LEFT JOIN apotek_obat a ON a.kd_obat = dt_sub.kd_obat
            WHERE u.kd_instalasi = $1 
              AND a.kd_jenis_terapi = 8 
              AND k.tgl_masuk::date BETWEEN $2 AND $3
              AND tgl_keluar_rm IS NOT NULL 
              AND dt_sub.status_hapus = 0 
              AND status_kirim = 1
              {unit_filter_sql}
        )"""
    else:
        filter_sql += " AND a.kd_jenis_terapi = 8"

    filter_krs = (
        "MAX(DATE(tgl_keluar_rm)) = MAX(DATE(dt.tgl_transaksi))"
        if req.cmbkrs == '1' else
        "MAX(DATE(tgl_keluar_rm)) != MAX(DATE(dt.tgl_transaksi))"
    )

    p_obat = f"${param_idx}"
    param_idx += 1
    bind_values.append(req.obat_oral_ids if req.obat_oral_ids else [0])

    if req.cmbkelas == '1':
        sql = f"""SELECT
            dt.no_transaksi_asal,
            rp.nama_ruangperawatan,
            u.nama_unit,
            p.nama_pasien,
            t.no_medicalrecord,
            a.nama_obat,
            a.kd_obat,
            k.no_registrasikunjungan,
            DATE(k.tgl_masuk) AS tgl_mrs,
            DATE(tgl_keluar_rm) AS tgl_krs,
            SUM(dt.qty) AS qty,
            EXTRACT(days FROM age(tgl_keluar_rm, k.tgl_masuk)) AS lama_perawatan,
            (gk.tgl_keluar::date - gk.tgl_masuk::date) AS lama_perawatan_diruangan,
            (tgl_keluar_rm::date - k.tgl_masuk::date) AS lama_perawatan_total,
            COUNT(*) OVER (PARTITION BY dt.no_transaksi_asal) AS span,
            pm.nama_paramedis,
            'rj' AS jenis_kunjungan
        FROM detail_transaksi_obat dt
        JOIN transaksi t ON dt.no_transaksi_asal = t.no_transaksi
        JOIN unit u ON t.kd_unit = u.kd_unit
        JOIN pasien p ON p.no_medicalrecord = t.no_medicalrecord
        LEFT JOIN history_gantikamar gk ON gk.no_transaksi = t.no_transaksi
        JOIN kunjungan k ON k.no_registrasikunjungan = t.no_registrasikunjungan
        LEFT JOIN kamar_perawatan kr ON kr.kd_kamarperawatan = gk.kd_kamarperawatan
        LEFT JOIN ruang_perawatan rp ON rp.kd_ruangperawatan = kr.kd_ruangperawatan
        LEFT JOIN apotek_obat a ON a.kd_obat = dt.kd_obat
        LEFT JOIN para_medis pm ON dt.kd_paramedis = pm.kd_paramedis
        WHERE u.kd_instalasi = $1
          AND k.tgl_keluar_rme::date BETWEEN $2 AND $3
          AND dt.status_hapus = 0
          AND status_kirim = 1
          AND a.kd_jenis_terapi = 8
          AND a.kd_obat = ANY({p_obat})
        GROUP BY
            dt.no_transaksi_asal, rp.nama_ruangperawatan, pm.nama_paramedis,
            u.nama_unit, p.nama_pasien, t.no_medicalrecord, t.tgl_transaksi,
            a.nama_obat, k.tgl_masuk, k.no_registrasikunjungan,
            gk.kd_kamarperawatan, gk.tgl_masuk, gk.tgl_keluar, a.kd_obat
        ORDER BY u.nama_unit, p.nama_pasien"""
    else:
        sql = f"""SELECT
            dt.no_transaksi_asal,
            rp.nama_ruangperawatan,
            u.nama_unit,
            p.nama_pasien,
            t.no_medicalrecord,
            a.nama_obat,
            a.kd_obat,
            k.no_registrasikunjungan,
            DATE(k.tgl_masuk) AS tgl_mrs,
            DATE(tgl_keluar_rm) AS tgl_krs,
            SUM(dt.qty) AS qty,
            EXTRACT(days FROM age(tgl_keluar_rm, k.tgl_masuk)) AS lama_perawatan,
            (gk.tgl_keluar::date - gk.tgl_masuk::date) AS lama_perawatan_diruangan,
            (tgl_keluar_rm::date - k.tgl_masuk::date) AS lama_perawatan_total,
            COUNT(*) OVER (PARTITION BY dt.no_transaksi_asal) AS span,
            pm.nama_paramedis,
            'inap' AS jenis_kunjungan
        FROM detail_transaksi_obat dt
        JOIN transaksi t ON dt.no_transaksi_asal = t.no_transaksi
        JOIN unit u ON t.kd_unit = u.kd_unit
        JOIN pasien p ON p.no_medicalrecord = t.no_medicalrecord
        LEFT JOIN history_gantikamar gk ON gk.no_transaksi = t.no_transaksi
        JOIN kunjungan k ON k.no_registrasikunjungan = t.no_registrasikunjungan
        LEFT JOIN kamar_perawatan kr ON kr.kd_kamarperawatan = gk.kd_kamarperawatan
        LEFT JOIN ruang_perawatan rp ON rp.kd_ruangperawatan = kr.kd_ruangperawatan
        LEFT JOIN apotek_obat a ON a.kd_obat = dt.kd_obat
        LEFT JOIN para_medis pm ON dt.kd_paramedis = pm.kd_paramedis
        WHERE u.kd_instalasi = $1
          AND tgl_keluar_rm IS NOT NULL
          AND k.tgl_keluar_rm::date BETWEEN $2 AND $3
          AND dt.status_hapus = 0
          AND status_kirim = 1
          {filter_sql}
        GROUP BY
            dt.no_transaksi_asal, rp.nama_ruangperawatan, pm.nama_paramedis,
            u.nama_unit, p.nama_pasien, t.no_medicalrecord, t.tgl_transaksi,
            a.nama_obat, k.tgl_masuk, k.no_registrasikunjungan,
            gk.kd_kamarperawatan, gk.tgl_masuk, gk.tgl_keluar, a.kd_obat
        HAVING
            SUM(CASE WHEN a.kd_obat = ANY({p_obat}) THEN 1 ELSE 0 END) = 0
            AND {filter_krs}
        ORDER BY t.no_medicalrecord, k.no_registrasikunjungan, dt.no_transaksi_asal"""

    return sql, bind_values

async def execute_mpreview(conn: asyncpg.Connection, req: MPreviewRequest) -> List[Dict[str, Any]]:
    """
    Executes the parameterized mpreview query on an active asyncpg database connection.
    """
    sql, bind_values = build_mpreview_query(req)
    records = await conn.fetch(sql, *bind_values)
    return [dict(r) for r in records]
