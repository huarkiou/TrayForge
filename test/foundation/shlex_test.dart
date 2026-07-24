import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/foundation/shlex.dart';

void main() {
  group('Shlex.split', () {
    test('splits simple command by spaces', () {
      expect(Shlex.split('echo hello world'), ['echo', 'hello', 'world']);
    });

    test('returns single argument for no spaces', () {
      expect(Shlex.split('hello'), ['hello']);
    });

    test('returns empty list for empty string', () {
      expect(Shlex.split(''), []);
    });

    test('returns empty list for whitespace only', () {
      expect(Shlex.split('   '), []);
    });

    test('handles tab as separator', () {
      expect(Shlex.split('a\tb'), ['a', 'b']);
    });

    test('respects double quotes', () {
      expect(Shlex.split('echo "hello world"'), ['echo', 'hello world']);
    });

    test('handles empty double quotes', () {
      expect(Shlex.split('echo ""'), ['echo', '']);
    });

    test('handles escaped double quotes via ""', () {
      expect(Shlex.split('echo "say ""hi"" now"'), ['echo', 'say "hi" now']);
    });

    test('treats single quotes as literal', () {
      expect(Shlex.split("it's"), ["it's"]);
    });

    test('single quotes inside double quotes are literal', () {
      expect(Shlex.split('echo "it\'s fine"'), ['echo', "it's fine"]);
    });

    test('multiple spaces collapse', () {
      expect(Shlex.split('a    b'), ['a', 'b']);
    });

    test('unclosed quote consumes rest', () {
      expect(Shlex.split('cmd "arg with space'), ['cmd', 'arg with space']);
    });
  });
}
