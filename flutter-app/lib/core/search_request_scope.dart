/// A completed search must never survive an authority or API client change.
/// AppState is immutable; replacing even an equivalent bootstrap requires
/// revalidation rather than assuming the old permissions are still current.
class SearchRequestScope<T extends Object> {
  T? _state;
  Object? _client;
  void capture(T state, Object client) {
    _state = state;
    _client = client;
  }
  bool matches(T state, Object client) =>
      identical(_state, state) && identical(_client, client);
  void clear() {
    _state = null;
    _client = null;
  }
}
