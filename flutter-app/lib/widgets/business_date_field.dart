import 'package:flutter/material.dart';

class BusinessDateField extends StatelessWidget {
  const BusinessDateField({
    super.key,
    required this.controller,
    required this.label,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    this.allowClear = false,
  });

  final TextEditingController controller;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: allowClear && controller.text.trim().isNotEmpty
            ? IconButton(
                tooltip: 'Clear date',
                onPressed: enabled ? controller.clear : null,
                icon: const Icon(Icons.close_rounded),
              )
            : const Icon(Icons.calendar_month_outlined),
      ),
      onTap: enabled ? () => _pick(context) : null,
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final min = _dateOnly(firstDate ?? DateTime(1900, 1, 1));
    final max = _dateOnly(lastDate ?? DateTime(2100, 12, 31));
    var initial = DateTime.tryParse(controller.text.trim()) ?? now;
    initial = _dateOnly(initial);
    if (initial.isBefore(min)) initial = min;
    if (initial.isAfter(max)) initial = max;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: min,
      lastDate: max,
    );
    if (picked == null) return;
    controller.text = format(picked);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
