import 'package:dartlab/features/caller/domain/caller_phrases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Englisch', () {
    const en = EnglishCallerPhrases();

    test('Zahlen wie ein britischer Caller', () {
      expect(en.number(0), 'zero');
      expect(en.number(7), 'seven');
      expect(en.number(13), 'thirteen');
      expect(en.number(40), 'forty');
      expect(en.number(41), 'forty-one');
      expect(en.number(100), 'one hundred');
      expect(en.number(101), 'one hundred and one');
      expect(en.number(140), 'one hundred and forty');
      expect(en.number(170), 'one hundred and seventy');
      expect(en.number(180), 'one hundred and eighty');
      expect(en.number(501), 'five hundred and one');
      expect(en.number(1001), '1001');
    });

    test('Aufnahmen: 180 mit Nachdruck, 0 ist „No score“', () {
      expect(en.score(60), const CallerPhrase('Sixty'));
      expect(en.score(140), const CallerPhrase('One hundred and forty'));
      expect(en.score(180), const CallerPhrase('One hundred and eighty!', emphasis: true));
      expect(en.score(0), const CallerPhrase('No score'));
      expect(en.score(26), const CallerPhrase('Twenty-six'));
    });

    test('Bust, Rest, Game shot, Game on', () {
      expect(en.forCall(const BustCall()).text, 'Bust');
      expect(en.forCall(const RequireCall(32)).text, 'You require thirty-two');
      expect(en.forCall(const RequireCall(121)).text, 'You require one hundred and twenty-one');
      expect(en.forCall(const GameShotCall()).text, 'Game shot!');
      expect(en.forCall(const GameShotCall(GameShotKind.leg)).text, 'Game shot, and the leg!');
      expect(
        en.forCall(const GameShotCall(GameShotKind.match)),
        const CallerPhrase('Game shot, and the match!', emphasis: true),
      );
      expect(en.forCall(const GameOnCall()).text, 'Game on!');
    });
  });

  group('Deutsch', () {
    const de = GermanCallerPhrases();

    test('Zahlen ausgeschrieben', () {
      expect(de.number(0), 'null');
      expect(de.number(1), 'eins');
      expect(de.number(16), 'sechzehn');
      expect(de.number(17), 'siebzehn');
      expect(de.number(21), 'einundzwanzig');
      expect(de.number(32), 'zweiunddreißig');
      expect(de.number(60), 'sechzig');
      expect(de.number(100), 'hundert');
      expect(de.number(101), 'hunderteins');
      expect(de.number(121), 'hunderteinundzwanzig');
      expect(de.number(140), 'hundertvierzig');
      expect(de.number(180), 'hundertachtzig');
      expect(de.number(301), 'dreihunderteins');
    });

    test('Aufnahmen, Bust, Rest, Checkout', () {
      expect(de.score(180), const CallerPhrase('Hundertachtzig!', emphasis: true));
      expect(de.score(45), const CallerPhrase('Fünfundvierzig'));
      expect(de.score(0), const CallerPhrase('Keine Punkte'));
      expect(de.bust().text, 'Überworfen');
      expect(de.requires(32).text, 'Du brauchst zweiunddreißig');
      expect(de.gameShot(GameShotKind.plain).text, 'Ausgecheckt!');
      expect(de.gameShot(GameShotKind.leg).text, 'Ausgecheckt, Leg gewonnen!');
      expect(de.gameShot(GameShotKind.match).emphasis, isTrue);
      expect(de.gameOn().text, "Los geht's!");
    });
  });

  test('Sprache wählt den Baukasten', () {
    expect(CallerPhrases.of(CallerLanguage.english), isA<EnglishCallerPhrases>());
    expect(CallerPhrases.of(CallerLanguage.german), isA<GermanCallerPhrases>());
  });
}
