import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';

class _Session extends SecureSession {
  _Session():super(const FlutterSecureStorage());
  String? boundary='employee-a',access='access-a',refresh='refresh-a';
  int saves=0,clears=0;
  @override Future<String?> loginBoundary() async=>boundary;
  @override Future<String?> accessToken() async=>access;
  @override Future<String?> refreshToken() async=>refresh;
  @override Future<String?> sessionGeneration() async=>'generation-a';
  @override Future<String> deviceId() async=>'synthetic-device-id-123456789';
  @override Future<void> save({required String accessToken,required String refreshToken}) async {
    saves++;access=accessToken;refresh=refreshToken;
  }
  @override Future<void> clear() async {clears++;boundary=null;access=null;refresh=null;}
  void peerLogin(){boundary='employee-b';access='access-b';refresh='refresh-b';}
}
void main(){
  test('an active tab does not issue new reads using another login identity',() async{
    final session=_Session();final api=ApiClient(session);addTearDown(()=>api.dio.close(force:true));
    var sends=0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){sends++;h.resolve(Response(requestOptions:o,data:{'ok':true,'data':[]}));}));
    await api.get('/synthetic');
    session.peerLogin();
    await expectLater(api.get('/synthetic'),throwsA(isA<ApiException>().having((e)=>e.code,'code','session_changed')));
    expect(sends,1);
    await api.logout();
    expect(session.access,'access-b');expect(session.clears,0);
  });
  test('late refresh response cannot restore tokens after logout',() async{
    final session=_Session();final api=ApiClient(session);addTearDown(()=>api.dio.close(force:true));
    final refreshStarted=Completer<void>();final release=Completer<void>();
    var requests=0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async{
      if(o.path==ApiPaths.refresh){
        refreshStarted.complete();await release.future;
        h.resolve(Response(requestOptions:o,data:{'ok':true,'data':{'access_token':'late-access','refresh_token':'late-refresh'}}));
      }else if(o.path==ApiPaths.logout){
        h.resolve(Response(requestOptions:o,data:{'ok':true,'data':{}}));
      }else{
        requests++;
        h.reject(DioException(requestOptions:o,response:Response(requestOptions:o,statusCode:401),type:DioExceptionType.badResponse));
      }
    }));
    final pending=expectLater(api.get('/synthetic'),throwsA(isA<ApiException>().having((e)=>e.code,'code','session_changed')));
    await refreshStarted.future;
    final logout=api.logout();
    release.complete();await logout;await pending;
    expect(session.saves,0);expect(session.access,isNull);expect(requests,1);
  });
}
