// Damit `node --test cloud/test` (Ordner als Argument) auch mit Node 22 klappt,
// laedt dieser kleine Einstieg die eigentlichen Tests.
import('./worker.test.mjs');
