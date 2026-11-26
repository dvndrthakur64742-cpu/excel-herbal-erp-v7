import 'package:flutter/material.dart';
import '../core/entry_form_scope.dart';

class SearchChoice {
  const SearchChoice(this.id, this.title, this.subtitle, {this.search = const []});
  final int id;
  final String title;
  final String subtitle;
  final List<Object?> search;
}

/// Shared, scrollable selection. The result is a stable identifier, not a
/// filtered-list position. No transaction is created here.
class SearchChoiceDialog extends StatefulWidget {
  const SearchChoiceDialog({super.key, required this.title, required this.choices});
  final String title;
  final List<SearchChoice> choices;

  @override
  State<SearchChoiceDialog> createState() => _SearchChoiceDialogState();
}

class _SearchChoiceDialogState extends State<SearchChoiceDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.choices.where((c) => EntryFormScope.matchesProduct(
      query, [c.title, c.subtitle, ...c.search],
    )).toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search', prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No matching records.'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final c = results[i];
                      return ListTile(
                        title: Text(c.title),
                        subtitle: c.subtitle.isEmpty ? null : Text(c.subtitle),
                        onTap: () => Navigator.pop(context, c.id),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
