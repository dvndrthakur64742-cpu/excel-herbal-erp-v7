import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/actions_screen.dart';
import '../screens/home/profile_screen.dart';
import '../screens/my_work/my_work_screen.dart';
import '../screens/communication/tasks_screen.dart';
import '../screens/communication/communication_screen.dart';
import '../screens/organization/team_screen.dart';
import '../screens/organization/organization_screen.dart';
import '../screens/sales/sales_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/purchase/purchase_screen.dart';
import '../screens/finance/finance_screen.dart';
import '../screens/performance/performance_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/administration/administration_screen.dart';

class AppShell extends ConsumerStatefulWidget{const AppShell({super.key});@override ConsumerState<AppShell> createState()=>_AppShellState();}
class _AppShellState extends ConsumerState<AppShell>{int index=0;
 @override Widget build(BuildContext context){final app=ref.watch(appStateProvider);final pages=[const HomeScreen(),const MyWorkScreen(),ActionsScreen(openMyWork:()=>setState(()=>index=1),openModule:_openModule),const TasksScreen(),const ProfileScreen()];return Scaffold(appBar:AppBar(title:Text(_title(index))),drawer:Drawer(child:SafeArea(child:ListView(padding:EdgeInsets.zero,children:[Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Excel Herbal ERP',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:4),Text('${(app.me['employee'] as Map?)?['full_name']??''}') ])),const Divider(height:1),...app.sections.map((s)=>ListTile(leading:Icon(_icon('${s['id']}')),title:Text('${s['label']}'),onTap:(){Navigator.pop(context);_openModule('${s['id']}');})),const Divider(),ListTile(leading:const Icon(Icons.logout),title:const Text('Logout'),onTap:(){Navigator.pop(context);ref.read(appStateProvider.notifier).logout();})]))),body:SafeArea(child:pages[index]),bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Home'),NavigationDestination(icon:Icon(Icons.work_outline),selectedIcon:Icon(Icons.work),label:'My Work'),NavigationDestination(icon:Icon(Icons.add_circle_outline),selectedIcon:Icon(Icons.add_circle),label:'Actions'),NavigationDestination(icon:Icon(Icons.task_alt_outlined),selectedIcon:Icon(Icons.task_alt),label:'Tasks'),NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile')]));}
 String _title(int i)=>const ['Home','My Work','Quick Actions','Tasks','Profile'][i];
 IconData _icon(String id)=>switch(id){'home'=>Icons.home_outlined,'my_work'=>Icons.work_outline,'team'=>Icons.groups_outlined,'sales'=>Icons.point_of_sale_outlined,'inventory'=>Icons.inventory_2_outlined,'purchase'=>Icons.local_shipping_outlined,'finance'=>Icons.account_balance_outlined,'payroll_performance'=>Icons.insights_outlined,'reports'=>Icons.analytics_outlined,'organization'=>Icons.apartment_outlined,'communication'=>Icons.notifications_outlined,'administration'=>Icons.admin_panel_settings_outlined,_=>Icons.circle_outlined};
 void _openModule(String id){Widget? screen;switch(id){case'home':setState(()=>index=0);return;case'my_work':setState(()=>index=1);return;case'team':screen=const TeamScreen();break;case'sales':screen=const SalesScreen();break;case'inventory':screen=const InventoryScreen();break;case'purchase':screen=const PurchaseScreen();break;case'finance':screen=const FinanceScreen();break;case'payroll_performance':screen=const PerformanceScreen();break;case'reports':screen=const ReportsScreen();break;case'organization':screen=const OrganizationScreen();break;case'communication':screen=const CommunicationScreen();break;case'administration':screen=const AdministrationScreen();break;}if(screen!=null)Navigator.of(context).push(MaterialPageRoute(builder:(_)=>screen!));}
}
