class SupplierOutstanding {
  const SupplierOutstanding(this.id,this.name,this.bills,this.total,this.paid,this.outstanding);
  final String id,name;
  final int bills,total,paid,outstanding;
}
/// Posted open bill balances, not bank payments or general ledger balances.
class PurchaseOutstandingTotals {
  const PurchaseOutstandingTotals(this.billCount,this.total,this.paid,this.outstanding,this.suppliers);
  final int billCount,total,paid,outstanding;
  final List<SupplierOutstanding> suppliers;
  static int? minor(dynamic value) {
    final m=RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch('${value ?? ''}'.trim());
    if(m==null)return null;
    return int.parse(m.group(1)!)*100+int.parse((m.group(2)??'').padRight(2,'0'));
  }
  static PurchaseOutstandingTotals? read(List<Map<String,dynamic>> rows) {
    const limit=9007199254740991;
    final seen=<String>{};
    final groups=<String,SupplierOutstanding>{};
    int total=0,paid=0,outstanding=0;
    for(final row in rows){
      final id='${row['id']??''}',supplier='${row['supplier_id']??''}',name='${row['supplier_name']??''}'.trim();
      final t=minor(row['total_amount']),p=minor(row['paid_amount']),o=minor(row['outstanding_amount']);
      if((int.tryParse(id)??0)<=0||!seen.add(id)||(int.tryParse(supplier)??0)<=0||name.isEmpty||
        t==null||p==null||o==null||o<=0||t!=p+o||row['status']!='posted')return null;
      final prior=groups[supplier];
      if(prior!=null&&prior.name!=name)return null;
      if(total>limit-t||paid>limit-p||outstanding>limit-o)return null;
      total+=t;paid+=p;outstanding+=o;
      groups[supplier]=SupplierOutstanding(supplier,name,(prior?.bills??0)+1,(prior?.total??0)+t,(prior?.paid??0)+p,(prior?.outstanding??0)+o);
    }
    final suppliers=groups.values.toList()..sort((a,b){final order=b.outstanding.compareTo(a.outstanding);return order!=0?order:a.id.compareTo(b.id);});
    return PurchaseOutstandingTotals(rows.length,total,paid,outstanding,List.unmodifiable(suppliers));
  }
}
