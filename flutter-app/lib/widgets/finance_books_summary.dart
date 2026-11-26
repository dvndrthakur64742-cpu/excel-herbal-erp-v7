import 'package:flutter/material.dart';
import '../core/finance_books_totals.dart';
import '../core/business_format.dart';
import 'records_list.dart';

class FinanceBooksSummary extends StatelessWidget{
  const FinanceBooksSummary({super.key,required this.rows,required this.scope,required this.asOf});
  final List<Map<String,dynamic>> rows;
  final String scope,asOf;
  String money(int minor)=>BusinessFormat.money(minor/100);
  @override
  Widget build(BuildContext context){
    final t=FinanceBooksTotals.read(rows);
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,4,12,8),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Ledger balances · $scope · as of $asOf'),
          if(t==null)const Text('Summary unavailable: ledger rows require review.')
          else Wrap(spacing:8,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,children:[
            _metric(context,'Cash',t.cash,t.cashCount),
            _metric(context,'Bank',t.bank,t.bankCount),
            _metric(context,'UPI',t.upi,t.upiCount),
            Text(t.difference==0?'Trial balance matched':'Trial balance difference: ${money(t.difference)}',
              style:TextStyle(fontWeight:FontWeight.w600,color:t.difference==0?null:Theme.of(context).colorScheme.error)),
          ]),
          const Text('Book balances only; not physical cash or verified bank balances. Includes historical activity on inactive ledgers.',style:TextStyle(fontSize:12)),
        ])),
      Expanded(child:RecordsList(recordType:'trial_balance',rows:rows)),
    ]);
  }
  Widget _metric(BuildContext context,String label,int value,int count)=>Chip(label:Text('$label: ${count==0?'Not configured':money(value)}'));
}
