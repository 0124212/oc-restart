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

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  bool get connected => _connected;

  void connect() {
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
        _scheduleReconnect();
      },
      onError: (_) {
        _connected = false;
        _scheduleReconnect();
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
    final cols = w > 900 ? 2 : 1;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('ak'),
            const SizedBox(width: 8),
            Icon(
              _connected ? Icons.wifi : Icons.wifi_off,
              color: _connected ? Colors.green : Colors.red,
              size: 18,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _sync.restart('opencode'),
          ),
        ],
      ),
      body: cols == 1 ? _buildList() : _buildGrid(cols),
    );
  }

  Widget _buildList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_status != null) _buildStatusCard(),
        const SizedBox(height: 12),
        _buildRestartButton(),
        const SizedBox(height: 12),
        if (_services.isNotEmpty) _buildServicesCard(),
      ],
    );
  }

  Widget _buildGrid(int cols) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      childAspectRatio: 1.6,
      children: [
        if (_status != null) _buildStatusCard(),
        _buildRestartButton(),
        if (_services.isNotEmpty) _buildServicesCard(),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Server', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            _row('Uptime', _status!['uptime'] ?? '—'),
            _row('CPU', '${_status!['load'] ?? '—'}  ·  ${_status!['temp'] ?? '—'}'),
            _row('Memory', _status!['mem'] ?? '—'),
            _row('Disk', _status!['disk'] ?? '—'),
            _row('OpenCode', _status!['opencode'] ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    final isUp = v == 'active' || v == 'running';
    final isDown = v == 'inactive' || v == 'failed';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          isUp || isDown
              ? Chip(
                  label: Text(v, style: const TextStyle(fontSize: 12)),
                  backgroundColor: isUp ? Colors.green.shade900 : Colors.red.shade900,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              : Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildRestartButton() {
    return Card(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _sync.restart('opencode'),
          icon: const Icon(Icons.restart_alt, size: 28),
          label: const Text('Restart OpenCode Server', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildServicesCard() {
    final running = _services.where((s) => s['state'] == 'running').length;
    final total = _services.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  label: Text('$running/$total up', style: const TextStyle(fontSize: 12)),
                  backgroundColor: running == total ? Colors.green.shade900 : Colors.orange.shade900,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _services.length,
                itemBuilder: (ctx, i) {
                  final s = _services[i];
                  final isUp = s['state'] == 'running';
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isUp ? Icons.circle : Icons.circle_outlined,
                      color: isUp ? Colors.green : Colors.red,
                      size: 12,
                    ),
                    title: Text(s['name'], style: const TextStyle(fontSize: 14)),
                    subtitle: Text(s['status'] ?? '', style: const TextStyle(fontSize: 11)),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'restart') _sync.restart(s['name']);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'restart', child: Text('Restart')),
                      ],
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
