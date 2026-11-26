import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/purchase_outstanding_totals.dart';
void main(){
  Map<String,dynamic> bill(int id,int supplier,String total,String paid,String outstanding)=>{'id':id,'supplier_id':supplier,'supplier_name':'Supplier $supplier','status':'posted','total_amount':total,'paid_amount':paid,'outstanding_amount':outstanding};
  test('exact paise grouped by supplier',(){
    final r=PurchaseOutstandingTotals.read([bill(1,1,'100.20','40.10','60.10'),bill(2,1,'10.01','0','10.01'),bill(3,2,'80','0','80')])!;
    expect(r.outstanding,15011);expect(r.paid,4010);expect(r.total,19021);expect(r.suppliers.map((s)=>s.id),['2','1']);expect(r.suppliers.last.bills,2);
  });
  test('invalid and duplicate rows fail closed',(){
    final row=bill(1,1,'100','40','60');
    expect(PurchaseOutstandingTotals.read([row,row]),isNull);
    expect(PurchaseOutstandingTotals.read([bill(1,1,'100','40','61')]),isNull);
    expect(PurchaseOutstandingTotals.read([bill(1,1,'100','40','60.001')]),isNull);
    expect(PurchaseOutstandingTotals.read([{...row,'supplier_name':null}]),isNull);
    expect(PurchaseOutstandingTotals.read([{...row,'status':'reversed'}]),isNull);
  });
}
