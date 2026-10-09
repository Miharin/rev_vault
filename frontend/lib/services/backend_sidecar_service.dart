import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Service responsible for managing the embedded Python backend sidecar process
/// on Desktop platforms (Linux, Windows, macOS).
class BackendSidecarService with WidgetsBindingObserver {
  static final BackendSidecarService instance = BackendSidecarService._();
  BackendSidecarService._();

  Process? _process;
  int _activePort = 8000;
  bool _isManagedByApp = false;
  Completer<int>? _portCompleter;

  int get activePort => _activePort;
  String get baseUrl => 'http://127.0.0.1:$_activePort';

  /// Ensures that a RevVault backend instance is running and healthy.
  /// If an external backend is already online on [targetPort], it will be reused.
  /// Otherwise, it spawns the bundled sidecar executable.
  Future<int> ensureBackendRunning({int targetPort = 8000}) async {
    if (kIsWeb || (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS)) {
      return targetPort;
    }

    // 1. Check if backend is already online
    final isAlreadyUp = await _probeHealth(targetPort);
    if (isAlreadyUp) {
      debugPrint('[Sidecar] Existing backend detected on port $targetPort');
      _activePort = targetPort;
      return targetPort;
    }

    // 2. Locate bundled backend binary
    final candidatePaths = _getCandidateExecutablePaths();
    String? executable;
    List<String> args = ['--auto-port', '--port', targetPort.toString()];

    for (final candidate in candidatePaths) {
      if (candidate.type == _CandidateType.direct && File(candidate.path).existsSync()) {
        executable = candidate.path;
        break;
      } else if (candidate.type == _CandidateType.pythonScript && File(candidate.path).existsSync()) {
        executable = candidate.pythonBin;
        args = [candidate.path, '--auto-port', '--port', targetPort.toString()];
        break;
      }
    }

    if (executable == null) {
      debugPrint('[Sidecar] No bundled backend binary found. Assuming external daemon.');
      return targetPort;
    }

    debugPrint('[Sidecar] Spawning backend sidecar: $executable with args $args');

    _portCompleter = Completer<int>();

    try {
      _process = await Process.start(
        executable,
        args,
        workingDirectory: File(executable).parent.path,
        mode: ProcessStartMode.normal,
      );
      _isManagedByApp = true;

      // Register exit observers
      WidgetsBinding.instance.addObserver(this);
      _setupSignalHandlers();

      // Listen to stdout to catch REVVAULT_ASSIGNED_PORT
      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        debugPrint('[Backend stdout] $line');
        final match = RegExp(r'REVVAULT_ASSIGNED_PORT=(\d+)').firstMatch(line);
        if (match != null && !(_portCompleter?.isCompleted ?? true)) {
          final assigned = int.tryParse(match.group(1)!) ?? targetPort;
          _portCompleter?.complete(assigned);
        }
      });

      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        debugPrint('[Backend stderr] $line');
      });

      _process!.exitCode.then((code) {
        debugPrint('[Sidecar] Backend exited with code $code');
        _isManagedByApp = false;
        _process = null;
      });

      // Wait for port announcement with 3s timeout
      _activePort = await _portCompleter!.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => targetPort,
      );

      // Poll health until 200 OK
      final ready = await _pollUntilHealthy(_activePort, timeout: const Duration(seconds: 10));
      if (!ready) {
        debugPrint('[Sidecar] Backend failed health check timeout.');
      } else {
        debugPrint('[Sidecar] Backend is healthy on port $_activePort');
      }

      return _activePort;
    } catch (e) {
      debugPrint('[Sidecar] Failed to launch backend sidecar: $e');
      return targetPort;
    }
  }

  Future<bool> _probeHealth(int port) async {
    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:$port/health')).timeout(const Duration(milliseconds: 600));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pollUntilHealthy(int port, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _probeHealth(port)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  List<_Candidate> _getCandidateExecutablePaths() {
    final results = <_Candidate>[];
    final execDir = File(Platform.resolvedExecutable).parent.path;

    if (Platform.isLinux) {
      // 1. Release bundle path: ./backend/revvault-backend
      results.add(_Candidate(
        type: _CandidateType.direct,
        path: '$execDir/backend/revvault-backend',
      ));
      // 2. Adjacent binary: ./revvault-backend
      results.add(_Candidate(
        type: _CandidateType.direct,
        path: '$execDir/revvault-backend',
      ));
      // 3. Local dev fallback
      results.add(_Candidate(
        type: _CandidateType.pythonScript,
        path: '${Directory.current.path}/../backend/run_server.py',
        pythonBin: '${Directory.current.path}/../backend/.venv/bin/python',
      ));
    } else if (Platform.isWindows) {
      // 1. Release bundle path: ./backend/revvault-backend.exe
      results.add(_Candidate(
        type: _CandidateType.direct,
        path: '$execDir\\backend\\revvault-backend.exe',
      ));
      // 2. Adjacent binary: ./revvault-backend.exe
      results.add(_Candidate(
        type: _CandidateType.direct,
        path: '$execDir\\revvault-backend.exe',
      ));
      // 3. Local dev fallback
      results.add(_Candidate(
        type: _CandidateType.pythonScript,
        path: '${Directory.current.path}\\..\\backend\\run_server.py',
        pythonBin: '${Directory.current.path}\\..\\backend\\.venv\\Scripts\\python.exe',
      ));
    }

    return results;
  }

  void _setupSignalHandlers() {
    if (!kIsWeb && Platform.isLinux) {
      try {
        ProcessSignal.sigint.watch().listen((_) => terminate());
        ProcessSignal.sigterm.watch().listen((_) => terminate());
      } catch (_) {}
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    terminate();
    return AppExitResponse.exit;
  }

  /// Terminates the child backend process gracefully.
  void terminate() {
    if (_isManagedByApp && _process != null) {
      debugPrint('[Sidecar] Terminating child backend process (PID ${_process!.pid})...');
      try {
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {
        _process!.kill();
      }
      _process = null;
      _isManagedByApp = false;
    }
  }
}

enum _CandidateType { direct, pythonScript }

class _Candidate {
  final _CandidateType type;
  final String path;
  final String pythonBin;

  _Candidate({
    required this.type,
    required this.path,
    this.pythonBin = 'python3',
  });
}
