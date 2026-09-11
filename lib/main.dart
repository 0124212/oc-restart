import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const OcRestartApp());

class OcRestartApp extends StatelessWidget {
  const OcRestartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OC Restart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const Dashboard(),
    );
  }
}

// ─── Sync Service (WebSocket) ────────────────────────────
class SyncService {
  static const _token = 'd204f2016b28c0c50c793df833c9be3d370662a5dcfc5c8ebedf110e034388a9';
  static const _wsUrl = 'ws://100.115.178.90:4099?token=$_token';

  WebSocketChannel? _ws;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnect;
  bool _connected = false;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  bool get connected => _connected;

  void connect() {
    if (_disposed) return;
    _ws = WebSocketChannel.connect(Uri.parse(_wsUrl));
    _ws!.sink.add(_token);

    _ws!.stream.listen(
      (data) {
        _connected = true;
        try {
          _controller.add(jsonDecode(data));
        } catch (_) {}
      },
      onDone: () {
        _connected = false;
        if (!_disposed) _scheduleReconnect();
      },
      onError: (_) {
        _connected = false;
        if (!_disposed) _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), connect);
  }

  void restart(String target) {
    _ws?.sink.add(jsonEncode({'type': 'restart', 'target': target}));
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _ws?.sink.close();
    _controller.close();
  }
}

// ─── Dashboard ───────────────────────────────────────────
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final _sync = SyncService();
  Map<String, dynamic>? _status;
  List<dynamic> _services = [];
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _sync.stream.listen((msg) {
      if (msg['type'] == 'snapshot') {
        setState(() {
          _status = msg['status'];
          _services = msg['services'] ?? [];
          _connected = _sync.connected;
        });
      } else if (msg['type'] == 'restarted') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${msg['target']} restarting…'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
    _sync.connect();
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 900;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('ak', style: TextStyle(fontSize: isWide ? 28 : 22)),
            const SizedBox(width: 12),
            Icon(
              _connected ? Icons.wifi : Icons.wifi_off,
              color: _connected ? Colors.green : Colors.red,
              size: isWide ? 26 : 20,
            ),
            const SizedBox(width: 8),
            if (_connected)
              Text('LIVE', style: TextStyle(color: Colors.green.shade300, fontSize: isWide ? 16 : 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _sync.restart('opencode'),
              icon: const Icon(Icons.restart_alt, size: 22),
              label: const Text('Restart Server'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  // ─── iPhone layout ───────────────────────────────────
  Widget _buildNarrowLayout() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_status != null) _buildStatusCard(fontSize: 16, padding: 20),
        const SizedBox(height: 16),
        _buildRestartButton(),
        const SizedBox(height: 16),
        if (_services.isNotEmpty) _buildServicesCard(fontSize: 15, padding: 20),
      ],
    );
  }

  // ─── iPad / desktop layout ───────────────────────────
  Widget _buildWideLayout() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Top row: status + restart
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildStatusCard(fontSize: 22, padding: 28)),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _buildRestartButton(height: 280)),
            ],
          ),
          const SizedBox(height: 24),
          // Bottom row: services full width
          Expanded(child: _buildServicesCard(fontSize: 18, padding: 28)),
        ],
      ),
    );
  }

  // ─── Status Card ─────────────────────────────────────
  Widget _buildStatusCard({required double fontSize, required double padding}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns, size: fontSize + 6, color: Colors.teal),
                const SizedBox(width: 12),
                Text('Server', style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: padding * 0.5),
            _statRow('Uptime', _status!['uptime'] ?? '—', fontSize),
            _statRow('CPU', '${_status!['load'] ?? '—'}  ·  ${_status!['temp'] ?? '—'}', fontSize),
            _statRow('Memory', _status!['mem'] ?? '—', fontSize),
            _statRow('Disk', _status!['disk'] ?? '—', fontSize),
            _statRow('OpenCode', _status!['opencode'] ?? '—', fontSize, isStatus: true),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, double fontSize, {bool isStatus = false}) {
    final isUp = value == 'active' || value == 'running';
    final isDown = value == 'inactive' || value == 'failed';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.35),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey, fontSize: fontSize - 2)),
          SizedBox(width: 16),
          Flexible(
            child: isStatus
                ? Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isUp ? Colors.green.shade900 : isDown ? Colors.red.shade900 : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(value, style: TextStyle(fontSize: fontSize - 3, fontWeight: FontWeight.w600)),
                  )
                : Text(value, style: TextStyle(fontWeight: FontWeight.w500, fontSize: fontSize - 2)),
          ),
        ],
      ),
    );
  }

  // ─── Restart Button ──────────────────────────────────
  Widget _buildRestartButton({double? height}) {
    return Card(
      elevation: 2,
      child: height != null
          ? SizedBox(
              height: height,
              child: _buildRestartContent(isCompact: false),
            )
          : _buildRestartContent(isCompact: true),
    );
  }

  Widget _buildRestartContent({required bool isCompact}) {
    return Padding(
      padding: EdgeInsets.all(isCompact ? 16 : 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restart_alt, size: isCompact ? 36 : 56, color: Colors.teal),
          SizedBox(height: isCompact ? 8 : 12),
          Text(
            'Restart',
            style: TextStyle(fontSize: isCompact ? 16 : 22, fontWeight: FontWeight.bold),
          ),
          Text(
            'OpenCode Server',
            style: TextStyle(fontSize: isCompact ? 13 : 16, color: Colors.grey),
          ),
          SizedBox(height: isCompact ? 12 : 16),
          SizedBox(
            width: double.infinity,
            height: isCompact ? 48 : 56,
            child: FilledButton.icon(
              onPressed: () => _sync.restart('opencode'),
              icon: const Icon(Icons.power_settings_new, size: 24),
              label: Text(
                'RESTART',
                style: TextStyle(fontSize: isCompact ? 16 : 18, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Services Card ───────────────────────────────────
  Widget _buildServicesCard({required double fontSize, required double padding}) {
    final running = _services.where((s) => s['state'] == 'running').length;
    final total = _services.length;

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.apps, size: fontSize + 4, color: Colors.teal),
                const SizedBox(width: 12),
                Text('Services', style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: running == total ? Colors.green.shade900 : Colors.orange.shade900,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$running/$total up', style: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            SizedBox(height: padding * 0.4),
            const Divider(),
            SizedBox(height: padding * 0.2),
            Expanded(
              child: ListView.builder(
                itemCount: _services.length,
                itemBuilder: (ctx, i) {
                  final s = _services[i];
                  final isUp = s['state'] == 'running';
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      leading: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isUp ? Colors.green : Colors.red,
                          boxShadow: [
                            BoxShadow(
                              color: (isUp ? Colors.green : Colors.red).withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      title: Text(s['name'], style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
                      subtitle: Text(s['status'] ?? '', style: TextStyle(fontSize: fontSize - 4, color: Colors.grey)),
                      trailing: IconButton(
                        icon: Icon(Icons.restart_alt, size: fontSize + 2, color: Colors.teal),
                        onPressed: () => _sync.restart(s['name']),
                        tooltip: 'Restart ${s['name']}',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.teal.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
