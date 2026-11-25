/// Export only the fields already presented in the price distribution table.
/// Never include hidden identifiers, metadata or other API payload fields.
List<Map<String, dynamic>> priceDistributionExportRows(
  List<Map<String, dynamic>> rows,
) =>
    [
      for (final row in rows)
        {
          'Employee': row['full_name'],
          'Employee Code': row['employee_code'],
          'Reporting': row['reporting_category'],
          'Sale Days': row['sale_days'],
          'Sale Price': row['sale_price'],
          'HO Amount': row['ho_amount'],
          'BM Profit': row['bm_profit'],
          'Salary Fund': row['salary_fund'],
          'Expense': row['expense'],
          'Points': row['points'],
        },
    ];
