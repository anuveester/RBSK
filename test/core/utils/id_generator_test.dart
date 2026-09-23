import 'package:flutter_test/flutter_test.dart';
import 'package:referredline/core/utils/id_generator.dart';

/// RFC 4122 version 4: version nibble `4`, variant nibble one of 8/9/a/b.
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('generates well-formed RFC 4122 v4 UUIDs (valid for a Postgres uuid '
      'column, per docs/04 §0)', () {
    for (var i = 0; i < 1000; i++) {
      final id = generateUuidV4();
      expect(id, matches(_uuidV4), reason: id);
    }
  });

  test('does not repeat across many generations', () {
    final ids = {for (var i = 0; i < 10000; i++) generateUuidV4()};
    expect(ids, hasLength(10000));
  });
}
