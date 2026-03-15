/// State object for PiP mode changes
class PipState {
  final bool isInPipMode;
  final int? playerId;

  const PipState({required this.isInPipMode, this.playerId});

  @override
  String toString() => 'PipState(isInPipMode: $isInPipMode, playerId: $playerId)';
}
