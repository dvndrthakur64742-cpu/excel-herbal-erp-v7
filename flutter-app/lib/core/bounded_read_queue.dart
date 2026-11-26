/// Limit independent GET sources within one workspace load. Queued work is
/// abandoned when the authority or query changes; already-sent HTTP requests
/// still finish and are discarded by the owning view's scope checks.
abstract final class BoundedReadQueue {
  static Future<void> run(List<Future<void> Function()> jobs, {
    required bool Function() isCurrent,
    int limit=3,
  }) async {
    if(limit<1)throw ArgumentError.value(limit,'limit');
    var next=0;
    Future<void> worker() async {
      while(next<jobs.length && isCurrent()){
        final job=jobs[next++];
        await job();
      }
    }
    await Future.wait([for(var i=0;i<limit && i<jobs.length;i++) worker()]);
  }
}
