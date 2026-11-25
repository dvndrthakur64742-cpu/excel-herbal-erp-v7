import 'package:flutter/material.dart';

/// Keeps an independent Home summary stable across incidental rebuilds.
/// A new authority/branch/date scope or explicit retry starts a new request.
class HomeQuery<T> extends StatefulWidget {
  const HomeQuery({super.key, required this.scope, required this.loader,
    required this.builder});
  final Object scope;
  final Future<T> Function() loader;
  final Widget Function(BuildContext, AsyncSnapshot<T>, VoidCallback) builder;
  @override
  State<HomeQuery<T>> createState() => _HomeQueryState<T>();
}

class _HomeQueryState<T> extends State<HomeQuery<T>> {
  late Future<T> _future;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _future = Future<T>.sync(widget.loader);
  }

  @override
  void didUpdateWidget(covariant HomeQuery<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scope != oldWidget.scope) {
      _generation++;
      _future = Future<T>.sync(widget.loader);
    }
  }

  void _retry() {
    setState(() {
      _generation++;
      _future = Future<T>.sync(widget.loader);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    // Discard the previous scope's snapshot immediately, even while waiting.
    key: ValueKey(_generation),
    future: _future,
    builder: (context, snapshot) => widget.builder(context, snapshot, _retry),
  );
}
