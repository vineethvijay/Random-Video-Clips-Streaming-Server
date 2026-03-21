import 'package:flutter/material.dart';

import '../services/streaming_api.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.api});

  final StreamingApi api;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getStats();
      if (!mounted) return;
      setState(() {
        _stats = data;
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

  @override
  Widget build(BuildContext context) {
    final stream = _stats?['stream_stats'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final playCounts = _stats?['play_counts'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final models = playCounts['models'] as List<dynamic>? ?? <dynamic>[];
    final audio = playCounts['audio'] as List<dynamic>? ?? <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stream Stats', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _kv('Time played', '${stream['time_played'] ?? '-'}'),
                        _kv('Chunks pushed', '${stream['chunks_pushed'] ?? '-'}'),
                        _kv('Chunks created', '${stream['chunks_created_total'] ?? '-'}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top Models (${models.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (models.isEmpty)
                          const Text('No model stats yet')
                        else
                          ...models.take(30).map((m) {
                            final mm = m as Map<String, dynamic>;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${mm['username'] ?? mm['url'] ?? '-'}'),
                              subtitle: Text(
                                  '${mm['platform'] ?? 'other'}${(mm['channel'] ?? '').toString().isNotEmpty ? ' • ${mm['channel']}' : ''}'),
                              trailing: Text('${mm['count'] ?? 0}x'),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top Audio (${audio.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (audio.isEmpty)
                          const Text('No audio stats yet')
                        else
                          ...audio.take(30).map((a) {
                            final aa = a as Map<String, dynamic>;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${aa['name'] ?? '-'}'),
                              subtitle: Text('${aa['seconds'] ?? 0}s • ${aa['chunks'] ?? 0} chunks'),
                              trailing: Text('${aa['time_display'] ?? '-'}'),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(k)),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
