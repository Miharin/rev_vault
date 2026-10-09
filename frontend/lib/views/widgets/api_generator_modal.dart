import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../models/saved_query.dart';
import '../../services/backend_codegen_service.dart';
import '../../state/app_state.dart';
import 'cyber_dropdown_bottom_sheet.dart';

/// Opens the Multi-Language Backend API Generator Modal
Future<void> showApiGeneratorModal(BuildContext context, {required String query}) async {
  final appState = context.read<AppState>();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: _ApiGeneratorModalDialog(query: query),
    ),
  );
}

class _ApiGeneratorModalDialog extends StatefulWidget {
  final String query;

  const _ApiGeneratorModalDialog({required this.query});

  @override
  State<_ApiGeneratorModalDialog> createState() => _ApiGeneratorModalDialogState();
}

class _ApiGeneratorModalDialogState extends State<_ApiGeneratorModalDialog> {
  final BackendCodegenService _codegenService = BackendCodegenService();

  late final TextEditingController _endpointNameCtrl;
  late final TextEditingController _routePathCtrl;
  late final Map<String, TextEditingController> _queryControllers;
  String _activeQueryOp = 'select';
  bool _isQueryConfigExpanded = true;

  String _selectedMethod = 'GET';
  String _selectedFramework = 'fastapi';
  Set<String> _selectedOperations = {'select'}; // multiple choice: 'select', 'insert', 'update', 'delete'
  bool _snippetOnlyMode = false; // Toggle between Function Only and Full Project Files
  String _selectedFileKey = '';
  bool _isExportingZip = false;
  String _zipStatusMessage = '';

  List<ApiQueryParam> _parameters = [];
  late GeneratedApiProject _currentProject;

  @override
  void initState() {
    super.initState();
    // Auto-detect operation type from query
    final detected = _codegenService.detectOperationType(widget.query);
    _selectedOperations = {detected};
    _activeQueryOp = detected;
    _selectedMethod = _defaultMethodForOp(detected);

    _endpointNameCtrl = TextEditingController(text: '${detected}_records');
    _routePathCtrl = TextEditingController(text: '/api/v1/records');

    _queryControllers = {
      for (final op in ['select', 'insert', 'update', 'delete'])
        op: TextEditingController(
          text: op == detected
              ? widget.query.trim()
              : _codegenService.getQueryForOperation(widget.query, op),
        ),
    };

    _updateParametersFromActiveQueries();

    _currentProject = _codegenService.generate(
      framework: _selectedFramework,
      query: _queryControllers[_activeQueryOp]?.text.trim() ?? widget.query,
      endpointName: _endpointNameCtrl.text.trim(),
      routePath: _routePathCtrl.text.trim(),
      method: _selectedMethod,
      parameters: _parameters,
      dbType: 'postgresql',
      operationType: _selectedOperations.first,
      operationTypes: _selectedOperations.toList(),
      operationQueries: {
        for (final entry in _queryControllers.entries)
          entry.key: entry.value.text.trim(),
      },
    );
    _selectedFileKey = _currentProject.primaryFile;
  }

  void _updateParametersFromActiveQueries() {
    final allNames = <String>{};
    for (final op in _selectedOperations) {
      final sql = _queryControllers[op]?.text ?? '';
      final extracted = RegExp(r':([a-zA-Z0-9_]+)').allMatches(sql).map((m) => m.group(1)!).toSet();
      final dollar = RegExp(r'\$(\d+)').allMatches(sql).map((m) => 'param_${m.group(1)!}').toSet();
      allNames.addAll(extracted);
      allNames.addAll(dollar);
    }
    _parameters = allNames.map((n) => ApiQueryParam(name: n)).toList();
  }

  String _defaultMethodForOp(String op) {
    switch (op) {
      case 'insert':
        return 'POST';
      case 'update':
        return 'PUT';
      case 'delete':
        return 'DELETE';
      case 'select':
      default:
        return 'GET';
    }
  }

  bool _depsInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_depsInitialized) {
      _depsInitialized = true;
      _regenerateCode();
    }
  }

  @override
  void dispose() {
    _endpointNameCtrl.dispose();
    _routePathCtrl.dispose();
    for (final ctrl in _queryControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _regenerateCode() {
    _updateParametersFromActiveQueries();
    final activeEngine = context.read<AppState>().activeConnection?.engine ?? 'postgresql';
    final opQueries = {
      for (final entry in _queryControllers.entries)
        entry.key: entry.value.text.trim(),
    };

    _currentProject = _codegenService.generate(
      framework: _selectedFramework,
      query: _queryControllers[_activeQueryOp]?.text.trim() ?? widget.query,
      endpointName: _endpointNameCtrl.text.trim().isEmpty ? 'manage_records' : _endpointNameCtrl.text.trim(),
      routePath: _routePathCtrl.text.trim().isEmpty ? '/api/v1/records' : _routePathCtrl.text.trim(),
      method: _selectedMethod,
      parameters: _parameters,
      dbType: activeEngine,
      operationType: _selectedOperations.first,
      operationTypes: _selectedOperations.toList(),
      operationQueries: opQueries,
    );

    if (!_currentProject.files.containsKey(_selectedFileKey)) {
      _selectedFileKey = _currentProject.primaryFile;
    }
  }

  Future<void> _exportZipArchive() async {
    setState(() {
      _isExportingZip = true;
      _zipStatusMessage = 'Building ZIP package...';
    });

    try {
      final state = context.read<AppState>();
      final backendUrl = '${state.backendBaseUrl}/api/codegen/backend/export-zip';
      
      final payload = jsonEncode({
        'framework': _selectedFramework,
        'query': _queryControllers[_activeQueryOp]?.text.trim() ?? widget.query,
        'endpoint_name': _endpointNameCtrl.text.trim(),
        'route_path': _routePathCtrl.text.trim(),
        'method': _selectedMethod,
        'parameters': _parameters.map((p) => p.toJson()).toList(),
        'db_type': state.activeConnection?.engine ?? 'postgresql',
        'operation_type': _selectedOperations.first,
        'operation_types': _selectedOperations.toList(),
        'operation_queries': {
          for (final entry in _queryControllers.entries)
            entry.key: entry.value.text.trim(),
        },
      });

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode == 200) {
        final opsLabel = _selectedOperations.length == 1 ? _selectedOperations.first : 'crud';
        final filename = '${_endpointNameCtrl.text.trim()}_${opsLabel}_$_selectedFramework.zip';
        setState(() {
          _zipStatusMessage = 'ZIP package created successfully ($filename, ${response.bodyBytes.length} bytes)!';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ZIP package generated: $filename (${response.bodyBytes.length} bytes)'),
              backgroundColor: const Color(0xFF14B8A6),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _zipStatusMessage = 'Export failed (${response.statusCode}): ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _zipStatusMessage = 'Client error generating ZIP: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExportingZip = false;
        });
      }
    }
  }

  Future<void> _exportOpenApi() async {
    setState(() {
      _zipStatusMessage = 'Generating OpenAPI 3.1 specification...';
    });
    try {
      final state = context.read<AppState>();
      final backendUrl = '${state.backendBaseUrl}/api/codegen/openapi/generate';
      final payload = jsonEncode({
        'framework': _selectedFramework,
        'query': _queryControllers[_activeQueryOp]?.text.trim() ?? widget.query,
        'endpoint_name': _endpointNameCtrl.text.trim(),
        'route_path': _routePathCtrl.text.trim(),
        'method': _selectedMethod,
        'parameters': _parameters.map((p) => p.toJson()).toList(),
        'db_type': state.activeConnection?.engine ?? 'postgresql',
        'operation_type': _selectedOperations.first,
        'operation_types': _selectedOperations.toList(),
        'operation_queries': {
          for (final entry in _queryControllers.entries)
            entry.key: entry.value.text.trim(),
        },
      });

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final spec = decoded['spec'];
        final prettyJson = const JsonEncoder.withIndent('  ').convert(spec);
        await Clipboard.setData(ClipboardData(text: prettyJson));
        setState(() {
          _zipStatusMessage = 'OpenAPI 3.1.0 spec copied to clipboard!';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OpenAPI 3.1.0 Specification copied to clipboard!'),
              backgroundColor: Color(0xFF14B8A6),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(() {
          _zipStatusMessage = 'OpenAPI generation failed: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _zipStatusMessage = 'OpenAPI export error: $e';
      });
    }
  }

  Future<void> _exportPostman() async {
    setState(() {
      _zipStatusMessage = 'Generating Postman v2.1 collection...';
    });
    try {
      final state = context.read<AppState>();
      final backendUrl = '${state.backendBaseUrl}/api/codegen/postman/generate';
      final payload = jsonEncode({
        'framework': _selectedFramework,
        'query': _queryControllers[_activeQueryOp]?.text.trim() ?? widget.query,
        'endpoint_name': _endpointNameCtrl.text.trim(),
        'route_path': _routePathCtrl.text.trim(),
        'method': _selectedMethod,
        'parameters': _parameters.map((p) => p.toJson()).toList(),
        'db_type': state.activeConnection?.engine ?? 'postgresql',
        'operation_type': _selectedOperations.first,
        'operation_types': _selectedOperations.toList(),
        'operation_queries': {
          for (final entry in _queryControllers.entries)
            entry.key: entry.value.text.trim(),
        },
      });

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final col = decoded['collection'];
        final prettyJson = const JsonEncoder.withIndent('  ').convert(col);
        await Clipboard.setData(ClipboardData(text: prettyJson));
        setState(() {
          _zipStatusMessage = 'Postman v2.1 Collection copied to clipboard!';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Postman Collection copied to clipboard!'),
              backgroundColor: Color(0xFF14B8A6),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(() {
          _zipStatusMessage = 'Postman generation failed: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _zipStatusMessage = 'Postman export error: $e';
      });
    }
  }

  Future<void> _selectMethodViaBottomSheet() async {
    final selected = await showCyberDropdownBottomSheet<String>(
      context: context,
      title: 'Select HTTP Method',
      headerIcon: Icons.http,
      selectedValue: _selectedMethod,
      items: const [
        CyberDropdownItem(
          value: 'GET',
          label: 'GET',
          subtitle: 'Safe retrieval of database records',
          icon: Icons.search,
          color: Colors.teal,
        ),
        CyberDropdownItem(
          value: 'POST',
          label: 'POST',
          subtitle: 'Create / insert new records',
          icon: Icons.add_circle_outline,
          color: Colors.green,
        ),
        CyberDropdownItem(
          value: 'PUT',
          label: 'PUT',
          subtitle: 'Update / replace existing records',
          icon: Icons.edit_note,
          color: Colors.amber,
        ),
        CyberDropdownItem(
          value: 'DELETE',
          label: 'DELETE',
          subtitle: 'Remove records permanently',
          icon: Icons.delete_outline,
          color: Colors.redAccent,
        ),
      ],
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedMethod = selected;
        _regenerateCode();
      });
    }
  }

  Future<void> _openSavedQueriesBottomSheet() async {
    final state = context.read<AppState>();
    final queries = state.savedQueries;
    if (queries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved queries in library yet.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final selected = await showCyberDropdownBottomSheet<SavedQuery>(
      context: context,
      title: 'Load Saved Query into ${_activeQueryOp.toUpperCase()}',
      searchHint: 'Search saved queries...',
      headerIcon: Icons.bookmarks_outlined,
      items: queries.map((sq) {
        return CyberDropdownItem<SavedQuery>(
          value: sq,
          label: sq.title,
          subtitle: sq.sql.replaceAll('\n', ' ').trim(),
          icon: Icons.code,
          color: const Color(0xFF14B8A6),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      setState(() {
        _queryControllers[_activeQueryOp]!.text = selected.sql.trim();
        _regenerateCode();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded saved query "${selected.title}" into ${_activeQueryOp.toUpperCase()}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF14B8A6),
        ),
      );
    }
  }

  Future<void> _openPutInBottomSheet() async {
    final targetOps = ['select', 'insert', 'update', 'delete']
        .where((op) => op != _activeQueryOp)
        .toList();

    final selected = await showCyberDropdownBottomSheet<String>(
      context: context,
      title: 'Copy ${_activeQueryOp.toUpperCase()} Query To...',
      headerIcon: Icons.copy_all,
      items: targetOps.map((op) {
        Color col;
        IconData ic;
        switch (op) {
          case 'select':
            col = Colors.teal;
            ic = Icons.search;
            break;
          case 'insert':
            col = Colors.green;
            ic = Icons.add_circle_outline;
            break;
          case 'update':
            col = Colors.amber.shade700;
            ic = Icons.edit_note;
            break;
          case 'delete':
            col = Colors.redAccent;
            ic = Icons.delete_outline;
            break;
          default:
            col = Colors.teal;
            ic = Icons.code;
        }
        return CyberDropdownItem<String>(
          value: op,
          label: 'Copy to ${op.toUpperCase()} (${_defaultMethodForOp(op)})',
          subtitle: 'Assign current ${_activeQueryOp.toUpperCase()} query to $op operation',
          icon: ic,
          color: col,
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      setState(() {
        _queryControllers[selected]!.text = _queryControllers[_activeQueryOp]!.text;
        _activeQueryOp = selected;
        _regenerateCode();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Query copied to ${selected.toUpperCase()}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF14B8A6),
        ),
      );
    }
  }

  void _copyToClipboard(String content, String title) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title copied to clipboard!'),
        backgroundColor: const Color(0xFF14B8A6),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Mode Switcher
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.api, color: Color(0xFF14B8A6), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auto Backend API & Function Generator',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Generate production API endpoints or isolated copy-pasteable functions across 7 frameworks',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Snippet vs Full Project Segmented Button
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.folder_zip_outlined, size: 14),
                        label: Text('Full Project', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.code, size: 14),
                        label: Text('Function Only', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {_snippetOnlyMode},
                    onSelectionChanged: (val) {
                      setState(() {
                        _snippetOnlyMode = val.first;
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedBackgroundColor: const Color(0xFF14B8A6).withValues(alpha: 0.2),
                      selectedForegroundColor: const Color(0xFF14B8A6),
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // CRUD Operation Type Multi-Choice Bar (SELECT, INSERT, UPDATE, DELETE)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Operation Type:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_selectedOperations.length} selected',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    ...['select', 'insert', 'update', 'delete'].map((op) {
                      final isSelected = _selectedOperations.contains(op);
                      Color opColor;
                      switch (op) {
                        case 'select':
                          opColor = Colors.teal;
                          break;
                        case 'insert':
                          opColor = Colors.green;
                          break;
                        case 'update':
                          opColor = Colors.amber.shade700;
                          break;
                        case 'delete':
                          opColor = Colors.redAccent;
                          break;
                        default:
                          opColor = Colors.teal;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            op.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : null,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: opColor,
                          checkmarkColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedOperations.add(op);
                                _activeQueryOp = op;
                              } else {
                                if (_selectedOperations.length > 1) {
                                  _selectedOperations.remove(op);
                                }
                              }
                              if (_selectedOperations.length == 1) {
                                final singleOp = _selectedOperations.first;
                                _selectedMethod = _defaultMethodForOp(singleOp);
                                _endpointNameCtrl.text = '${singleOp}_records';
                              } else {
                                _selectedMethod = 'MULTI';
                                _endpointNameCtrl.text = 'manage_records';
                              }
                              _regenerateCode();
                            });
                          },
                        ),
                      );
                    }),
                    const SizedBox(width: 16),
                    // Quick Action: Toggle All CRUD / Reset to single
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (_selectedOperations.length == 4) {
                            _selectedOperations = {_codegenService.detectOperationType(widget.query)};
                            _activeQueryOp = _selectedOperations.first;
                            _selectedMethod = _defaultMethodForOp(_selectedOperations.first);
                            _endpointNameCtrl.text = '${_selectedOperations.first}_records';
                          } else {
                            _selectedOperations = {'select', 'insert', 'update', 'delete'};
                            _selectedMethod = 'MULTI';
                            _endpointNameCtrl.text = 'manage_records';
                          }
                          _regenerateCode();
                        });
                      },
                      icon: Icon(
                        _selectedOperations.length == 4 ? Icons.restart_alt : Icons.done_all,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      label: Text(
                        _selectedOperations.length == 4 ? 'Single' : 'All CRUD',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _selectedOperations.length == 1
                            ? 'HTTP Method: $_selectedMethod'
                            : 'HTTP: ${_selectedOperations.map(_defaultMethodForOp).join(' | ')}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
              const SizedBox(height: 10),

              // Configuration Row: Endpoint Name, Route Path, HTTP Method
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    // Endpoint Function Name
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _endpointNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Function / Method Name',
                          hintText: 'e.g. get_users_report',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(_regenerateCode),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Route Path
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _routePathCtrl,
                        decoration: const InputDecoration(
                          labelText: 'HTTP Route Path',
                          hintText: 'e.g. /api/v1/users',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(_regenerateCode),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Method Selector
                    Expanded(
                      flex: 2,
                      child: _selectedOperations.length > 1
                          ? Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'MULTI (${_selectedOperations.map(_defaultMethodForOp).join('/')})',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : InkWell(
                              onTap: _selectMethodViaBottomSheet,
                              borderRadius: BorderRadius.circular(4),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Method',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
                                ),
                                child: Text(
                                  _selectedMethod,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // CRUD SQL Queries (Per-Operation Customization: choose which query and put in where)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar with Expand / Collapse
                    InkWell(
                      onTap: () => setState(() => _isQueryConfigExpanded = !_isQueryConfigExpanded),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Row(
                          children: [
                            const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF14B8A6)),
                            const SizedBox(width: 8),
                            const Text(
                              'Operation SQL Queries',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '(Customize query per CRUD operation)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Active: ${_activeQueryOp.toUpperCase()}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF14B8A6), fontFamily: 'monospace'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _isQueryConfigExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isQueryConfigExpanded) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Operation Tabs Selector & Actions Bar
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  // Tabs for SELECT, INSERT, UPDATE, DELETE
                                  ...['select', 'insert', 'update', 'delete'].map((op) {
                                    final isActiveTab = op == _activeQueryOp;
                                    final isIncludedInApi = _selectedOperations.contains(op);
                                    Color opColor;
                                    IconData opIcon;
                                    switch (op) {
                                      case 'select':
                                        opColor = Colors.teal;
                                        opIcon = Icons.search;
                                        break;
                                      case 'insert':
                                        opColor = Colors.green;
                                        opIcon = Icons.add_circle_outline;
                                        break;
                                      case 'update':
                                        opColor = Colors.amber.shade700;
                                        opIcon = Icons.edit_note;
                                        break;
                                      case 'delete':
                                        opColor = Colors.redAccent;
                                        opIcon = Icons.delete_outline;
                                        break;
                                      default:
                                        opColor = Colors.teal;
                                        opIcon = Icons.code;
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _activeQueryOp = op;
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: isActiveTab
                                                ? opColor.withValues(alpha: 0.22)
                                                : theme.colorScheme.surface,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isActiveTab ? opColor : theme.dividerColor.withValues(alpha: 0.3),
                                              width: isActiveTab ? 1.5 : 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                opIcon,
                                                size: 13,
                                                color: isActiveTab
                                                    ? opColor
                                                    : (isDark ? Colors.grey : Colors.black54),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                '${op.toUpperCase()} (${_defaultMethodForOp(op)})',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: isActiveTab ? FontWeight.bold : FontWeight.w500,
                                                  color: isDark
                                                      ? (isActiveTab ? Colors.white : Colors.grey.shade400)
                                                      : (isActiveTab ? Colors.black : Colors.black87),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isIncludedInApi
                                                      ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                                                      : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  const SizedBox(width: 16),

                                  // Quick Action 1: Use Active SQL Editor Query
                                  Tooltip(
                                    message: 'Set ${_activeQueryOp.toUpperCase()} query to current Editor SQL',
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _queryControllers[_activeQueryOp]!.text = widget.query.trim();
                                          _regenerateCode();
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Loaded SQL Editor query into ${_activeQueryOp.toUpperCase()}'),
                                            duration: const Duration(seconds: 1),
                                            backgroundColor: const Color(0xFF14B8A6),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.download, size: 12),
                                      label: const Text('Use Editor SQL', style: TextStyle(fontSize: 10.5)),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  // Quick Action 2: Auto Template
                                  Tooltip(
                                    message: 'Reset ${_activeQueryOp.toUpperCase()} to auto-generated SQL template',
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _queryControllers[_activeQueryOp]!.text =
                                              _codegenService.getQueryForOperation(widget.query, _activeQueryOp);
                                          _regenerateCode();
                                        });
                                      },
                                      icon: const Icon(Icons.auto_awesome, size: 12),
                                      label: const Text('Auto Template', style: TextStyle(fontSize: 10.5)),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  // Quick Action 3: Saved Queries Picker via BottomSheet
                                  Tooltip(
                                    message: 'Load from Saved Queries into ${_activeQueryOp.toUpperCase()}',
                                    child: InkWell(
                                      onTap: _openSavedQueriesBottomSheet,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.bookmarks_outlined, size: 12, color: Color(0xFF14B8A6)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Saved (${context.watch<AppState>().savedQueries.length})',
                                              style: const TextStyle(fontSize: 10.5),
                                            ),
                                            const Icon(Icons.arrow_drop_down, size: 14),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  // Quick Action 4: Put/Copy to another operation via BottomSheet
                                  Tooltip(
                                    message: 'Copy this query to another CRUD operation',
                                    child: InkWell(
                                      onTap: _openPutInBottomSheet,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.copy_all, size: 12, color: Colors.grey),
                                            SizedBox(width: 4),
                                            Text('Put in...', style: TextStyle(fontSize: 10.5)),
                                            Icon(Icons.arrow_drop_down, size: 14),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // 2. Query Text Field for Active Operation
                            TextField(
                              controller: _queryControllers[_activeQueryOp],
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: Color(0xFFE5E7EB),
                                height: 1.35,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFF0D1117),
                                hintText: 'Enter SQL query for ${_activeQueryOp.toUpperCase()}...',
                                hintStyle: TextStyle(color: Colors.grey.shade600, fontFamily: 'monospace', fontSize: 11),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: Colors.grey.shade800),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: Color(0xFF14B8A6), width: 1.5),
                                ),
                              ),
                              onChanged: (_) => setState(_regenerateCode),
                            ),
                            const SizedBox(height: 6),

                            // 3. Mini bar: Status & toggle to include in generation
                            Row(
                              children: [
                                Checkbox(
                                  value: _selectedOperations.contains(_activeQueryOp),
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedOperations.add(_activeQueryOp);
                                      } else {
                                        if (_selectedOperations.length > 1) {
                                          _selectedOperations.remove(_activeQueryOp);
                                        }
                                      }
                                      _regenerateCode();
                                    });
                                  },
                                ),
                                Text(
                                  'Include ${_activeQueryOp.toUpperCase()} in generated API',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Target: ${_defaultMethodForOp(_activeQueryOp)} ${_activeQueryOp == 'update' || _activeQueryOp == 'delete' ? '${_routePathCtrl.text.trim()}/{id}' : _routePathCtrl.text.trim()}',
                                    textAlign: TextAlign.end,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                      color: isDark ? Colors.grey.shade400 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Detected Parameters Row (if any)
              if (_parameters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.data_object, size: 14, color: Colors.pinkAccent),
                      const SizedBox(width: 6),
                      Text(
                        'Extracted Parameters (${_parameters.length}):',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          children: _parameters.map((p) {
                            return Chip(
                              label: Text('${p.name} (${p.type})', style: const TextStyle(fontSize: 10.5)),
                              backgroundColor: theme.colorScheme.surface,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Framework Selector Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: BackendCodegenService.supportedFrameworks.map((fw) {
                    final isSelected = fw['id'] == _selectedFramework;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          fw['name']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : null,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFF14B8A6),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFramework = fw['id']!;
                              _regenerateCode();
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),

              // Code Display Area (Snippet Only vs Full Project Files)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      // Navigation Bar
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
                        ),
                        child: Row(
                          children: [
                            if (_snippetOnlyMode) ...[
                              Icon(Icons.code, size: 14, color: const Color(0xFF14B8A6)),
                              const SizedBox(width: 8),
                              Text(
                                '${_selectedFramework.toUpperCase()} Function Snippet (${_selectedOperations.length == 1 ? _selectedOperations.first.toUpperCase() : "CRUD (${_selectedOperations.length})"})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace'),
                              ),
                              const Spacer(),
                              Text(
                                'Ready to paste into existing project',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                              ),
                            ] else ...[
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _currentProject.files.keys.map((filename) {
                                      final isSelected = filename == _selectedFileKey;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: InkWell(
                                          onTap: () => setState(() => _selectedFileKey = filename),
                                          borderRadius: BorderRadius.circular(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFF111827) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  filename.endsWith('.php')
                                                      ? Icons.code
                                                      : filename.endsWith('.py')
                                                          ? Icons.terminal
                                                          : filename.endsWith('.js') || filename.endsWith('.ts')
                                                              ? Icons.javascript
                                                              : Icons.description_outlined,
                                                  size: 13,
                                                  color: isSelected ? const Color(0xFF14B8A6) : Colors.grey,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  filename,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontFamily: 'monospace',
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                    color: isSelected ? Colors.white : Colors.grey.shade400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                              tooltip: _snippetOnlyMode ? 'Copy function snippet' : 'Copy current file',
                              onPressed: () => _copyToClipboard(
                                _snippetOnlyMode ? _currentProject.functionSnippet : (_currentProject.files[_selectedFileKey] ?? ''),
                                _snippetOnlyMode ? 'Function snippet' : _selectedFileKey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Code Display View
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _snippetOnlyMode
                                  ? _currentProject.functionSnippet
                                  : (_currentProject.files[_selectedFileKey] ?? ''),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Status line if exporting
              if (_zipStatusMessage.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _zipStatusMessage,
                  style: TextStyle(
                    fontSize: 11,
                    color: _zipStatusMessage.contains('failed') ? Colors.redAccent : const Color(0xFF14B8A6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Footer action buttons (right-aligned, horizontally scrollable to prevent overflow)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _exportOpenApi,
                      icon: const Icon(Icons.description_outlined, size: 15, color: Color(0xFF14B8A6)),
                      label: const Text('OpenAPI 3.1 Spec'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _exportPostman,
                      icon: const Icon(Icons.send_rounded, size: 15, color: Colors.orangeAccent),
                      label: const Text('Postman Collection'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 10),

                    if (_snippetOnlyMode) ...[
                      // Copy Function Snippet Button
                      ElevatedButton.icon(
                        onPressed: () => _copyToClipboard(
                          _currentProject.functionSnippet,
                          '${_selectedFramework.toUpperCase()} ${_selectedOperations.length == 1 ? _selectedOperations.first.toUpperCase() : "CRUD"} Function Snippet',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Function Snippet'),
                      ),
                    ] else ...[
                      // Copy File Code
                      OutlinedButton.icon(
                        onPressed: () => _copyToClipboard(
                          _currentProject.primaryCode,
                          '${_currentProject.primaryFile} code',
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy File Code'),
                      ),
                      const SizedBox(width: 10),

                      // Download Full Scaffolded Project ZIP
                      ElevatedButton.icon(
                        onPressed: _isExportingZip ? null : _exportZipArchive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: _isExportingZip
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.archive, size: 16),
                        label: Text(_isExportingZip ? 'Packing ZIP...' : 'Download Project ZIP'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
