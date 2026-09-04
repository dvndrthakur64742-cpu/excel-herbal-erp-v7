from pathlib import Path

BASE = Path('flutter/excel_herbal_erp/lib/screens')

def replace(path: str, old: str, new: str) -> None:
    p = BASE / path
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'Expected source fragment not found: {path}: {old[:80]}')
    p.write_text(text.replace(old, new, 1))

replace('finance/finance_screen.dart',
        "      final accounts = (d['accounts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => '${e['type']}' == 'asset' && const {'cash', 'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase())).toList();\n      int? head, account;",
        "      final accounts = (d['accounts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => '${e['type']}' == 'asset' && const {'cash', 'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase())).toList();\n      if (!mounted) return;\n      int? head, account;")
replace('finance/finance_screen.dart',
        "      final accounts = (finance['accounts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => '${e['type']}' == 'asset' && const {'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase())).toList();\n      int? accountId;",
        "      final accounts = (finance['accounts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => '${e['type']}' == 'asset' && const {'bank', 'upi'}.contains('${e['subtype']}'.toLowerCase())).toList();\n      if (!mounted) return;\n      int? accountId;")
replace('inventory/inventory_screen.dart', "      if (stock.isEmpty) throw Exception('Selected branch me transfer ke liye stock nahi hai.');\n      int? dest;", "      if (stock.isEmpty) throw Exception('Selected branch me transfer ke liye stock nahi hai.');\n      if (!mounted) return;\n      int? dest;")
replace('inventory/inventory_screen.dart', "      if (stock.isEmpty) throw Exception('Adjustment ke liye stock item available nahi hai.');\n      int? lineId;", "      if (stock.isEmpty) throw Exception('Adjustment ke liye stock item available nahi hai.');\n      if (!mounted) return;\n      int? lineId;")
replace('inventory/inventory_screen.dart', "      final controllers = <int, TextEditingController>{for (final l in lines) int.parse('${l['id']}'): TextEditingController(text: '${l['quantity']}')};\n      final ok = await showDialog<bool>", "      final controllers = <int, TextEditingController>{for (final l in lines) int.parse('${l['id']}'): TextEditingController(text: '${l['quantity']}')};\n      if (!mounted) return;\n      final ok = await showDialog<bool>")
replace('inventory/inventory_screen.dart', "      for (final c in controllers.values) c.dispose();", "      for (final c in controllers.values) {\n        c.dispose();\n      }")
replace('my_work/my_work_screen.dart', "return Geolocator.getCurrentPosition(desiredAccuracy:LocationAccuracy.high);", "return Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high));")
replace('my_work/my_work_screen.dart', "if(emps.isNotEmpty)employee=int.parse('${emps.first['id']}');}\n final ok=await showDialog<bool>", "if(emps.isNotEmpty)employee=int.parse('${emps.first['id']}');}\n if(!mounted)return;\n final ok=await showDialog<bool>")
replace('my_work/my_work_screen.dart', "for(final c in qty.values)c.dispose();", "for(final c in qty.values){c.dispose();}")
replace('organization/organization_screen.dart', "      final employees = (results[2] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();\n      String? designationCode;", "      final employees = (results[2] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();\n      if (!mounted) return;\n      String? designationCode;")
replace('organization/team_screen.dart', "if(remaining>.0001)throw Exception('${l['product_name']} ka authorised branch stock insufficient hai.');}Navigator.pop(context);await api.post", "if(remaining>.0001)throw Exception('${l['product_name']} ka authorised branch stock insufficient hai.');}if(!mounted)return;Navigator.pop(context);await api.post")
replace('performance/performance_screen.dart', "          .map((e) => Map<String, dynamic>.from(e as Map))\n          .toList();\n      int? employeeId;", "          .map((e) => Map<String, dynamic>.from(e as Map))\n          .toList();\n      if (!mounted) return;\n      int? employeeId;")
replace('purchase/purchase_screen.dart', "for(final p in products){final id=int.parse('${p['id']}');qty[id]=TextEditingController();cost[id]=TextEditingController();batchNo[id]=TextEditingController();}final ok=await showDialog<bool>", "for(final p in products){final id=int.parse('${p['id']}');qty[id]=TextEditingController();cost[id]=TextEditingController();batchNo[id]=TextEditingController();}if(!mounted)return;final ok=await showDialog<bool>")
replace('purchase/purchase_screen.dart', "final accounts=(finance['accounts'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).where((e)=>'${e['type']}'=='asset'&&const {'cash','bank','upi'}.contains('${e['subtype']}'.toLowerCase())).toList();int? billId;", "final accounts=(finance['accounts'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).where((e)=>'${e['type']}'=='asset'&&const {'cash','bank','upi'}.contains('${e['subtype']}'.toLowerCase())).toList();if(!mounted)return;int? billId;")
replace('purchase/purchase_screen.dart', "for(final c in [...qty.values,...cost.values,...batchNo.values])c.dispose();", "for(final c in [...qty.values,...cost.values,...batchNo.values]){c.dispose();}")
replace('sales/sales_screen.dart', "      if (stock.isEmpty) throw Exception('Selected branch me sale ke liye available stock nahi hai.');\n\n      int? customerId;", "      if (stock.isEmpty) throw Exception('Selected branch me sale ke liye available stock nahi hai.');\n      if (!mounted) return;\n\n      int? customerId;")
replace('sales/sales_screen.dart', "      for (final c in qty.values) c.dispose();", "      for (final c in qty.values) {\n        c.dispose();\n      }")

print('PASS strict analyzer cleanup applied')
