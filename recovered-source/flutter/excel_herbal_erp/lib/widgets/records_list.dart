import 'package:flutter/material.dart';

class RecordsList extends StatelessWidget{
 const RecordsList({super.key,required this.rows,this.titleKeys=const ['name','full_name','product_name','supplier_name','reference','entry_no','sale_no','bill_no','title','status'],this.onTap});
 final List<Map<String,dynamic>> rows;final List<String> titleKeys;final void Function(Map<String,dynamic>)? onTap;
 @override Widget build(BuildContext context)=>ListView.separated(padding:const EdgeInsets.all(16),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final r=rows[i];String title='Record #${r['id']??i+1}';for(final k in titleKeys){final v=r[k];if(v!=null&&'$v'.isNotEmpty){title='$v';break;}}final details=r.entries.where((e)=>e.value!=null&&e.key!='id'&&!titleKeys.contains(e.key)).take(5).map((e)=>'${e.key.replaceAll('_',' ')}: ${e.value}').join(' · ');return Card(child:ListTile(title:Text(title),subtitle:details.isEmpty?null:Text(details,maxLines:3,overflow:TextOverflow.ellipsis),trailing:onTap==null?null:const Icon(Icons.chevron_right),onTap:onTap==null?null:()=>onTap!(r)));});
}
