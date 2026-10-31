class BootstrapProjection {
  const BootstrapProjection({
    required this.raw,
    required this.identity,
    required this.company,
    required this.branches,
  });

  factory BootstrapProjection.fromMap(Map<String, dynamic>? source) {
    final raw = Map<String, dynamic>.from(source ?? const {});
    return BootstrapProjection(
      raw: raw,
      identity: BootstrapIdentity.fromValue(raw['me']),
      company: BootstrapCompany.fromValue(raw['company']),
      branches: ((raw['branches'] as List?) ?? const [])
          .map(BootstrapBranch.tryParse)
          .whereType<BootstrapBranch>()
          .toList(growable: false),
    );
  }

  final Map<String, dynamic> raw;
  final BootstrapIdentity identity;
  final BootstrapCompany company;
  final List<BootstrapBranch> branches;
}

class BootstrapIdentity {
  const BootstrapIdentity({
    required this.raw,
    required this.employee,
    required this.branchIds,
    required this.assignedBranchId,
    required this.capabilities,
    required this.branchSelectorVisible,
  });

  factory BootstrapIdentity.fromValue(Object? value) {
    final raw = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    final branchIds = ((raw['branch_ids'] as List?) ?? const [])
        .map((value) => int.tryParse('$value'))
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    return BootstrapIdentity(
      raw: raw,
      employee: BootstrapEmployee.fromValue(raw['employee']),
      branchIds: branchIds,
      assignedBranchId: int.tryParse('${raw['assigned_branch_id'] ?? ''}'),
      capabilities: ((raw['capabilities'] as List?) ?? const [])
          .map((value) => '$value')
          .where((value) => value.trim().isNotEmpty)
          .toSet()
          .toList(growable: false),
      branchSelectorVisible: raw['branch_selector_visible'] == true,
    );
  }

  final Map<String, dynamic> raw;
  final BootstrapEmployee employee;
  final List<int> branchIds;
  final int? assignedBranchId;
  final List<String> capabilities;
  final bool branchSelectorVisible;
}

class BootstrapEmployee {
  const BootstrapEmployee({
    required this.raw,
    required this.fullName,
    required this.designationCode,
    required this.designationName,
    required this.reportingCategory,
  });

  factory BootstrapEmployee.fromValue(Object? value) {
    final raw = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    return BootstrapEmployee(
      raw: raw,
      fullName: '${raw['full_name'] ?? ''}'.trim(),
      designationCode: '${raw['designation_code'] ?? ''}'.trim(),
      designationName: '${raw['designation_name'] ?? ''}'.trim(),
      reportingCategory: '${raw['reporting_category'] ?? ''}'.trim(),
    );
  }

  final Map<String, dynamic> raw;
  final String fullName;
  final String designationCode;
  final String designationName;
  final String reportingCategory;
}

class BootstrapCompany {
  const BootstrapCompany({required this.raw, required this.name});

  factory BootstrapCompany.fromValue(Object? value) {
    final raw = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    final name = '${raw['name'] ?? ''}'.trim();
    return BootstrapCompany(
      raw: raw,
      name: name.isEmpty ? 'ERP Company' : name,
    );
  }

  final Map<String, dynamic> raw;
  final String name;
}

class BootstrapBranch {
  const BootstrapBranch({
    required this.raw,
    required this.id,
    required this.code,
    required this.name,
    required this.isHeadOffice,
  });

  static BootstrapBranch? tryParse(Object? value) {
    if (value is! Map) return null;
    final raw = Map<String, dynamic>.from(value);
    final id = int.tryParse('${raw['id'] ?? ''}');
    if (id == null) return null;
    return BootstrapBranch(
      raw: raw,
      id: id,
      code: '${raw['code'] ?? ''}'.trim(),
      name: '${raw['name'] ?? ''}'.trim(),
      isHeadOffice: raw['is_head_office'] == true ||
          '${raw['is_head_office']}' == '1',
    );
  }

  final Map<String, dynamic> raw;
  final int id;
  final String code;
  final String name;
  final bool isHeadOffice;

  String get label {
    final value = name.isNotEmpty ? name : code;
    return value.isEmpty ? 'Authorised Branch' : value;
  }
}
