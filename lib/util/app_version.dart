/// Semantic-version compare for release tags (e.g. 'v0.1.1' vs '0.1.0').
///
/// Release tags carry a leading 'v' and the installed version does not;
/// both are reduced to numeric parts before comparing. Missing parts count
/// as 0 ('1.0' == '1.0.0'), and any pre-release/build suffix is ignored —
/// `releases/latest` never returns a pre-release anyway.
library;

/// Numeric parts of a version string, ignoring a leading 'v' and any
/// pre-release ('-...') or build ('+...') suffix.
List<int> parseVersionParts(String version) {
  var v = version.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  v = v.split('+').first.split('-').first;
  return v
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
}

/// Compares two versions numerically: -1 when [a] < [b], 0 when equal,
/// 1 when [a] > [b].
int compareVersions(String a, String b) {
  final ap = parseVersionParts(a);
  final bp = parseVersionParts(b);
  final n = ap.length > bp.length ? ap.length : bp.length;
  for (var i = 0; i < n; i++) {
    final av = i < ap.length ? ap[i] : 0;
    final bv = i < bp.length ? bp[i] : 0;
    if (av != bv) return av < bv ? -1 : 1;
  }
  return 0;
}

/// True when [latest] is strictly newer than [current].
bool isNewerVersion(String latest, String current) =>
    compareVersions(latest, current) > 0;
