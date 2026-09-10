import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Mirrors the ↺ restart button + status dots of https://junilab.xyz
// (terminal-startpage index.html: restartOC() + SERVICE_URLS).
const String kVizUiUrl = 'https://viz-ui.junilab.xyz';

const Map<String, String> kServices = {
  'vis-ui': 'https://viz-ui.junilab.xyz',
  'memory': 'https://memory.junilab.xyz',
  'voice': 'https://voice.junilab.xyz',
  'gitea': 'https://gitea.junilab.xyz',
  'kuma': 'https://kuma.junilab.xyz',
  'n8n': 'https://n8n.junilab.xyz',
  'dev': 'https://dev.junilab.xyz',
  'kasmweb': 'https://desktop.junilab.xyz',
  'pdf': 'https://pdf.junilab.xyz',
  'memos': 'https://memos.junilab.xyz/',
  'vikunja': 'https://vikunja.junilab.xyz/',
  'dave': 'https://dave.junilab.xyz',
  'ntfy': 'https://ntfy.junilab.xyz',
  'radicale': 'https://radicale.junilab.xyz/',
  'gatus': 'https://gatus.junilab.xyz',
};

void main() => runApp(const OcRestartApp());

class OcRestartApp extends StatelessWidget {
  const OcRestartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OC Restart',
      theme: ThemeData.dark(useMaterial3: true),
      home: const RestartPage(),
    );
  }
}

class RestartPage extends StatefulWidget {
  const RestartPage({super.key});

  @override
  State<RestartPage> createState() => _RestartPageState();
}

class _RestartPageState extends State<RestartPage> {
  bool _busy = false;
  String _status = 'Idle — press ↺ to ping OpenCode.';
  final Map<String, bool?> _dots = {for (final k in kServices.keys) k: null};

  Future<bool> _ping(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // Same action as restartOC(): hit viz-ui, then refresh statuses.
  Future<void> _restart() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Pinging OpenCode…';
    });
    final sw = Stopwatch()..start();
    final ok = await _ping(kVizUiUrl);
    sw.stop();
    if (mounted) {
      setState(() {
        _status = ok
            ? 'OpenCode answered in ${sw.elapsedMilliseconds} ms — refreshing…'
            : 'No answer from OpenCode (still restarting?).';
      });
    }
    await _checkAll();
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _status = 'Done — OpenCode answered in ${sw.elapsedMilliseconds} ms.';
      });
    }
  }

  Future<void> _checkAll() async {
    final results = await Future.wait(
      kServices.entries.map((e) async => MapEntry(e.key, await _ping(e.value))),
    );
    if (!mounted) return;
    setState(() {
      for (final r in results) {
        _dots[r.key] = r.value;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  @override
  Widget build(BuildContext context) {
    final up = _dots.values.where((v) => v == true).length;
    return Scaffold(
      appBar: AppBar(title: const Text('OC Restart ↺')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _busy ? null : _restart,
                  icon: _busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('↺', style: TextStyle(fontSize: 28)),
                  label: const Text('Restart OpenCode',
                      style: TextStyle(fontSize: 20)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(260, 72),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_status, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text('Services up: $up / ${_dots.length}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final e in _dots.entries)
                      Chip(
                        avatar: Icon(
                          Icons.circle,
                          size: 12,
                          color: e.value == null
                              ? Colors.grey
                              : (e.value! ? Colors.green : Colors.red),
                        ),
                        label: Text(e.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _checkAll,
        tooltip: 'Refresh status',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
