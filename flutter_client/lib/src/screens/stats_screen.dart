import 'package:flutter/material.dart';

import '../services/streaming_api.dart';
import '../widgets/dashboard_header.dart';

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
  int _modelsPage = 1;
  int _audioPage = 1;
  static const int _modelsPerPage = 12;
  static const int _audioPerPage = 12;

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
        _modelsPage = 1;
        _audioPage = 1;
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
    final modelsTotalPages = models.isEmpty ? 1 : (models.length / _modelsPerPage).ceil();
    final audioTotalPages = audio.isEmpty ? 1 : (audio.length / _audioPerPage).ceil();
    final modelsPage = _modelsPage.clamp(1, modelsTotalPages);
    final audioPage = _audioPage.clamp(1, audioTotalPages);
    final modelsStart = (modelsPage - 1) * _modelsPerPage;
    final audioStart = (audioPage - 1) * _audioPerPage;
    final modelsEnd = (modelsStart + _modelsPerPage).clamp(0, models.length);
    final audioEnd = (audioStart + _audioPerPage).clamp(0, audio.length);
    final modelsPageItems = models.isEmpty ? <dynamic>[] : models.sublist(modelsStart, modelsEnd);
    final audioPageItems = audio.isEmpty ? <dynamic>[] : audio.sublist(audioStart, audioEnd);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DashboardHeader(
                  title: 'Stats',
                  onRefresh: _loading ? null : _load,
                ),
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
                          ...modelsPageItems.map((m) {
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
                        if (models.isNotEmpty)
                          _pager(
                            page: modelsPage,
                            totalPages: modelsTotalPages,
                            onPrev: modelsPage > 1
                                ? () => setState(() => _modelsPage = modelsPage - 1)
                                : null,
                            onNext: modelsPage < modelsTotalPages
                                ? () => setState(() => _modelsPage = modelsPage + 1)
                                : null,
                          ),
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
                          ...audioPageItems.map((a) {
                            final aa = a as Map<String, dynamic>;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${aa['name'] ?? '-'}'),
                              subtitle: Text('${aa['seconds'] ?? 0}s • ${aa['chunks'] ?? 0} chunks'),
                              trailing: Text('${aa['time_display'] ?? '-'}'),
                            );
                          }),
                        if (audio.isNotEmpty)
                          _pager(
                            page: audioPage,
                            totalPages: audioTotalPages,
                            onPrev: audioPage > 1
                                ? () => setState(() => _audioPage = audioPage - 1)
                                : null,
                            onNext: audioPage < audioTotalPages
                                ? () => setState(() => _audioPage = audioPage + 1)
                                : null,
                          ),
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

  Widget _pager({
    required int page,
    required int totalPages,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          OutlinedButton(onPressed: onPrev, child: const Text('Prev')),
          const SizedBox(width: 10),
          Text('Page $page of $totalPages'),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}
