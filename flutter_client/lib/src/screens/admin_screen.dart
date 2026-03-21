import 'dart:async';

import 'package:flutter/material.dart';

import '../models/server_status.dart';
import '../models/stream_status.dart';
import '../models/system_usage.dart';
import '../services/streaming_api.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_progress_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_card.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.api});
  final StreamingApi api;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _ctx;
  List<dynamic> _cronEntries = <dynamic>[];
  int _cronPage = 1;
  static const int _cronPerPage = 6;
  StreamStatus? _streamStatus;
  SystemUsage? _systemUsage;
  ServerStatus? _serverStatus;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _editingSettings = false;
  Timer? _pollTimer;

  final TextEditingController _cronController = TextEditingController();
  final Map<String, TextEditingController> _settingControllers = {};

  static const _editableKeys = <String>[
    'MAX_CHUNKS',
    'CHUNK_DURATION',
    'CLIP_MIN',
    'CLIP_MAX',
    'CHUNKS_PER_RUN',
    'HW_ACCEL',
  ];

  static const _settingDescriptions = <String, String>{
    'MAX_CHUNKS': 'Maximum chunks to keep',
    'CHUNK_DURATION': 'Duration per chunk (sec)',
    'CLIP_MIN': 'Min clip length (sec)',
    'CLIP_MAX': 'Max clip length (sec)',
    'CHUNKS_PER_RUN': 'Chunks generated per run',
    'HW_ACCEL': 'Hardware acceleration',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadLive(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cronController.dispose();
    for (final c in _settingControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.getAdminContext(),
        widget.api.getCronHistory(page: 1, perPage: 40),
        widget.api.getServerStatus(),
        widget.api.getStreamStatus(),
        widget.api.getSystemUsage(),
      ]);
      final ctx = results[0] as Map<String, dynamic>;
      final cron = results[1] as Map<String, dynamic>;
      final status = results[2] as ServerStatus;
      final streamStatus = results[3] as StreamStatus;
      final systemUsage = results[4] as SystemUsage;

      final settings = (ctx['settings'] as Map<String, dynamic>?) ?? {};
      for (final key in _editableKeys) {
        _settingControllers[key]?.dispose();
        _settingControllers[key] =
            TextEditingController(text: '${settings[key] ?? ''}');
      }
      _cronController.text = '${ctx['cron_schedule'] ?? ''}';

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _cronEntries = cron['entries'] as List<dynamic>? ?? [];
        _serverStatus = status;
        _streamStatus = streamStatus;
        _systemUsage = systemUsage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _loadLive() async {
    try {
      final results = await Future.wait<dynamic>([
        widget.api.getStreamStatus(),
        widget.api.getSystemUsage(),
        widget.api.getServerStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _streamStatus = results[0] as StreamStatus;
        _systemUsage = results[1] as SystemUsage;
        _serverStatus = results[2] as ServerStatus;
      });
    } catch (_) {}
  }

  Future<void> _run(String ok, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ok)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildLiveStatsRow(context),
                    const SizedBox(height: 16),
                    _buildActionsCard(context),
                    const SizedBox(height: 16),
                    _buildCronCard(context),
                    const SizedBox(height: 16),
                    _buildSettingsCard(context),
                    const SizedBox(height: 16),
                    _buildSystemInfoCard(context),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [
              cs.primary.withValues(alpha: 0.3),
              cs.tertiary.withValues(alpha: 0.2),
            ]),
            border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.admin_panel_settings_rounded,
              color: cs.primary, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin Panel',
                  style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              Text('Server management',
                  style:
                      tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  // ── Live stats strip ──

  Widget _buildLiveStatsRow(BuildContext context) {
    final st = _streamStatus;
    final su = _systemUsage;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        StatCard(
          label: 'Current Chunk',
          value: st?.currentChunk ?? '—',
          icon: Icons.live_tv_rounded,
          gradientStart: AppTheme.nowPlayingBlue.withValues(alpha: 0.15),
          gradientEnd: AppTheme.nowPlayingBlue.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Current Audio',
          value: st?.currentAudio ?? '—',
          icon: Icons.music_note_rounded,
          gradientStart: AppTheme.accentEmerald.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentEmerald.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'CPU',
          value: su?.cpuPercent != null
              ? '${su!.cpuPercent!.toStringAsFixed(1)}%'
              : '—',
          icon: Icons.memory_rounded,
          gradientStart: AppTheme.accentAmber.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentAmber.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'Memory',
          value: su?.memPercent != null
              ? '${su!.memPercent!.toStringAsFixed(1)}%'
              : '—',
          icon: Icons.storage_rounded,
          gradientStart: AppTheme.accentRose.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentRose.withValues(alpha: 0.05),
        ),
        StatCard(
          label: 'GPU',
          value: su?.gpuPercent != null
              ? '${su!.gpuPercent!.toStringAsFixed(1)}%'
              : '—',
          icon: Icons.developer_board_rounded,
          gradientStart: AppTheme.accentCyan.withValues(alpha: 0.15),
          gradientEnd: AppTheme.accentCyan.withValues(alpha: 0.05),
        ),
      ],
    );
  }

  // ── Actions card ──

  Widget _buildActionsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final genRunning = _serverStatus?.generationInProgress == true;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Actions',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (genRunning)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentAmber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Generating…',
                          style: tt.labelSmall?.copyWith(
                              color: AppTheme.accentAmber,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('Chunk generation triggered',
                        widget.api.generateChunks),
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Generate Chunks'),
              ),
              if (genRunning)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () =>
                          _run('Stop signal sent', widget.api.stopGeneration),
                  icon: Icon(Icons.stop_rounded,
                      size: 18, color: AppTheme.accentRose),
                  label: Text('Stop',
                      style: TextStyle(color: AppTheme.accentRose)),
                ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('chunk-generator restarted',
                        widget.api.restartChunkGenerator),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Restart Generator'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Cron card ──

  Widget _buildCronCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totalPages = _cronEntries.isEmpty
        ? 1
        : (_cronEntries.length / _cronPerPage).ceil();
    final page = _cronPage.clamp(1, totalPages);
    final start = (page - 1) * _cronPerPage;
    final end = (start + _cronPerPage).clamp(0, _cronEntries.length);
    final pageItems = _cronEntries.isEmpty
        ? <dynamic>[]
        : _cronEntries.sublist(start, end);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Cron Schedule',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cronController,
                  style: tt.bodySmall,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'e.g. 0 2 * * *',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run('Cron updated', () {
                          return widget.api
                              .setCron(_cronController.text.trim());
                        }),
                child: const Text('Set'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run('Cron removed', widget.api.removeCron),
                child: const Text('Remove'),
              ),
            ],
          ),
          if (_cronEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Run History',
                style: tt.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...pageItems.map((e) {
              final m = e as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${m['timestamp'] ?? '—'}',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${m['trigger'] ?? 'cron'}',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              );
            }),
            if (totalPages > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Page $page of $totalPages',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    Row(children: [
                      IconButton(
                        onPressed: page > 1
                            ? () =>
                                setState(() => _cronPage = page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: page < totalPages
                            ? () =>
                                setState(() => _cronPage = page + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No run history yet',
                  style:
                      tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  // ── Settings card ──

  Widget _buildSettingsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('Server Configuration',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _editingSettings = !_editingSettings),
                icon: Icon(
                  _editingSettings ? Icons.lock_open_rounded : Icons.edit_rounded,
                  size: 16,
                ),
                label: Text(_editingSettings ? 'Editing' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._editableKeys.map((key) {
            final ctrl = _settingControllers[key] ?? TextEditingController();
            final desc = _settingDescriptions[key] ?? key;
            if (!_editingSettings) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 170,
                      child: Text(desc,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    Expanded(
                      child: Text(ctrl.text,
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: ctrl,
                style: tt.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: desc,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            );
          }),
          if (_editingSettings) ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run('Settings saved', () {
                        final payload = <String, dynamic>{};
                        for (final k in _editableKeys) {
                          payload[k] =
                              _settingControllers[k]?.text.trim() ?? '';
                        }
                        return widget.api.updateSettings(payload);
                      }),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Settings'),
            ),
          ],
        ],
      ),
    );
  }

  // ── System info ──

  Widget _buildSystemInfoCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sys = (_ctx?['sys_info'] as Map<String, dynamic>?) ?? {};
    final su = _systemUsage;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.computer_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('System Info',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(context, 'OS', '${sys['os'] ?? '—'}'),
          _infoRow(context, 'CPU Cores', '${sys['cpu_cores'] ?? '—'}'),
          _infoRow(context, 'HW Accel', '${sys['hw_accel'] ?? '—'}'),
          _infoRow(context, 'Chunks', '${sys['chunks_count'] ?? '—'}'),
          _infoRow(
              context, 'Disk', '${sys['chunks_total_mb'] ?? '—'} MB'),
          if (su != null) ...[
            const SizedBox(height: 12),
            Text('Live Usage',
                style: tt.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _gauge(context, 'CPU', su.cpuPercent, AppTheme.accentAmber),
            const SizedBox(height: 6),
            _gauge(context, 'Memory', su.memPercent, AppTheme.accentRose),
            if (su.memUsedMb != null)
              Padding(
                padding: const EdgeInsets.only(left: 54, bottom: 6),
                child: Text(su.memDisplay,
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            if (su.gpuPercent != null) ...[
              _gauge(context, 'GPU', su.gpuPercent, AppTheme.accentCyan),
              if (su.gpuMemUsedMb != null)
                Padding(
                  padding: const EdgeInsets.only(left: 54, bottom: 6),
                  child: Text(su.gpuMemDisplay,
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String key, String value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(key,
                style: tt.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: tt.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _gauge(
      BuildContext context, String label, num? value, Color color) {
    final pct = value?.toDouble() ?? 0;
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedProgressBar(
            progress: pct / 100,
            height: 8,
            startColor: color.withValues(alpha: 0.6),
            endColor: color,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text('${pct.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ],
    );
  }
}
