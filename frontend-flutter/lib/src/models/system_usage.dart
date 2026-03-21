class SystemUsage {
  SystemUsage({
    this.cpuPercent,
    this.memPercent,
    this.memUsedMb,
    this.memTotalMb,
    this.gpuPercent,
    this.gpuMemUsedMb,
    this.gpuMemTotalMb,
  });

  final num? cpuPercent;
  final num? memPercent;
  final num? memUsedMb;
  final num? memTotalMb;
  final num? gpuPercent;
  final num? gpuMemUsedMb;
  final num? gpuMemTotalMb;

  factory SystemUsage.fromJson(Map<String, dynamic> json) {
    return SystemUsage(
      cpuPercent: json['cpu_percent'] as num?,
      memPercent: json['mem_percent'] as num?,
      memUsedMb: json['mem_used_mb'] as num?,
      memTotalMb: json['mem_total_mb'] as num?,
      gpuPercent: json['gpu_percent'] as num?,
      gpuMemUsedMb: json['gpu_mem_used_mb'] as num?,
      gpuMemTotalMb: json['gpu_mem_total_mb'] as num?,
    );
  }

  String formatMb(num? mb) {
    if (mb == null) return '—';
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.round()} MB';
  }

  String get memDisplay {
    if (memUsedMb == null || memTotalMb == null) return '—';
    return '${formatMb(memUsedMb)} / ${formatMb(memTotalMb)}';
  }

  String get gpuMemDisplay {
    if (gpuMemUsedMb == null || gpuMemTotalMb == null) return '—';
    return '${formatMb(gpuMemUsedMb)} / ${formatMb(gpuMemTotalMb)}';
  }
}
