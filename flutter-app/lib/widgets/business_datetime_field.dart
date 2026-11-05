import 'package:flutter/material.dart';

class BusinessDateTimeField extends StatelessWidget {
  const BusinessDateTimeField({
    super.key,
    required this.controller,
    required this.label,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.schedule_outlined),
        suffixIcon: const Icon(Icons.edit_calendar_outlined),
      ),
      onTap: enabled ? () => _pick(context) : null,
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    var initial = DateTime.tryParse(controller.text.trim()) ?? now;
    final min = firstDate ?? DateTime(now.year - 1, 1, 1);
    final max = lastDate ?? DateTime(now.year + 3, 12, 31);
    if (initial.isBefore(min)) initial = min;
    if (initial.isAfter(max)) initial = max;

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(min.year, min.month, min.day),
      lastDate: DateTime(max.year, max.month, max.day),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null) return;

    controller.text = format(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  static String format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}T'
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
