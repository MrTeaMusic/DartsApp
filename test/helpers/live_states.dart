import 'package:dartlab/features/second_screen/domain/screen_state.dart';

/// Ein laufendes X01-Match gegen den Bot (wie der zweite Bildschirm es bekommt).
const liveMatch = ScreenState(
  kind: ScreenKind.match,
  title: '501 · X01-Match',
  subtitle: 'First to 3 Legs (Best of 5) · Leg 4',
  status: 'Ben ist dran',
  players: [
    ScreenPlayer(name: 'Ben', score: '81', scoreLabel: 'Rest', active: true, legs: 2, average: '58,4', darts: 39, lastVisit: 100),
    ScreenPlayer(name: 'CPU 60', score: '146', scoreLabel: 'Rest', bot: true, starter: true, legs: 1, average: '61,2', darts: 39, lastVisit: 45),
  ],
  visit: ['T19'],
  visitScore: 57,
  route: ['S4', 'D10'],
  lastVisit: ['S5', 'T20', 'S20'],
  lastVisitScore: 85,
  hits: [ScreenHit('T19', x: -0.17, y: -0.57)],
  hitSerial: 40,
);

/// Dasselbe Match, einen Dart später.
const liveMatchNext = ScreenState(
  kind: ScreenKind.match,
  title: '501 · X01-Match',
  subtitle: 'First to 3 Legs (Best of 5) · Leg 4',
  status: 'Ben ist dran',
  players: [
    ScreenPlayer(name: 'Ben', score: '61', scoreLabel: 'Rest', active: true, legs: 2, average: '58,4', darts: 40, lastVisit: 100),
    ScreenPlayer(name: 'CPU 60', score: '146', scoreLabel: 'Rest', bot: true, starter: true, legs: 1, average: '61,2', darts: 39, lastVisit: 45),
  ],
  visit: ['T19', 'S20'],
  visitScore: 77,
  route: ['D10', 'D20'],
  lastVisit: ['S5', 'T20', 'S20'],
  lastVisitScore: 85,
  hits: [ScreenHit('T19', x: -0.17, y: -0.57), ScreenHit('S20', x: 0.02, y: 0.7)],
  hitSerial: 41,
);

/// X01 solo (Training).
const liveSolo = ScreenState(
  kind: ScreenKind.training,
  title: 'X01-Solo',
  subtitle: 'Ben',
  players: [ScreenPlayer(name: 'Ben', score: '170', scoreLabel: 'Rest', active: true, darts: 18)],
  lastVisit: ['T20', 'T20', 'S11'],
  lastVisitScore: 131,
  route: ['T20', 'T20', 'BULL'],
  stats: [
    ScreenStat('3-Dart-Average', '55,2'),
    ScreenStat('Darts im Leg', '18'),
    ScreenStat('First-9-Average', '61,0'),
    ScreenStat('Höchstes Finish', '–'),
  ],
  hits: [ScreenHit('T20', x: 0.01, y: 0.6), ScreenHit('T20', x: -0.02, y: 0.61), ScreenHit('S11', x: -0.8, y: 0.05)],
  hitSerial: 18,
  banner: 'Bestwert: 131',
  bannerTone: ScreenTone.positive,
  progress: 0,
  progressLabel: 'Leg 1/1',
);

/// Trainingsspiel mit Fortschritt (Around the Clock).
const liveTraining = ScreenState(
  kind: ScreenKind.training,
  title: 'Around the Clock',
  subtitle: 'Ben',
  status: 'Ziel: 7',
  players: [ScreenPlayer(name: 'Ben', score: '7', scoreLabel: 'Ziel', active: true, darts: 21)],
  visit: ['S7', 'MISS'],
  lastVisit: ['S6', 'S6', 'MISS'],
  hits: [ScreenHit('S7', x: 0.4, y: -0.3), ScreenHit('MISS')],
  hitSerial: 21,
  progress: 6 / 21,
  progressLabel: '6/21',
);
