import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/finance_books_totals.dart';
void main(){
  Map<String,dynamic> row(int id,String type,String sub,String d,String c,String b,{int active=1})=>{'id':id,'type':type,'subtype':sub,'debit':d,'credit':c,'balance':b,'active':active};
  test('exact ledger balances include inactive historical accounts and negative balances',(){
    final t=FinanceBooksTotals.read([row(1,'asset','cash','100.01','20','80.01'),row(2,'asset','bank','10','20','-10',active:0),row(3,'asset','upi','20','0','20'),row(4,'income','sales','0','90.01','-90.01')])!;
    expect(t.cash,8001);expect(t.bank,-1000);expect(t.upi,2000);expect(t.difference,0);expect(t.bankCount,1);
  });
  test('missing metadata, duplicate records and bad balances are unavailable',(){
    final r=row(1,'asset','cash','10','0','10');
    expect(FinanceBooksTotals.read([r,r]),isNull);
    expect(FinanceBooksTotals.read([{...r,'balance':'11'}]),isNull);
    expect(FinanceBooksTotals.read([{...r}..remove('subtype')]),isNull);
    expect(FinanceBooksTotals.read([r])!.upiCount,0);
  });
}
