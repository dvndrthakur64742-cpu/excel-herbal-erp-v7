/// A draft-only comparison of saved and proposed assignments.
/// It does not calculate effective permissions or grant server authority.
class AccessChangeReview<T extends Comparable<T>> {
  AccessChangeReview(Set<T> before, Set<T> after)
      : added = List<T>.unmodifiable(after.difference(before).toList()..sort()),
        removed = List<T>.unmodifiable(before.difference(after).toList()..sort());

  final List<T> added;
  final List<T> removed;

  bool get changed => added.isNotEmpty || removed.isNotEmpty;
}
