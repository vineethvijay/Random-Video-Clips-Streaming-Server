class SystemUsage {
  SystemUsage({
    this.cpuPercent,
    this.memPercent,
    this.gpuPercent,
  });

  final num? cpuPercent;
  final num? memPercent;
  final num? gpuPercent;

  factory SystemUsage.fromJson(Map<String, dynamic> json) {
    return SystemUsage(
      cpuPercent: json['cpu_percent'] as num?,
      memPercent: json['mem_percent'] as num?,
      gpuPercent: json['gpu_percent'] as num?,
    );
  }
}
