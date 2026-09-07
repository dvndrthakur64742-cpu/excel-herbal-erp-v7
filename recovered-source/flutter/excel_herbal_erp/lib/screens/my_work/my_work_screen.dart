import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/api_paths.dart';
import '../../core/providers.dart';
import '../../state/app_state.dart';
import '../../widgets/async_panel.dart';
import '../../widgets/branch_selector.dart';

class MyWorkScreen extends ConsumerStatefulWidget{const MyWorkScreen({super.key});@override ConsumerState<MyWorkScreen> createState()=>_MyWorkScreenState();}
class _MyWorkScreenState extends ConsumerState<MyWorkScreen>{int refresh=0;String? message;
 @override Widget build(BuildContext context){return DefaultTabController(length:3,child:Column(children:[const Padding(padding:EdgeInsets.fromLTRB(16,12,16,0),child:BranchSelector()),const TabBar(isScrollable:true,tabs:[Tab(text:'Attendance & Duty'),Tab(text:'Daily Order'),Tab(text:'Leave & Visit')]),Expanded(child:TabBarView(children:[_attendance(),_daily(),_leaveVisit()]))]));}
 Widget _attendance(){final api=ref.watch(apiClientProvider);return ListView(padding:const EdgeInsets.all(16),children:[AsyncPanel(key:ValueKey('att-$refresh'),future:api.get(ApiPaths.attendanceToday),emptyMessage:'Aaj attendance pending hai.',builder:(context,data){if(data==null)return const SizedBox.shrink();final r=Map<String,dynamic>.from(data as Map);return Card(child:ListTile(title:Text('${r['status']??'present'}'),subtitle:Text('Check-In: ${r['check_in_at']??'-'}\nCheck-Out: ${r['check_out_at']??'-'}'),isThreeLine:true));}),if(message!=null)...[const SizedBox(height:8),Text(message!)],const SizedBox(height:12),Wrap(spacing:10,runSpacing:10,children:[FilledButton.icon(onPressed:()=>_attendanceAction(true),icon:const Icon(Icons.login),label:const Text('Check-In')),FilledButton.tonalIcon(onPressed:()=>_attendanceAction(false),icon:const Icon(Icons.logout),label:const Text('Check-Out'))])]);}
 Widget _daily(){
  final app=ref.watch(appStateProvider);
  final api=ref.watch(apiClientProvider);
  return Column(children:[
   Padding(
    padding:const EdgeInsets.fromLTRB(16,12,16,0),
    child:Row(children:[
     Expanded(child:Text('Daily Orders',style:Theme.of(context).textTheme.titleLarge)),
     FilledButton.icon(onPressed:app.currentBranchId==null?null:_newDailyOrder,icon:const Icon(Icons.add),label:const Text('New Order')),
    ]),
   ),
   Expanded(
    child:AsyncPanel(
     key:ValueKey('daily-${app.currentBranchId}-$refresh'),
     future:api.get(ApiPaths.dailyCycles,query:{if(app.currentBranchId!=null)'branch_id':app.currentBranchId}),
     emptyMessage:'Daily Order nahi mila.',
     builder:(context,data){
      final rows=(data as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      return ListView.separated(
       padding:const EdgeInsets.all(16),
       itemCount:rows.length,
       separatorBuilder:(_,__)=>const SizedBox(height:8),
       itemBuilder:(_,i){
        final r=rows[i];
        return Card(
         child:ListTile(
          title:Text('${r['business_date']} · ${r['status']}'),
          subtitle:Text('Employee #${r['employee_id']}'),
          trailing:PopupMenuButton<String>(
           onSelected:(v)=>_dailyAction(int.parse('${r['id']}'),v),
           itemBuilder:(_)=>_dailyMenu('${r['status']}'),
          ),
          onTap:()=>_showDaily(int.parse('${r['id']}')),
         ),
        );
       },
      );
     },
    ),
   ),
  ]);
 }
 List<PopupMenuEntry<String>> _dailyMenu(String status){final out=<PopupMenuEntry<String>>[];if(status=='morning_draft')out.add(const PopupMenuItem(value:'submit',child:Text('Submit Order')));if(status=='issued')out.add(const PopupMenuItem(value:'evening',child:Text('Start Evening Closing')));if(status=='evening_draft')out.add(const PopupMenuItem(value:'evening_submit',child:Text('Submit Evening')));return out;}
 Widget _leaveVisit(){final api=ref.watch(apiClientProvider);return ListView(padding:const EdgeInsets.all(16),children:[Text('Leave',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),FilledButton.icon(onPressed:_applyLeave,icon:const Icon(Icons.event_available_outlined),label:const Text('Apply Leave')),const SizedBox(height:12),AsyncPanel(key:ValueKey('leave-$refresh'),reloadToken:refresh,future:api.get(ApiPaths.leaveMine),emptyMessage:'Leave history nahi hai.',builder:(context,data){final rows=(data as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();return Column(children:rows.take(8).map((r)=>Card(child:ListTile(dense:true,title:Text('${r['leave_type']} · ${r['status']}'),subtitle:Text('${r['date_from']} → ${r['date_to']}')))).toList());}),const Divider(height:32),Text('Field Visit',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),AsyncPanel(key:ValueKey('visit-$refresh'),reloadToken:refresh,future:api.get(ApiPaths.fieldVisitCurrent),emptyMessage:'Koi active Field Visit nahi hai.',builder:(context,data){if(data==null)return FilledButton.tonalIcon(onPressed:_startVisit,icon:const Icon(Icons.route_outlined),label:const Text('Start Field Visit'));final r=Map<String,dynamic>.from(data as Map);return Card(child:ListTile(title:Text('Visit #${r['id']} · ${r['status']}'),subtitle:Text('${r['purpose']??''}'),trailing:FilledButton(onPressed:()=>_completeVisit(int.parse('${r['id']}')),child:const Text('Complete'))));}),const SizedBox(height:8),FilledButton.tonalIcon(onPressed:_startVisit,icon:const Icon(Icons.add_road),label:const Text('Start Field Visit')),if(message!=null)...[const SizedBox(height:12),Text(message!)] ]);}
 Future<Position> _position() async{var permission=await Geolocator.checkPermission();if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw Exception('Location permission required.');return Geolocator.getCurrentPosition(desiredAccuracy:LocationAccuracy.high);}
 Future<void> _attendanceAction(bool checkIn) async{final app=ref.read(appStateProvider);if(checkIn&&app.currentBranchId==null){setState(()=>message='Authorised Branch select karein.');return;}try{final p=await _position();await ref.read(apiClientProvider).post(checkIn?ApiPaths.checkIn:ApiPaths.checkOut,data:{if(checkIn)'branch_id':app.currentBranchId,'lat':p.latitude,'lng':p.longitude});if(mounted)setState((){refresh++;message=checkIn?'Check-In successful.':'Check-Out successful.';});}catch(e){if(mounted)setState(()=>message=e.toString());}}
 Future<void> _newDailyOrder() async{final app=ref.read(appStateProvider);final api=ref.read(apiClientProvider);try{final data=Map<String,dynamic>.from(await api.get(ApiPaths.masterData) as Map);final products=(data['products'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();final qty=<int,TextEditingController>{for(final p in products)int.parse('${p['id']}'):TextEditingController()};int employee=int.parse('${(app.me['employee'] as Map)['id']}');if(app.can('daily_order.others')){final emps=(await api.get(ApiPaths.employees,query:{'branch_id':app.currentBranchId}) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();if(emps.isNotEmpty)employee=int.parse('${emps.first['id']}');}
 final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Create Daily Order'),content:SizedBox(width:560,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:products.map((p){final id=int.parse('${p['id']}');return Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:qty[id],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'${p['name']} · Qty')));}).toList()))),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Create'))]));if(ok==true){final lines=<Map<String,dynamic>>[];for(final p in products){final id=int.parse('${p['id']}');final q=double.tryParse(qty[id]!.text)??0;if(q>0)lines.add({'product_id':id,'quantity':q});}if(lines.isEmpty)throw Exception('Kam se kam ek product quantity required hai.');await api.post(ApiPaths.dailyCycles,data:{'branch_id':app.currentBranchId,'employee_id':employee,'business_date':_today(),'lines':lines});if(mounted)setState(()=>refresh++);}for(final c in qty.values)c.dispose();}catch(e){if(mounted)setState(()=>message=e.toString());}}
 Future<void> _dailyAction(int id,String action) async{try{final api=ref.read(apiClientProvider);if(action=='submit')await api.post(ApiPaths.dailySubmit(id),data:const {});if(action=='evening')await api.post(ApiPaths.eveningStart(id),data:const {});if(action=='evening_submit')await api.post(ApiPaths.eveningSubmit(id),data:const {});if(mounted)setState(()=>refresh++);}catch(e){if(mounted)setState(()=>message=e.toString());}}
 Future<void> _showDaily(int id) async{try{final d=Map<String,dynamic>.from(await ref.read(apiClientProvider).get(ApiPaths.dailyDetail(id)) as Map);if(!mounted)return;await showModalBottomSheet<void>(context:context,useSafeArea:true,isScrollControlled:true,builder:(context)=>DraggableScrollableSheet(expand:false,initialChildSize:.7,maxChildSize:.95,builder:(_,controller)=>ListView(controller:controller,padding:const EdgeInsets.all(16),children:[Text('Daily Order #$id',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),Text('${d['cycle']}'),const Divider(),Text('Requests',style:Theme.of(context).textTheme.titleMedium),...(d['requests'] as List).map((e)=>ListTile(title:Text('${(e as Map)['type']} · ${e['status']}'),subtitle:Text('${e['lines']??''}')))])));}catch(e){if(mounted)setState(()=>message=e.toString());}}
 Future<void> _applyLeave() async{final type=TextEditingController(text:'Casual Leave');final from=TextEditingController(text:_today());final to=TextEditingController(text:_today());final reason=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Apply Leave'),content:SizedBox(width:480,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:type,decoration:const InputDecoration(labelText:'Leave Type')),const SizedBox(height:10),TextField(controller:from,decoration:const InputDecoration(labelText:'From YYYY-MM-DD')),const SizedBox(height:10),TextField(controller:to,decoration:const InputDecoration(labelText:'To YYYY-MM-DD')),const SizedBox(height:10),TextField(controller:reason,decoration:const InputDecoration(labelText:'Reason'),minLines:2,maxLines:4)])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Submit'))]));if(ok==true){try{await ref.read(apiClientProvider).post(ApiPaths.leave,data:{'leave_type':type.text.trim(),'date_from':from.text.trim(),'date_to':to.text.trim(),'reason':reason.text.trim()});if(mounted)setState((){refresh++;message='Leave request submitted.';});}catch(e){if(mounted)setState(()=>message=e.toString());}}type.dispose();from.dispose();to.dispose();reason.dispose();}
 Future<void> _completeVisit(int id) async{try{final p=await _position();await ref.read(apiClientProvider).post(ApiPaths.visitComplete(id),data:{'lat':p.latitude,'lng':p.longitude});if(mounted)setState((){refresh++;message='Field Visit completed.';});}catch(e){if(mounted)setState(()=>message=e.toString());}}
 Future<void> _startVisit() async{final app=ref.read(appStateProvider);if(app.currentBranchId==null){setState(()=>message='Branch select karein.');return;}final purpose=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Start Field Visit'),content:TextField(controller:purpose,decoration:const InputDecoration(labelText:'Purpose'),minLines:2,maxLines:4),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,purpose.text.trim().isNotEmpty),child:const Text('Start'))]));if(ok==true){try{final p=await _position();final r=Map<String,dynamic>.from(await ref.read(apiClientProvider).post(ApiPaths.fieldVisitStart,data:{'branch_id':app.currentBranchId,'purpose':purpose.text.trim(),'lat':p.latitude,'lng':p.longitude}) as Map);if(mounted)setState((){refresh++;message='Field Visit #${r['id']} started.';});}catch(e){if(mounted)setState(()=>message=e.toString());}}purpose.dispose();}
 static String _today(){final d=DateTime.now();return'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';}
}
