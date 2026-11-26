import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/bounded_read_queue.dart';
void main(){
  test('at most three reads run together and queued jobs advance',() async {
    final started=<int>[];
    final gates=List.generate(6,(_)=>Completer<void>());
    final done=BoundedReadQueue.run([
      for(var i=0;i<gates.length;i++) () async {started.add(i);await gates[i].future;}
    ],isCurrent:()=>true);
    expect(started,[0,1,2]);
    gates[1].complete();await Future<void>.delayed(Duration.zero);
    expect(started,[0,1,2,3]);
    for(final g in gates)if(!g.isCompleted)g.complete();
    await done;expect(started,[0,1,2,3,4,5]);
  });
  test('scope change prevents queued reads from starting',() async {
    var current=true;
    final started=<int>[];
    final gate=Completer<void>();
    final done=BoundedReadQueue.run([
      for(var i=0;i<7;i++) () async {started.add(i);await gate.future;}
    ],isCurrent:()=>current);
    expect(started,[0,1,2]);
    current=false;gate.complete();await done;
    expect(started,[0,1,2]);
  });
}
