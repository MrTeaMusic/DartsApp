/// Ein Computergegner mit Namen und ungefährem 3-Dart-Average.
class CpuPlayer {
  const CpuPlayer(this.name, this.average);

  final String name;

  /// Ungefährer 3-Dart-Average des echten Vorbilds (bei 100 % Stärke).
  final double average;

  static const int maxNameLength = 40;
  static const double minAverage = 20;
  static const double maxAverage = 120;

  Map<String, Object?> toJson() => {'name': name, 'average': average};

  static CpuPlayer? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final avg = json['average'];
    if (name is! String || name.trim().isEmpty || avg is! num) return null;
    return CpuPlayer(name.trim(), avg.toDouble().clamp(minAverage, maxAverage));
  }

  CpuPlayer copyWith({String? name, double? average}) => CpuPlayer(name ?? this.name, average ?? this.average);

  @override
  bool operator ==(Object other) => other is CpuPlayer && other.name == name && other.average == average;

  @override
  int get hashCode => Object.hash(name, average);
}

/// Standardliste bekannter PDC-Spieler. Die Averages sind grobe Richtwerte
/// für die Spielstärke der Bots, keine offiziellen oder aktuellen Statistiken.
/// In der App lässt sich die Liste frei bearbeiten.
const List<CpuPlayer> defaultCpuPlayers = [
  CpuPlayer('Luke Littler', 101),
  CpuPlayer('Luke Humphries', 99),
  CpuPlayer('Michael van Gerwen', 97),
  CpuPlayer('Gian van Veen', 97),
  CpuPlayer('Gerwyn Price', 96),
  CpuPlayer('Stephen Bunting', 96),
  CpuPlayer('Josh Rock', 96),
  CpuPlayer('Jonny Clayton', 95),
  CpuPlayer('Rob Cross', 95),
  CpuPlayer('Chris Dobey', 95),
  CpuPlayer('Gary Anderson', 95),
  CpuPlayer('Wessel Nijman', 95),
  CpuPlayer('Danny Noppert', 94),
  CpuPlayer('Damon Heta', 94),
  CpuPlayer('Nathan Aspinall', 94),
  CpuPlayer('Dave Chisnall', 94),
  CpuPlayer('Ross Smith', 94),
  CpuPlayer('Ryan Searle', 94),
  CpuPlayer('Martin Schindler', 94),
  CpuPlayer('Peter Wright', 93),
  CpuPlayer('Michael Smith', 93),
  CpuPlayer('Dimitri Van den Bergh', 93),
  CpuPlayer('Joe Cullen', 93),
  CpuPlayer('Mike De Decker', 93),
  CpuPlayer('James Wade', 92),
  CpuPlayer('Jermaine Wattimena', 92),
  CpuPlayer('Ricardo Pietreczko', 92),
  CpuPlayer('Krzysztof Ratajski', 92),
  CpuPlayer('Dirk van Duijvenbode', 92),
  CpuPlayer('Daryl Gurney', 91),
  CpuPlayer('Kevin Doets', 91),
  CpuPlayer('Raymond van Barneveld', 91),
];
