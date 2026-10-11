import 'caller_phrases.dart';

/// Eine Stimme, wie sie die Plattform meldet.
class VoiceInfo {
  const VoiceInfo({required this.name, required this.locale, this.quality, this.identifier});

  /// Aus einem Eintrag von `FlutterTts.getVoices` (Map mit `name`,
  /// `locale`, auf Apple-Geräten auch `quality` und `identifier`).
  static VoiceInfo? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final locale = raw['locale'];
    if (name is! String || locale is! String) return null;
    final quality = raw['quality'];
    final identifier = raw['identifier'];
    return VoiceInfo(
      name: name,
      locale: locale,
      quality: quality is String ? quality : null,
      identifier: identifier is String ? identifier : null,
    );
  }

  final String name;
  final String locale;
  final String? quality;
  final String? identifier;

  /// Für `FlutterTts.setVoice`.
  Map<String, String> toPlatform() => {
        'name': name,
        'locale': locale,
        if (identifier != null && identifier!.isNotEmpty) 'identifier': identifier!,
      };

  String get _locale => locale.toLowerCase().replaceAll('_', '-');
  String get language => _locale.split('-').first;
  String get region => _locale.contains('-') ? _locale.split('-')[1] : '';

  @override
  String toString() => 'VoiceInfo($name, $locale${quality == null ? '' : ', $quality'})';
}

/// Wählt die beste verfügbare Stimme für [language], `null` ohne passende.
///
/// Zuerst zählt die Qualität (Apple: premium > enhanced > default;
/// Windows: „Natural“/„Neural“-Stimmen vor den übrigen), dann die Region:
/// Englisch bevorzugt britisch wie bei den großen Turnieren, Deutsch
/// bevorzugt Deutschland. Spaßstimmen von macOS (Zarvox, Bubbles, …) und
/// die alten Eloquence-Stimmen kommen nur als letzte Wahl.
VoiceInfo? pickVoice(Iterable<VoiceInfo> voices, CallerLanguage language) {
  VoiceInfo? best;
  var bestScore = -1 << 30;
  for (final v in voices) {
    if (v.language != language.code) continue;
    final score = _qualityScore(v) * 10 + _regionScore(v, language);
    if (score > bestScore || (score == bestScore && best != null && v.name.compareTo(best.name) < 0)) {
      best = v;
      bestScore = score;
    }
  }
  return best;
}

int _qualityScore(VoiceInfo v) {
  final id = (v.identifier ?? '').toLowerCase();
  final name = v.name.toLowerCase();
  if (id.contains('speech.synthesis.voice') || id.contains('eloquence')) return -5;
  switch (v.quality?.toLowerCase()) {
    case 'premium':
      return 3;
    case 'enhanced':
      return 2;
  }
  if (name.contains('natural') || name.contains('neural') || name.contains('premium') || name.contains('enhanced')) {
    return 2;
  }
  return 1;
}

int _regionScore(VoiceInfo v, CallerLanguage language) => switch (language) {
      CallerLanguage.english => switch (v.region) {
          'gb' => 3,
          'ie' || 'au' => 2,
          'us' => 1,
          _ => 0,
        },
      CallerLanguage.german => switch (v.region) {
          'de' => 3,
          'at' || 'ch' => 2,
          _ => 0,
        },
    };
