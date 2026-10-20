import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/api_paths.dart';

/// Human report attestation, not proof of bank deposit, physical stock or payroll.
class ReportSubmissionsPanel extends StatefulWidget {
  const ReportSubmissionsPanel({super.key, required this.api, required this.branchId,
    required this.businessDate, required this.canSubmit, required this.canReview,
    required this.canViewSalary});
  final ApiClient api;
  final int branchId;
  final String businessDate;
  final bool canSubmit, canReview, canViewSalary;
  @override
  State<ReportSubmissionsPanel> createState() => _ReportSubmissionsPanelState();
}

class _ReportSubmissionsPanelState extends State<ReportSubmissionsPanel> {
  late Future<dynamic> _loading;
  final _summary=TextEditingController();
  bool busy=false;
  String type='weekly_report';
  DateTime? picked;
  static const types=<String,String>{
    'weekly_report':'Monday Weekly Branch Report',
    'product_order_mon':'Monday Product Order',
    'product_order_tue':'Tuesday Product Order',
    'monthly_report':'1st Monthly Report',
    'salary_receipts':'Salary Receipts (due 10th)',
  };
  @override
  void initState(){super.initState();_loading=_fetch();}
  @override
  void dispose(){_summary.dispose();super.dispose();}
  @override
  void didUpdateWidget(covariant ReportSubmissionsPanel old){
    super.didUpdateWidget(old);
    if(old.branchId!=widget.branchId||old.canReview!=widget.canReview||
       old.canSubmit!=widget.canSubmit){_reload();}
  }
  Future<dynamic> _fetch()=>widget.api.get(ApiPaths.reportSubmissions,
    query:{'branch_id':widget.branchId,'status':'all','limit':100});
  void _reload(){if(mounted)setState(()=>_loading=_fetch());}
  String _date(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+
    d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
  String get period {
    final base=picked??DateTime.tryParse(widget.businessDate)??DateTime.now();
    DateTime d=base;
    if(type=='weekly_report'||type=='product_order_mon'){
      d=base.subtract(Duration(days:base.weekday-DateTime.monday));
    }else if(type=='product_order_tue'){
      d=base.subtract(Duration(days:(base.weekday-DateTime.tuesday+7)%7));
    }else if(type=='monthly_report'){d=DateTime(base.year,base.month,1);}
    else if(type=='salary_receipts'){
      final due=DateTime(base.year,base.month,10);
      d=due.isAfter(base)?DateTime(base.year,base.month-1,10):due;
    }
    return _date(d);
  }
  Future<void> _act(Future<dynamic> Function() fn) async {
    if(busy)return;
    setState(()=>busy=true);
    try{
      await fn();
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Report workflow saved successfully.')));
        _reload();
      }
    }catch(err){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Report action failed: '+err.toString())));
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _send() async {
    final note=_summary.text.trim();
    if(note.length<15){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Summary must contain at least 15 characters.')));
      return;
    }
    await _act(()=>widget.api.post(ApiPaths.reportSubmissions,data:{
      'branch_id':widget.branchId,'report_type':type,
      'period_date':period,'summary_text':note}));
  }
  Future<void> _decision(int id,String decision) async {
    final ctl=TextEditingController();
    try{
      final note=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        title:Text(decision=='approve'?'Approve report attestation?':'Reject report with reason'),
        content:TextField(controller:ctl,maxLength:500,maxLines:3,
          decoration:const InputDecoration(labelText:'Reviewer note')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,ctl.text.trim()),
            child:const Text('Confirm')),
        ],
      ));
      if(note==null||!mounted)return;
      if(decision=='reject'&&note.length<12){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Rejection reason requires 12 characters.')));
        return;
      }
      await _act(()=>widget.api.post(
        ApiPaths.reportSubmissions+'/'+id.toString()+'/decision',
        data:{'decision':decision,'note':note}));
    }finally{ctl.dispose();}
  }
  Future<void> _history(int id) async {
    try{
      final result=await widget.api.get(
        ApiPaths.reportSubmissions+'/'+id.toString()+'/history');
      if(!mounted||result is! Map)return;
      final entries=((result['history'] as List?)??const []).whereType<Map>().toList();
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Immutable Submission History'),
        content:SizedBox(width:520,height:350,child:ListView(children:[
          for(final event in entries)ListTile(
            title:Text('Revision '+event['revision'].toString()+' · '+
              event['event_type'].toString()),
            subtitle:Text('By employee '+event['actor_employee_id'].toString()+
              ' · '+event['created_at'].toString()+'\n'+
              event['content_snapshot'].toString()+'\n'+
              (event['note']??'').toString())),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),
          child:const Text('Close'))],
      ));
    }catch(err){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('History unavailable: '+err.toString())));
    }
  }
  @override
  Widget build(BuildContext context){
    final available=Map<String,String>.from(types);
    if(!widget.canViewSalary)available.remove('salary_receipts');
    if(!available.containsKey(type))type=available.keys.first;
    return Column(children:[
      const Card(child:Padding(padding:EdgeInsets.all(12),
        child:Text('Submitted/approved means a manager attested and reviewer accepted a report. '
          'NOT independent Cash/UPI bank settlement, inventory, payroll payout '
          'or salary receipt verification. Automatic WhatsApp/push/email is disabled.'))),
      if(widget.canSubmit)Card(child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Submit branch report #'+widget.branchId.toString(),
            style:Theme.of(context).textTheme.titleMedium),
          DropdownButtonFormField<String>(initialValue:type,
            items:[for(final e in available.entries)
              DropdownMenuItem(value:e.key,child:Text(e.value))],
            onChanged:busy?null:(value){
              if(value!=null)setState(()=>type=value);
            }),
          OutlinedButton.icon(
            icon:const Icon(Icons.event_outlined),
            label:Text('Scheduled period: '+period),
            onPressed:busy?null:()async{
              final today=DateTime.tryParse(widget.businessDate)??DateTime.now();
              final d=await showDatePicker(context:context,initialDate:picked??today,
                firstDate:DateTime(2000),lastDate:today);
              if(d!=null&&mounted)setState(()=>picked=d);
            }),
          TextField(controller:_summary,minLines:2,maxLines:4,maxLength:1900,
            decoration:const InputDecoration(labelText:'Report summary (15–1900 characters)')),
          FilledButton.icon(onPressed:busy?null:_send,
            icon:const Icon(Icons.send_outlined),
            label:const Text('Submit for regional review')),
        ]))),
      Expanded(child:FutureBuilder<dynamic>(future:_loading,builder:(ctx,snapshot){
        if(snapshot.connectionState!=ConnectionState.done){
          return const Center(child:CircularProgressIndicator());
        }
        if(snapshot.hasError)return Center(child:Column(
          mainAxisSize:MainAxisSize.min,children:[
            Text('Unable to load submissions: '+snapshot.error.toString()),
            TextButton(onPressed:_reload,child:const Text('Retry')),
          ]));
        final result=snapshot.data;
        if(result is! Map||result['read_only']!=true||
            result['scope']!='authorized_branch_report_submissions'||
            int.tryParse(result['branch_id'].toString())!=widget.branchId||
            result['evidence']!='user_attestation_only_not_bank_payroll_or_stock_verification'){
          return const Center(child:Text('Submission authority/evidence contract mismatch.'));
        }
        final records=((result['records'] as List?)??const []).whereType<Map>().toList();
        return RefreshIndicator(onRefresh:()async{_reload();await _loading;},
          child:ListView(children:[
            if(records.isEmpty)const ListTile(title:Text('No submitted reports in this branch.')),
            for(final row in records)Card(child:ListTile(
              title:Text((types[row['report_type']]??row['report_type']).toString()+
                ' · '+row['period_date'].toString()),
              subtitle:Text(row['status'].toString()+' · revision '+
                row['revision'].toString()+'\n'+row['summary_text'].toString()),
              isThreeLine:true,
              trailing:Wrap(mainAxisSize:MainAxisSize.min,children:[
                IconButton(icon:const Icon(Icons.history_outlined),
                  tooltip:'View submission history',
                  onPressed:()=>_history(int.parse(row['id'].toString()))),
                if(widget.canReview&&row['status']=='submitted')...[
                  IconButton(icon:const Icon(Icons.check_circle_outline),
                    tooltip:'Approve attestation',onPressed:busy?null:
                      ()=>_decision(int.parse(row['id'].toString()),'approve')),
                  IconButton(icon:const Icon(Icons.cancel_outlined),
                    tooltip:'Reject with reason',onPressed:busy?null:
                      ()=>_decision(int.parse(row['id'].toString()),'reject')),
                ],
              ]),
            )),
          ]));
      })),
    ]);
  }
}
