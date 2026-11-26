/// Trial balance summary in exact minor units. Ledger balances are not
/// physical cash counts or bank statement balances.
class FinanceBooksTotals {
  const FinanceBooksTotals(this.debit,this.credit,this.cash,this.bank,this.upi,this.cashCount,this.bankCount,this.upiCount);
  final int debit,credit,cash,bank,upi,cashCount,bankCount,upiCount;
  int get difference=>debit-credit;
  static int? minor(dynamic value){
    final m=RegExp(r'^(-?)(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch('${value??''}'.trim());
    if(m==null)return null;
    final n=int.parse(m.group(2)!)*100+int.parse((m.group(3)??'').padRight(2,'0'));
    return m.group(1)=='-'?-n:n;
  }
  static FinanceBooksTotals? read(List<Map<String,dynamic>> rows){
    const limit=9007199254740991;
    int debit=0,credit=0,cash=0,bank=0,upi=0,cc=0,bc=0,uc=0;
    final seen=<String>{};
    for(final r in rows){
      final id='${r['id']??''}';
      final d=minor(r['debit']),c=minor(r['credit']),b=minor(r['balance']);
      if((int.tryParse(id)??0)<=0||!seen.add(id)||d==null||c==null||b==null||d<0||c<0||d-c!=b||!r.containsKey('subtype')||!r.containsKey('active'))return null;
      if(debit>limit-d||credit>limit-c)return null;
      debit+=d;credit+=c;
      if(r['type']=='asset'){
        switch('${r['subtype']??''}'.trim().toLowerCase()){
          case 'cash': cash+=b;cc++;break;
          case 'bank': bank+=b;bc++;break;
          case 'upi': upi+=b;uc++;break;
        }
      }
      if(cash.abs()>limit||bank.abs()>limit||upi.abs()>limit)return null;
    }
    return FinanceBooksTotals(debit,credit,cash,bank,upi,cc,bc,uc);
  }
}
