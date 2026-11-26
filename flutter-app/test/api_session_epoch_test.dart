import 'dart:async';
import 'package:dio/dio.dart';
import 'package:excel_herbal_erp/core/api_client.dart';
import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:excel_herbal_erp/core/secure_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SecureSession {
  _Session():super(const FlutterSecureStorage());
  String? access='old-access', refresh='old-refresh';
  int saves=0;
  @override Future<String?> accessToken() async=>access;
  @override Future<String?> refreshToken() async=>refresh;
  @override Future<String?> sessionGeneration() async=>'generation';
  @override Future<String> deviceId() async=>'synthetic-device';
  @override Future<void> save({required String accessToken,required String refreshToken}) async{
    saves++;access=accessToken;refresh=refreshToken;
  }
  @override Future<void> clear() async{access=null;refresh=null;}
}
void main(){
  test('logout invalidates delayed refresh and prevents old request replay',() async {
    final session=_Session(), entered=Completer<void>(), release=Completer<void>();
    final api=ApiClient(session);
    var reads=0, logouts=0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async{
      if(o.path==ApiPaths.refresh){
        entered.complete();await release.future;
        h.resolve(Response(requestOptions:o,statusCode:200,data:{'ok':true,'data':{'access_token':'rotated-access','refresh_token':'rotated-refresh'}}));
      }else if(o.path==ApiPaths.logout){
        logouts++;
        h.resolve(Response(requestOptions:o,statusCode:200,data:{'ok':true,'data':{}}));
      }else{
        reads++;
        h.reject(DioException(requestOptions:o,response:Response(requestOptions:o,statusCode:401),type:DioExceptionType.badResponse));
      }
    }));
    final request=api.get(ApiPaths.bootstrap);
    final failed=expectLater(request,throwsA(isA<ApiException>()));
    await entered.future;
    final logout=api.logout();
    release.complete();
    await logout;await failed;
    expect(session.saves,0);expect(session.access,isNull);
    expect(reads,1);expect(logouts,1);
  });
  test('a delayed read cannot return prior session data after logout',() async{
    final session=_Session(), entered=Completer<void>(), release=Completer<void>();
    final api=ApiClient(session);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async{
      if(o.path!=ApiPaths.logout){entered.complete();await release.future;}
      h.resolve(Response(requestOptions:o,statusCode:200,data:{'ok':true,'data':{}}));
    }));
    final request=api.get(ApiPaths.bootstrap);
    final failed=expectLater(request,throwsA(isA<ApiException>().having((e)=>e.code,'code','session_changed')));
    await entered.future;await api.logout();release.complete();await failed;
    expect(session.access,isNull);
  });
}
