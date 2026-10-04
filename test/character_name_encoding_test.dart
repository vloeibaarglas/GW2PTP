import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gw2tp/api/gw2_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Regression tests for character-name URL encoding.
///
/// The old code ran Uri.encodeComponent on the name and then passed the
/// result through Uri.https, which encoded the '%' again:
/// "Elly Sourblossom" -> "Elly%2520Sourblossom" -> API 404 -> _safeGet
/// swallowed it -> the character silently vanished from inventory.
/// Names without spaces were unaffected. The fix: pass the raw name and
/// let Uri.https encode the path exactly once.
void main() {
  group('character name encoding', () {
    // (display name, item count on that character)
    const cases = <String, int>{
      'Elly Sourblossom': 250, // space
      'Fernberry': 36, // no space (control)
      'Zoe Nightshade': 12, // multiple words
    };

    for (final entry in cases.entries) {
      final name = entry.key;
      final count = entry.value;
      test('"$name" is encoded once, not twice', () async {
        final requestedUrls = <String>[];
        final api = HttpGw2Api(
          client: MockClient((request) async {
            requestedUrls.add(request.url.toString());
            final path = request.url.path;
            if (path == '/v2/account/bank' ||
                path == '/v2/account/materials' ||
                path == '/v2/account/inventory') {
              return http.Response('[]', 200);
            }
            if (path == '/v2/characters') {
              return http.Response(jsonEncode([name]), 200);
            }
            final expectedBase = Uri.https(
              'api.guildwars2.com',
              '/v2/characters/$name',
            ).path;
            if (path == '$expectedBase/inventory') {
              return http.Response(
                jsonEncode({
                  'bags': [
                    {
                      'inventory': [
                        {'id': 81127, 'count': count},
                      ],
                    },
                  ],
                }),
                200,
              );
            }
            if (path == '$expectedBase/equipment') {
              return http.Response(jsonEncode({'equipment': []}), 200);
            }
            return http.Response('not found', 404);
          }),
        );

        final entries = await api.fetchInventory('key');

        // The character's items must be present under the raw name...
        final items =
            entries.where((e) => e.itemId == 81127).toList();
        expect(items, hasLength(1));
        expect(items.first.location, name);
        expect(items.first.count, count);
        // ...and no request may double-encode (%25 = an encoded '%').
        expect(requestedUrls.any((u) => u.contains('%25')), isFalse);
      });
    }

    test('non-ASCII names are UTF-8 percent-encoded once', () async {
      const name = 'Zoë Nightshade';
      final requestedUrls = <String>[];
      final api = HttpGw2Api(
        client: MockClient((request) async {
          requestedUrls.add(request.url.toString());
          final path = request.url.path;
          if (path == '/v2/account/bank' ||
              path == '/v2/account/materials' ||
              path == '/v2/account/inventory') {
            return http.Response('[]', 200);
          }
          if (path == '/v2/characters') {
            return http.Response(jsonEncode([name]), 200);
          }
          final expectedBase =
              Uri.https('api.guildwars2.com', '/v2/characters/$name').path;
          if (path == '$expectedBase/inventory') {
            return http.Response(
              jsonEncode({
                'bags': [
                  {
                    'inventory': [
                      {'id': 81127, 'count': 7},
                    ],
                  },
                ],
              }),
              200,
            );
          }
          if (path == '$expectedBase/equipment') {
            return http.Response(jsonEncode({'equipment': []}), 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final entries = await api.fetchInventory('key');
      final items = entries.where((e) => e.itemId == 81127).toList();
      expect(items, hasLength(1));
      expect(items.first.location, name);
      expect(requestedUrls.any((u) => u.contains('%25')), isFalse);
      // ë must be UTF-8 encoded (0xC3 0xAB), exactly once.
      expect(
        requestedUrls.any((u) => u.contains('Zo%C3%AB%20Nightshade')),
        isTrue,
      );
    });
  });
}
