import 'package:flutter/material.dart';

class AsyncPanel extends StatefulWidget {
  const AsyncPanel({super.key, required this.future, required this.builder, this.emptyMessage='Koi data nahi mila.', this.reloadToken});
  final Future<dynamic> future;
  final Widget Function(BuildContext, dynamic) builder;
  final String emptyMessage;
  final Object? reloadToken;
  @override State<AsyncPanel> createState()=>_AsyncPanelState();
}
class _AsyncPanelState extends State<AsyncPanel>{late Future<dynamic> _future;
 @override void initState(){super.initState();_future=widget.future;}
 @override void didUpdateWidget(covariant AsyncPanel oldWidget){super.didUpdateWidget(oldWidget);if(oldWidget.reloadToken!=widget.reloadToken)_future=widget.future;}
 @override Widget build(BuildContext context)=>FutureBuilder<dynamic>(future:_future,builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:Padding(padding:EdgeInsets.all(32),child:CircularProgressIndicator()));if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_outlined,size:42),const SizedBox(height:10),Text('${s.error}',textAlign:TextAlign.center),const SizedBox(height:10),OutlinedButton.icon(onPressed:()=>setState(()=>_future=widget.future),icon:const Icon(Icons.refresh),label:const Text('Retry'))])));final d=s.data;if(d is List&&d.isEmpty)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(widget.emptyMessage)));return widget.builder(context,d);});}
