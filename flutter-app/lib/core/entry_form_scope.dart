/// An open transaction form belongs to the captured authority and API session.
class EntryFormScope {
  const EntryFormScope(this.state, this.client);
  final Object state;
  final Object client;
  bool matches(Object currentState, Object currentClient) =>
      identical(state, currentState) && identical(client, currentClient);

  static bool matchesProduct(String query, Iterable<Object?> fields) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty || fields.any((value) =>
        value != null && value.toString().toLowerCase().contains(needle));
  }
}
