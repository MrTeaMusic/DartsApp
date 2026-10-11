import 'package:dartlab/features/caller/domain/caller_phrases.dart';
import 'package:dartlab/features/caller/domain/voice_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VoiceInfo v(String name, String locale, {String? quality, String? id}) =>
      VoiceInfo(name: name, locale: locale, quality: quality, identifier: id);

  test('Apple: beste Qualität vor Region, britisch bei Gleichstand', () {
    final voices = [
      v('Daniel', 'en-GB', quality: 'default', id: 'com.apple.voice.compact.en-GB.Daniel'),
      v('Zoe', 'en-US', quality: 'premium', id: 'com.apple.voice.premium.en-US.Zoe'),
      v('Serena', 'en-GB', quality: 'premium', id: 'com.apple.voice.premium.en-GB.Serena'),
      v('Anna', 'de-DE', quality: 'enhanced'),
    ];
    expect(pickVoice(voices, CallerLanguage.english)?.name, 'Serena');
    expect(pickVoice(voices, CallerLanguage.german)?.name, 'Anna');
  });

  test('Spaßstimmen nur als letzte Wahl', () {
    final voices = [
      v('Zarvox', 'en-US', quality: 'default', id: 'com.apple.speech.synthesis.voice.Zarvox'),
      v('Grandpa', 'en-GB', quality: 'default', id: 'com.apple.eloquence.en-GB.Grandpa'),
      v('Samantha', 'en-US', quality: 'default', id: 'com.apple.voice.compact.en-US.Samantha'),
    ];
    expect(pickVoice(voices, CallerLanguage.english)?.name, 'Samantha');
  });

  test('Windows: Natural-Stimmen bevorzugt, Locale mit Unterstrich', () {
    final voices = [
      v('Microsoft Hazel', 'en_GB'),
      v('Microsoft Sonia (Natural)', 'en-GB'),
      v('Microsoft Hedda', 'de-DE'),
      v('Microsoft Katja (Natural)', 'de-DE'),
    ];
    expect(pickVoice(voices, CallerLanguage.english)?.name, 'Microsoft Sonia (Natural)');
    expect(pickVoice(voices, CallerLanguage.german)?.name, 'Microsoft Katja (Natural)');
  });

  test('Keine passende Stimme: null', () {
    expect(pickVoice([v('Amélie', 'fr-CA')], CallerLanguage.german), isNull);
    expect(pickVoice(const [], CallerLanguage.english), isNull);
  });

  test('Plattform-Einträge lesen und zurückgeben', () {
    final info = VoiceInfo.fromPlatform({'name': 'Daniel', 'locale': 'en-GB', 'quality': 'enhanced', 'identifier': 'x'});
    expect(info?.quality, 'enhanced');
    expect(info?.toPlatform(), {'name': 'Daniel', 'locale': 'en-GB', 'identifier': 'x'});
    expect(VoiceInfo.fromPlatform({'name': 'Hazel', 'locale': 'en-GB'})?.toPlatform(), {'name': 'Hazel', 'locale': 'en-GB'});
    expect(VoiceInfo.fromPlatform('kaputt'), isNull);
    expect(VoiceInfo.fromPlatform({'name': 1}), isNull);
  });
}
