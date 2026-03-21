class ServerStatus {
  ServerStatus({
    this.generationInProgress = false,
  });

  final bool generationInProgress;

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    return ServerStatus(
      generationInProgress: json['generation_in_progress'] == true,
    );
  }
}
