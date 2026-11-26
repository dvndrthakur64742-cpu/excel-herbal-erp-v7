import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/dashboard_data.dart';
void main(){
  Map<String,dynamic> payload(int n)=>{'total':n,'page':1,'page_size':1,'has_more':n>1,'items':n>0?[{'id':1}]:[]};
  test('uses server total not the first page length',(){
    expect(DashboardData.openCount(payload(126)),126);
    expect(DashboardData.openCount(payload(0)),0);
    expect(DashboardData.openCount({...payload(126),'has_more':false}),isNull);
    expect(DashboardData.openCount({...payload(126),'total':null}),isNull);
  });
  test('missing invalid and nonfinite points never become zero',(){
    expect(DashboardData.points([{'points':'2.5'},{'points':3}]),5.5);
    expect(DashboardData.points([{'points':null}]),isNull);
    expect(DashboardData.points([{'points':'NaN'}]),isNull);
  });
}
