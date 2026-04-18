import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/api_provider.dart';
import '../providers/stream_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/glass_card.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loader.dart';
import '../widgets/stat_card.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _busy = false;
  bool _editingSettings = false;
  int _cronPage = 1;
  static const int _cronPerPage = 6;

  final TextEditingController _cronController = TextEditingController();
  final Map<String, TextEditingController> _settingControllers = {};
  bool _controllersInitialised = false;

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
  void dispose() {
    _cronController.dispose();
    for (final c in _settingControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initControllers(Map<String, dynamic> ctx) {
    if (_controllersInitialised) return;
    _controllersInitialised = true;
    final settings = (ctx['settings'] as Map<String, dynamic>?) ?? {};
    for (final key in _editableKeys) {
      _settingControllers[key]?.dispose();
      _settingControllers[key] =
          TextEditingController(text: '${settings[key] ?? ''}');
    }
    _cronController.text = '${ctx['cron_schedule'] ?? ''}';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(String ok, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(ok);
      _controllersInitialised = false;
      ref.read(adminContextProvider.notifier).refresh();
      ref.read(cronHistoryProvider.notifier).refresh();
      ref.read(serverStatusProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _testBusy = false;
  int _testElapsed = 0;
  DateTime? _testEta;

  Future<void> _runTestChunk() async {
    if (_testBusy || _busy) return;
    setState(() {
      _testBusy = true;
      _testElapsed = 0;
      _testEta = DateTime.now().add(const Duration(seconds: 60));
    });
    final ticker = Stream.periodic(const Duration(seconds: 1), (i) => i + 1)
        .listen((s) {
      if (mounted) {
        setState(() => _testElapsed = s);
      }
    });
    try {
      final api = ref.read(apiProvider);
      await api.generateTestChunk();
      if (!mounted) return;
      _toast('Test chunk ready!');
      final playUrl = Uri.parse('http://streamer.homelab.local/chunks/test_clip_10s.mp4');
      await launchUrl(playUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    } finally {
      ticker.cancel();
      if (mounted) {
        setState(() {
          _testBusy = false;
          _testEta = null;
        });
      }
    }
  }

  String get _testCountdownLabel {
    if (_testEta == null) return 'Generating...';
    final remaining = _testEta!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) return 'Almost done... ${_testElapsed}s';
    final etaTime =
        '${_testEta!.hour.toString().padLeft(2, '0')}:${_testEta!.minute.toString().padLeft(2, '0')}:${_testEta!.second.toString().padLeft(2, '0')}';
    return '~${remaining}s left (ETA $etaTime)';
  }

  Future<void> _refresh() async {
    _controllersInitialised = false;
    ref.read(adminContextProvider.notifier).refresh();
    ref.read(cronHistoryProvider.notifier).refresh();
    ref.read(serverStatusProvider.notifier).refresh();
    ref.read(systemUsageProvider.notifier).refresh();
    ref.read(streamStatusProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ctxAsync = ref.watch(adminContextProvider);
    final cronAsync = ref.watch(cronHistoryProvider);
    final serverAsync = ref.watch(serverStatusProvider);
    final streamAsync = ref.watch(streamStatusProvider);
    final usageAsync = ref.watch(systemUsageProvider);

    // Initialise controllers when data is available
    ctxAsync.whenData((ctx) => _initControllers(ctx));

    final isLoading = ctxAsync.isLoading && !ctxAsync.hasValue;

    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  const ShimmerStatRow(count: 3),
                  const SizedBox(height: 16),
                  ShimmerLoader(count: 3, height: 100),
                ]),
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: SelectionArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      SectionHeader(
                        title: 'Admin Panel',
                        subtitle: 'Server management',
                        icon: Icons.admin_panel_settings_rounded,
                        onRefresh: _refresh,
                      ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
                      const SizedBox(height: 20),
                      _buildLiveStatsRow(context, streamAsync, usageAsync),
                      const SizedBox(height: 16),
                      _buildGauges(context, usageAsync),
                      const SizedBox(height: 16),
                      _buildActionsCard(context, serverAsync),
                      const SizedBox(height: 16),
                      _buildCronCard(context, cronAsync),
                      const SizedBox(height: 16),
                      _buildSettingsCard(context),
                      const SizedBox(height: 16),
                      _buildSystemInfoCard(context, ctxAsync, usageAsync),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Live stats strip ──

  Widget _buildLiveStatsRow(BuildContext context,
      AsyncValue streamAsync, AsyncValue usageAsync) {
    final st = streamAsync.valueOrNull;
    final su = usageAsync.valueOrNull;
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
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  // ── Gauges ──

  Widget _buildGauges(BuildContext context, AsyncValue usageAsync) {
    final su = usageAsync.valueOrNull;
    if (su == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: GaugeWidget(
            value: su.cpuPercent?.toDouble() ?? 0,
            label: 'CPU',
            subtitle: '${su.cpuPercent?.toStringAsFixed(0) ?? 0}%',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GaugeWidget(
            value: su.memPercent?.toDouble() ?? 0,
            label: 'Memory',
            subtitle: su.memDisplay,
          ),
        ),
        if (su.gpuPercent != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: GaugeWidget(
              value: su.gpuPercent!.toDouble(),
              label: 'GPU',
              subtitle: su.gpuMemDisplay,
            ),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 150.ms);
  }

  // ── Actions card ──

  Widget _buildActionsCard(BuildContext context, AsyncValue serverAsync) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final genRunning = serverAsync.valueOrNull?.generationInProgress == true;
    final api = ref.read(apiProvider);

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accentAmber),
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
                    : () => _run(
                        'Chunk generation triggered', api.generateChunks),
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Generate Chunks'),
              ),
              OutlinedButton.icon(
                onPressed: (_testBusy || _busy) ? null : _runTestChunk,
                icon: _testBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.science_rounded, size: 18),
                label: Text(_testBusy
                    ? _testCountdownLabel
                    : 'Test 10s Clip'),
              ),
              if (genRunning)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run('Stop signal sent', api.stopGeneration),
                  icon: Icon(Icons.stop_rounded,
                      size: 18, color: AppTheme.accentRose),
                  label: Text('Stop',
                      style: TextStyle(color: AppTheme.accentRose)),
                ),
              if (genRunning)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run('Lock cleared', api.clearGenerationLock),
                  icon: Icon(Icons.lock_open_rounded,
                      size: 18, color: AppTheme.accentAmber),
                  label: Text('Clear Lock',
                      style: TextStyle(color: AppTheme.accentAmber)),
                ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('chunk-generator restarted',
                        api.restartChunkGenerator),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Restart Generator'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  // ── Cron card ──

  Widget _buildCronCard(
      BuildContext context, AsyncValue<List<dynamic>> cronAsync) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final api = ref.read(apiProvider);
    final cronEntries = cronAsync.valueOrNull ?? [];
    final totalPages =
        cronEntries.isEmpty ? 1 : (cronEntries.length / _cronPerPage).ceil();
    final page = _cronPage.clamp(1, totalPages);
    final start = (page - 1) * _cronPerPage;
    final end = (start + _cronPerPage).clamp(0, cronEntries.length);
    final pageItems =
        cronEntries.isEmpty ? <dynamic>[] : cronEntries.sublist(start, end);

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
                    : () => _run('Cron updated',
                        () => api.setCron(_cronController.text.trim())),
                child: const Text('Set'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run('Cron removed', api.removeCron),
                child: const Text('Remove'),
              ),
            ],
          ),
          if (cronEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Run History',
                style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
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
              PaginationBar(
                page: page,
                totalPages: totalPages,
                onPrev: () => setState(() => _cronPage = page - 1),
                onNext: () => setState(() => _cronPage = page + 1),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No run history yet',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 250.ms);
  }

  // ── Settings card ──

  Widget _buildSettingsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final api = ref.read(apiProvider);

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
                  _editingSettings
                      ? Icons.lock_open_rounded
                      : Icons.edit_rounded,
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
                        return api.updateSettings(payload);
                      }),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Settings'),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  // ── System info ──

  Widget _buildSystemInfoCard(BuildContext context,
      AsyncValue<Map<String, dynamic>> ctxAsync, AsyncValue usageAsync) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ctx = ctxAsync.valueOrNull ?? {};
    final sys = (ctx['sys_info'] as Map<String, dynamic>?) ?? {};

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
          _infoRow(context, 'Disk', '${sys['chunks_total_mb'] ?? '—'} MB'),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 350.ms);
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
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
