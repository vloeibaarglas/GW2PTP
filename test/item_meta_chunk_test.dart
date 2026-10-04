import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/gw2_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A chunk whose request throws must not poison the other chunks:
/// metadata for the surviving chunks is still cached, so name search
/// keeps working for those items.
void main() {
  test('fetchItemMeta isolates a failing chunk', () async {
    // 201 ids -> two chunks (200 + 1). Fail the chunk containing id 1200.
    final ids = List.generate(201, (i) => 1000 + i);
    final api = HttpGw2Api(
      client: MockClient((request) async {
        final requested = request.url.queryParameters['ids'] ?? '';
        if (requested.split(',').contains('1200')) {
          throw http.ClientException('boom');
        }
        final items = [
          for (final id in requested.split(','))
            {
              'id': int.parse(id),
              'name': 'Item $id',
              'icon': '',
              'flags': <String>[],
            },
        ];
        return http.Response(jsonEncode(items), 200);
      }),
    );

    final result = await api.fetchItemMeta(ids);

    expect(result.length, 200);
    expect(result[1000]?.name, 'Item 1000');
    expect(result[1199]?.name, 'Item 1199');
    expect(result.containsKey(1200), isFalse);
  });
}
