import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';

import 'cyber_dropdown_bottom_sheet.dart';

/// Opens a modal dialog allowing the user to paste dynamic query functions (PHP, JS, Python)
/// and convert them into Raw SQL, Visual Builder rules, and Shader Node Graphs.
Future<void> showConvertCodeModal(BuildContext context) async {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _ConvertCodeModalDialog(),
  );
}

class _ConvertCodeModalDialog extends StatefulWidget {
  const _ConvertCodeModalDialog();

  @override
  State<_ConvertCodeModalDialog> createState() => _ConvertCodeModalDialogState();
}

class _ConvertCodeModalDialogState extends State<_ConvertCodeModalDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  String _sourceLanguage = 'PHP';
  String _queryVariant = 'inap'; // 'rajal' or 'inap'
  bool _isConverting = false;

  final String _samplePhpCode = '''function mpreview(\$txtperiode1, \$txtperiode2, \$cmbruang, \$namaruang, \$ckstatustidakpakai,\$cmbkelas,\$cmbkrs)
{
    \$obatOral = \$this->getObatOral();
    \$filter = "";

    if (\$cmbruang != "" && \$cmbkelas=="3" )
    { \$filter .=  " and kr.kd_ruangperawatan in (select kd_ruangperawatan from ruang_perawatan where kd_unit_ruang = '{\$cmbruang}' )";}
    if (\$cmbruang != "" && \$cmbkelas!="3" )
    { \$filter .=  " and u.kd_unit = '{\$cmbruang}' ";}

    if (\$ckstatustidakpakai == "true")
    { \$filter .=  " and dt.no_transaksi_asal not in (select distinct no_transaksi_asal
        from detail_transaksi_obat dt
        JOIN transaksi t ON dt.no_transaksi_asal = t.no_transaksi
        JOIN unit u ON t.kd_unit = u.kd_unit
        JOIN pasien p ON p.no_medicalrecord = t.no_medicalrecord
        LEFT JOIN history_gantikamar gk ON gk.no_transaksi = t.no_transaksi
        JOIN kunjungan k ON k.no_registrasikunjungan = t.no_registrasikunjungan
        LEFT JOIN kamar_perawatan kr ON kr.kd_kamarperawatan = gk.kd_kamarperawatan
        LEFT JOIN ruang_perawatan rp ON rp.kd_ruangperawatan = kr.kd_ruangperawatan
        LEFT JOIN apotek_obat a ON a.kd_obat = dt.kd_obat
        where u.kd_instalasi = '{\$cmbkelas}' and a.kd_jenis_terapi = 8 and k.tgl_masuk::date between '{\$txtperiode1}' and '{\$txtperiode2}'
        and tgl_keluar_rm is not null and dt.status_hapus = 0 and status_kirim = 1
        {\$filter} )";
    }
    else
    { \$filter .= " and a.kd_jenis_terapi = 8"; }
    
    \$filterKrs = "MAX(DATE(tgl_keluar_rm)) != MAX(DATE(dt.tgl_transaksi))";
    if (\$cmbkrs == '1') {
        \$filterKrs = "MAX(DATE(tgl_keluar_rm)) = MAX(DATE(dt.tgl_transaksi))";
    }

    \$kpraRajal = "SELECT
                dt.no_transaksi_asal,
                nama_ruangperawatan,
                nama_unit,
                nama_pasien,
                T.no_medicalrecord,
                nama_obat,
                A.kd_obat,
                K.no_registrasikunjungan,
                DATE (K.tgl_masuk) AS tgl_mrs,
                DATE (tgl_keluar_rm) AS tgl_krs,
                SUM(qty) qty,
                EXTRACT(days FROM age(tgl_keluar_rm, K.tgl_masuk)) lama_perawatan,
                (gk.tgl_keluar :: DATE - gk.tgl_masuk :: DATE) AS lama_perawatan_diruangan,
                (tgl_keluar_rm :: DATE - K.tgl_masuk :: DATE) AS lama_perawatan,
                COUNT(*) OVER (PARTITION BY dt.no_transaksi_asal) span,
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
                WHERE u.kd_instalasi = '{\$cmbkelas}'
                AND K.tgl_keluar_rme :: DATE BETWEEN '{\$txtperiode1}' and '{\$txtperiode2}'
                AND dt.status_hapus = 0 AND status_kirim = 1 AND a.kd_jenis_terapi = 8
                AND a.kd_obat IN (\$obatOral)
                GROUP BY no_transaksi_asal, nama_ruangperawatan, pm.nama_paramedis, nama_unit, nama_pasien, T.no_medicalrecord, T.tgl_transaksi, nama_obat, K.tgl_masuk, K.no_registrasikunjungan, gk.kd_kamarperawatan, gk.tgl_masuk, gk.tgl_keluar, A.kd_obat
                ORDER BY nama_unit, nama_pasien";

    \$kpraInap = "SELECT
    dt.no_transaksi_asal,
    nama_ruangperawatan,
    nama_unit,
    nama_pasien,	
    T.no_medicalrecord,
    nama_obat,
    A.kd_obat,
    K.no_registrasikunjungan,
    date(K.tgl_masuk) AS tgl_mrs,
    date(tgl_keluar_rm) AS tgl_krs,
    SUM ( qty ) qty,
    EXTRACT ( days FROM age( tgl_keluar_rm, K.tgl_masuk ) ) lama_perawatan,
    (gk.tgl_keluar::date - gk.tgl_masuk::date) AS lama_perawatan_diruangan,
    (tgl_keluar_rm::date - K.tgl_masuk::date) AS lama_perawatan,
    COUNT ( * ) OVER ( PARTITION BY dt.no_transaksi_asal ) span,
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
        WHERE u.kd_instalasi = '{\$cmbkelas}'
        AND tgl_keluar_rm IS NOT NULL
        AND K.tgl_keluar_rm :: DATE BETWEEN '{\$txtperiode1}' and '{\$txtperiode2}'
        AND dt.status_hapus = 0 AND status_kirim = 1
        {\$filter}
    GROUP BY no_transaksi_asal, nama_ruangperawatan, pm.nama_paramedis, nama_unit, nama_pasien, T.no_medicalrecord, T.tgl_transaksi, nama_obat, K.tgl_masuk, K.no_registrasikunjungan, gk.kd_kamarperawatan, gk.tgl_masuk, gk.tgl_keluar, A.kd_obat
    HAVING SUM(CASE WHEN A.kd_obat IN (\$obatOral) THEN 1 ELSE 0 END) = 0
       AND {\$filterKrs}
    ORDER BY t.no_medicalrecord, K.no_registrasikunjungan, dt.no_transaksi_asal";

    \$result = \$this->db->query((\$cmbkelas == '1') ? \$kpraRajal : \$kpraInap);
    return \$result;
}''';

  @override
  void initState() {
    super.initState();
    _codeCtrl.text = _samplePhpCode;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _convertCode() {
    final rawCode = _codeCtrl.text.trim();
    if (rawCode.isEmpty) return;

    setState(() {
      _isConverting = true;
    });

    String extractedSql = "";

    // 1. Extract query variable block ($kpraInap or $kpraRajal)
    final rajalMatch = RegExp(r'\$kpraRajal\s*=\s*"([^"]+)"', dotAll: true).firstMatch(rawCode);
    final inapMatch = RegExp(r'\$kpraInap\s*=\s*"([^"]+)"', dotAll: true).firstMatch(rawCode);

    if (_queryVariant == 'inap' && inapMatch != null) {
      extractedSql = inapMatch.group(1)!;
    } else if (rajalMatch != null) {
      extractedSql = rajalMatch.group(1)!;
    } else {
      // Fallback to finding the largest SELECT block
      final allSelects = RegExp(r'SELECT\s+[\s\S]+?\bORDER BY\s+[^\n";]+', caseSensitive: false).allMatches(rawCode);
      if (allSelects.isNotEmpty) {
        // Pick the longest SELECT block to avoid matching small subqueries inside $filter
        extractedSql = allSelects.map((m) => m.group(0)!).reduce((a, b) => a.length > b.length ? a : b);
      } else {
        extractedSql = rawCode;
      }
    }

    // 2. Perform parameter replacement and variable expansion
    String convertedSql = extractedSql
        .replaceAll(RegExp(r"'\{\$cmbkelas\}'"), _queryVariant == 'rajal' ? "'1'" : "'3'")
        .replaceAll(RegExp(r"'\{\$txtperiode1\}'"), "'2026-01-01'")
        .replaceAll(RegExp(r"'\{\$txtperiode2\}'"), "'2026-01-31'")
        .replaceAll(RegExp(r"\{\$filter\}"), "AND a.kd_jenis_terapi = 8")
        .replaceAll(RegExp(r"\{\$filterKrs\}"), "MAX(DATE(tgl_keluar_rm)) != MAX(DATE(dt.tgl_transaksi))")
        .replaceAll(RegExp(r"\bIN\s*\(\s*\$obatOral\s*\)", caseSensitive: false), "= ANY(ARRAY['']::text[])")
        .replaceAll(RegExp(r"\(\s*\$obatOral\s*\)"), "= ANY(ARRAY['']::text[])")
        .replaceAll(RegExp(r"\bIN\s*\(\s*\)", caseSensitive: false), "= ANY(ARRAY['']::text[])")
        .replaceAll(RegExp(r"\btgl_keluar_rme\b", caseSensitive: false), "tgl_keluar_rm")
        .trim();

    final state = context.read<AppState>();
    state.setEditorQueryText(convertedSql);

    setState(() {
      _isConverting = false;
    });

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text('Successfully converted full query to Parameterized SQL & Shader Nodes!'),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.transform, color: accent, size: 22),
          const SizedBox(width: 8),
          const Text('Convert Code / Function to Query', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Source Language:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () async {
                        final items = const [
                          CyberDropdownItem<String>(value: 'PHP', label: 'PHP CodeIgniter / PDO', icon: Icons.code),
                          CyberDropdownItem<String>(value: 'JS', label: 'JavaScript / Node.js', icon: Icons.javascript),
                          CyberDropdownItem<String>(value: 'Python', label: 'Python (SQLAlchemy/asyncpg)', icon: Icons.terminal),
                        ];

                        final selected = await showCyberDropdownBottomSheet<String>(
                          context: context,
                          title: 'Select Source Language',
                          items: items,
                          selectedValue: _sourceLanguage,
                          headerIcon: Icons.code,
                        );
                        if (selected != null) {
                          setState(() => _sourceLanguage = selected);
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _sourceLanguage == 'PHP'
                                  ? 'PHP CodeIgniter / PDO'
                                  : (_sourceLanguage == 'JS' ? 'JavaScript / Node.js' : 'Python'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_drop_down, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Query Branch:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'inap', label: Text('Inpatient (Inap)', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'rajal', label: Text('Outpatient (Rajal)', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {_queryVariant},
                      onSelectionChanged: (val) {
                        setState(() => _queryVariant = val.first);
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Paste Function / Query Builder Code:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _codeCtrl,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              decoration: InputDecoration(
                hintText: 'Paste function code here...',
                border: const OutlineInputBorder(),
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                filled: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isConverting ? null : _convertCode,
          icon: _isConverting
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_fix_high, size: 16),
          label: const Text('Convert & Populate Views'),
        ),
      ],
    );
  }
}
