class BusinessFormat {
  BusinessFormat._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _moneyKeys = {
    'amount',
    'total_amount',
    'gross_amount',
    'paid_amount',
    'outstanding_amount',
    'salary_fund',
    'debit',
    'credit',
    'balance',
    'unit_cost',
    'line_total',
    'mrp',
    'sale_price',
    'purchase_price',
    'variance_amount',
    'cash',
    'upi',
    'bank',
    'closing_amount',
    'attendance_salary',
    'salary_fund_earning',
    'bonus',
    'allowances',
    'deductions',
    'net_salary',
    'net_total',
    'gross_total',
    'book_value',
    'control_value',
    'difference',
    'difference_value',
  };

  static const _quantityKeys = {
    'quantity',
    'qty',
    'issue_qty',
    'return_qty',
    'sold_qty',
    'received_quantity',
    'quantity_delta',
    'opening_qty',
    'closing_qty',
    'opening',
    'closing',
    'points',
    'balance_quantity',
    'ledger_quantity',
    'difference_quantity',
  };

  static const _dateKeys = {
    'business_date',
    'bill_date',
    'sale_date',
    'entry_date',
    'date',
    'from_date',
    'to_date',
    'period_start',
    'period_end',
    'expires_on',
    'due_date',
    'effective_from',
    'effective_to',
  };

  static const _statusLabels = {
    'morning_draft': 'Draft',
    'stock_requested': 'Approval Pending',
    'approved': 'Approved',
    'issued': 'Issued',
    'evening_draft': 'Evening Draft',
    'evening_submitted': 'Final Post Pending',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
    'submitted': 'Submitted',
    'pending': 'Pending',
    'posted': 'Posted',
    'reversed': 'Reversed',
    'rejected': 'Rejected',
    'draft': 'Draft',
    'packed': 'Packed',
    'in_transit': 'In Transit',
    'received': 'Received',
    'difference_reported': 'Difference Reported',
    'open': 'Open',
    'closed': 'Closed',
    'paid': 'Paid',
    'partial': 'Partially Paid',
    'partially_paid': 'Partially Paid',
    'matched': 'Matched',
    'mismatch': 'Mismatch',
  };

  static const _labelOverrides = {
    'reference': 'Reference',
    'entry_no': 'Entry No.',
    'sale_no': 'Sale No.',
    'bill_no': 'Bill No.',
    'business_date': 'Date',
    'bill_date': 'Bill Date',
    'sale_date': 'Sale Date',
    'entry_date': 'Entry Date',
    'total_amount': 'Total Amount',
    'gross_amount': 'Gross Amount',
    'paid_amount': 'Paid',
    'outstanding_amount': 'Outstanding',
    'product_name': 'Product',
    'supplier_name': 'Supplier',
    'customer_name': 'Customer',
    'employee_name': 'Employee',
    'full_name': 'Name',
    'employee_code': 'Employee Code',
    'source_type': 'Source',
    'batch_no': 'Batch',
    'custodian_name': 'Custodian',
    'quantity_delta': 'Adjustment Qty',
    'received_quantity': 'Received Qty',
    'unit_cost': 'Unit Cost',
    'line_total': 'Line Total',
    'status': 'Status',
    'debit': 'Debit',
    'credit': 'Credit',
    'balance': 'Balance',
    'memo': 'Narration',
    'mobile': 'Mobile',
    'gstin': 'GSTIN',
    'sku': 'SKU',
    'uom': 'Unit',
    'due_at': 'Due',
    'target_points': 'Target Points',
    'achieved_points': 'Achieved Points',
    'attendance_salary': 'Attendance Salary',
    'salary_fund_earning': 'Salary Fund',
    'net_salary': 'Net Salary',
    'net_total': 'Net Total',
    'gross_total': 'Gross Total',
    'event_type': 'Event',
    'action': 'Action',
    'entity_type': 'Entity',
    'description': 'Description',
    'check_name': 'Check',
    'book_label': 'Book',
    'book_value': 'Book Value',
    'control_label': 'Control',
    'control_value': 'Control Value',
    'difference': 'Difference',
    'difference_quantity': 'Qty Difference',
    'balance_quantity': 'Balance Qty',
    'ledger_quantity': 'Ledger Qty',
    'age_days': 'Age (Days)',
    'age_bucket': 'Ageing',
    'section': 'Section',
  };

  static bool isTechnicalKey(String key) {
    final k = key.toLowerCase();
    if (k == 'id' || k.endsWith('_id') || k.endsWith('_key')) return true;
    return const {
      'company_id',
      'branch_id',
      'created_by',
      'updated_by',
      'wp_user_id',
      'journal_entry_id',
      'assigned_branch_id',
      'role_id',
      'designation_id',
      'paid_by',
      'packed_by',
      'dispatched_by',
      'received_by',
      'decided_by',
      'resolved_by',
      'cancelled_by',
      'source_id',
      'party_id',
      'batch_tracking',
    }.contains(k);
  }

  static bool isBlank(dynamic value) {
    if (value == null) return true;
    final s = '$value'.trim();
    return s.isEmpty || s == 'null' || s == '0.0000' && false;
  }

  static String label(String key) {
    if (_labelOverrides.containsKey(key)) return _labelOverrides[key]!;
    return key
        .split('_')
        .where((e) => e.isNotEmpty)
        .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');
  }

  static String status(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return '—';
    final lower = raw.toLowerCase();
    return _statusLabels[lower] ?? _titleWords(lower.replaceAll('_', ' '));
  }

  static String value(String key, dynamic value) {
    if (value == null || '$value' == 'null' || '$value'.trim().isEmpty)
      return '—';
    final k = key.toLowerCase();
    if (k == 'status') return status(value);
    if (k.endsWith('_at') || k == 'due_at') return dateTime(value);
    if (_dateKeys.contains(k)) return date(value);
    if (_moneyKeys.contains(k) ||
        k.endsWith('_amount') ||
        k.contains('price') ||
        k.contains('cost')) {
      final n = num.tryParse('$value');
      return n == null ? '$value' : money(n);
    }
    if (_quantityKeys.contains(k) || k.endsWith('_qty')) {
      final n = num.tryParse('$value');
      return n == null ? '$value' : quantity(n);
    }
    if (k == 'source_type' || k == 'type')
      return _titleWords('$value'.replaceAll('_', ' '));
    if (k.contains('name')) return displayName('$value');
    return '$value';
  }

  /// Parses backend numeric values defensively. WordPress/PHP JSON responses can
  /// legitimately encode decimal database columns as either JSON numbers or
  /// numeric strings. UI code must never assume one transport representation.
  static num? number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    final raw = '$value'.trim().replaceAll(',', '');
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    return num.tryParse(raw);
  }

  static String money(dynamic value) {
    final parsed = number(value);
    return parsed == null ? '—' : '₹${_indian(parsed)}';
  }

  static String quantity(dynamic value) {
    final parsed = number(value);
    if (parsed == null) return '—';
    if (parsed == parsed.roundToDouble()) return parsed.toInt().toString();
    return parsed
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String date(dynamic value) {
    final raw = '$value'.trim();
    final d = DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    if (d == null) return raw;
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
  }

  static String dateTime(dynamic value) {
    final raw = '$value'.trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '—';
    var text = raw.replaceFirst(' ', 'T');
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
    final d = DateTime.tryParse(hasZone ? text : '${text}Z');
    if (d == null) return raw;
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day.toString().padLeft(2, '0')} ${_months[local.month - 1]} ${local.year} · $h:$m $ap';
  }

  static String displayName(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.length <= 3 && word == word.toUpperCase()) return word;
          if (RegExp(r'^[A-Z0-9-]+$').hasMatch(word) && word.length > 1)
            return word;
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  static String _titleWords(String input) => input
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
      .join(' ');

  static String _indian(num value) {
    final negative = value < 0;
    final abs = value.abs();
    var raw = abs.toStringAsFixed(abs == abs.roundToDouble() ? 0 : 2);
    var parts = raw.split('.');
    var whole = parts[0];
    if (whole.length > 3) {
      final last3 = whole.substring(whole.length - 3);
      var head = whole.substring(0, whole.length - 3);
      final chunks = <String>[];
      while (head.length > 2) {
        chunks.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
      if (head.isNotEmpty) chunks.insert(0, head);
      whole = '${chunks.join(',')},$last3';
    }
    final decimals = parts.length > 1 ? '.${parts[1]}' : '';
    return '${negative ? '-' : ''}$whole$decimals';
  }
}
