// lib/design/listenable_selector.dart
//
// ListenableSelector<int>(listenable: AttentionService.instance, select: () => svc.count(tab), builder: (c, n) => …)
//   rebuilds only when the selected value changes, not on every notify of the source: a badge whose own count did not
//   move stays as it is while another tab's count ticks (UX v3 phase 5). The leaf form of a provider Selector for a
//   plain Listenable (the attention feed is a singleton, not a provider).
library;

import 'package:flutter/widgets.dart';

class ListenableSelector<T> extends StatefulWidget {
  const ListenableSelector({super.key, required this.listenable, required this.select, required this.builder});

  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    // a new select (another tab / organization) is read on this build
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final v = widget.select();
    if (v != _value) setState(() => _value = v);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
