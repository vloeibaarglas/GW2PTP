/// Build tag baked into the app at compile time via
/// `--dart-define=BUILD_TAG=<git-sha>`. Shown at the bottom of Settings.
///
/// `rebuild.sh` and the CI release workflow pass the short commit hash
/// (with a `-dirty` suffix when the tree has uncommitted changes);
/// plain IDE builds without the define fall back to 'dev'.
library;

const buildTag = String.fromEnvironment('BUILD_TAG', defaultValue: 'dev');
