import 'package:flutter/material.dart';
import '../core/business_format.dart';
import '../core/purchase_outstanding_totals.dart';
import 'records_list.dart';
class PurchaseOutstandingSummary extends StatelessWidget {
  const PurchaseOutstandingSummary({super.key,required this.rows,required this.scope});
  final List<Map<String,dynamic>> rows;
  final String scope;
  String _money(int minor)=>BusinessFormat.money(minor/100);
  @override
  Widget build(BuildContext context){
    final totals=PurchaseOutstandingTotals.read(rows);
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,0,12,6),child:totals==null
        ?const Text('Outstanding summary unavailable: bill balances require review. Raw records remain visible.')
        :Wrap(spacing:12,runSpacing:6,crossAxisAlignment:WrapCrossAlignment.center,children:[
          Text('Outstanding: ${_money(totals.outstanding)}',style:Theme.of(context).textTheme.titleMedium),
          Text('${totals.billCount} open bills · ${totals.suppliers.length} suppliers'),
          OutlinedButton.icon(onPressed:()=>_details(context,totals),icon:const Icon(Icons.summarize_outlined),label:const Text('Supplier summary')),
        ])),
      Expanded(child:RecordsList(recordType:'purchase',rows:rows)),
    ]);
  }
  void _details(BuildContext context,PurchaseOutstandingTotals totals){
    showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Outstanding supplier summary'),
      content:SizedBox(width:600,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(scope),
        const Text('Posted open bills only. Paid amounts relate only to these bills, not all supplier payments or AP ledger balances.'),
        const SizedBox(height:12),
        Text('Open bill value: ${_money(totals.total)}'),
        Text('Paid on open bills: ${_money(totals.paid)}'),
        Text('Outstanding: ${_money(totals.outstanding)}'),
        const Divider(),
        for(final supplier in totals.suppliers)
          ExpansionTile(title:Text(supplier.name),subtitle:Text('${supplier.bills} open bills · ${_money(supplier.outstanding)} outstanding'),
            children:[for(final row in rows.where((r)=>'${r['supplier_id']}'==supplier.id))
              ListTile(title:Text('${row['bill_no']??row['id']}'),subtitle:Text('${row['bill_date']}'),trailing:Text(_money(PurchaseOutstandingTotals.minor(row['outstanding_amount'])!)))])
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Close'))],
    ));
  }
}
