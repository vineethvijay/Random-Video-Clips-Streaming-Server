import 'package:flutter/material.dart';

import '../services/streaming_api.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.api});

  final StreamingApi api;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _ctx;
  List<dynamic> _cronEntries = <dynamic>[];
  bool _generationInProgress = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final TextEditingController _cronController = TextEditingController();
  final Map<String, TextEditingController> _settingControllers =
      <String, TextEditingController>{};

  static const _editableKeys = <String>[
    'MAX_CHUNKS',
    'CHUNK_DURATION',
    'CLIP_MIN',
    'CLIP_MAX',
    'CHUNKS_PER_RUN',
    'HW_ACCEL',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cronController.dispose();
    for (final c in _settingControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.getAdminContext(),
        widget.api.getCronHistory(page: 1, perPage: 20),
        widget.api.getServerStatus(),
      ]);
      final ctx = results[0] as Map<String, dynamic>;
      final cron = results[1] as Map<String, dynamic>;
      final status = results[2] as dynamic;

      final settings = (ctx['settings'] as Map<String, dynamic>? ?? <String, dynamic>{});
      for (final key in _editableKeys) {
        _settingControllers[key]?.dispose();
        _settingControllers[key] = TextEditingController(text: '${settings[key] ?? ''}');
      }
      _cronController.text = '${ctx['cron_schedule'] ?? ''}';

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _cronEntries = cron['entries'] as List<dynamic>? ?? <dynamic>[];
        _generationInProgress = status.generationInProgress == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _run(String okMsg, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _actionsCard(),
                const SizedBox(height: 12),
                _cronCard(),
                const SizedBox(height: 12),
                _settingsCard(),
                const SizedBox(height: 12),
                _systemInfoCard(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
    );
  }

  Widget _actionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        'Chunk generation triggered',
                        widget.api.generateChunks,
                      ),
              child: const Text('Generate Chunks'),
            ),
            ElevatedButton(
              onPressed: _busy || !_generationInProgress
                  ? null
                  : () => _run('Stop signal sent', widget.api.stopGeneration),
              child: const Text('Stop Generation'),
            ),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        'chunk-generator restarted',
                        widget.api.restartChunkGenerator,
                      ),
              child: const Text('Restart chunk-generator'),
            ),
            Chip(
              label: Text(_generationInProgress ? 'Generation running' : 'Generation idle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cronCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cron Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _cronController,
              decoration: const InputDecoration(
                labelText: 'Cron expression (e.g. 0 2 * * *)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run('Cron schedule updated', () {
                            return widget.api.setCron(_cronController.text.trim());
                          }),
                  child: const Text('Set Schedule'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run('Cron schedule removed', widget.api.removeCron),
                  child: const Text('Remove Schedule'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('Recent run history', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_cronEntries.isEmpty)
              const Text('No run history yet')
            else
              ..._cronEntries.take(8).map((e) {
                final m = e as Map<String, dynamic>;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${m['timestamp'] ?? '-'}'),
                  trailing: Text('${m['trigger'] ?? 'cron'}'),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Server Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._editableKeys.map((key) {
              final c = _settingControllers[key] ?? TextEditingController();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: c,
                  decoration: InputDecoration(
                    labelText: key,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run('Settings saved', () {
                        final payload = <String, dynamic>{};
                        for (final k in _editableKeys) {
                          payload[k] = _settingControllers[k]?.text.trim() ?? '';
                        }
                        return widget.api.updateSettings(payload);
                      }),
              child: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _systemInfoCard() {
    final sys = (_ctx?['sys_info'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('System Info', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _kv('OS', '${sys['os'] ?? '-'}'),
            _kv('CPU cores', '${sys['cpu_cores'] ?? '-'}'),
            _kv('HW accel', '${sys['hw_accel'] ?? '-'}'),
            _kv('Chunks', '${sys['chunks_count'] ?? '-'}'),
            _kv('Chunk disk MB', '${sys['chunks_total_mb'] ?? '-'}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(k)),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
