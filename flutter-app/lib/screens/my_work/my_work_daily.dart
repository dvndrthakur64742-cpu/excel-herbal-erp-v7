part of 'my_work_screen.dart';

extension _MyWorkDaily on _MyWorkScreenState {
  Widget _daily() => _MyWorkDailyOverviewImpl(this)._dailyImpl();

  Future<List<Map<String, dynamic>>> _dailyRows(
    AppState app,
    dynamic api,
  ) =>
      _MyWorkDailyOverviewImpl(this)._dailyRowsImpl(app, api);

  String _dailyEmployeeLabel(Map<String, dynamic> row) =>
      _MyWorkDailyOverviewImpl(this)._dailyEmployeeLabelImpl(row);

  String _statusText(String status) =>
      _MyWorkDailyOverviewImpl(this)._statusTextImpl(status);

  Widget _orderStatusChip(String status) =>
      _MyWorkDailyOverviewImpl(this)._orderStatusChipImpl(status);

  List<PopupMenuEntry<String>> _dailyMenu(
    Map<String, dynamic> row,
    AppState app,
  ) =>
      _MyWorkDailyOverviewImpl(this)._dailyMenuImpl(row, app);

  Future<void> _newDailyOrder() =>
      _MyWorkDailyOrderImpl(this)._newDailyOrderImpl();

  Future<Map<String, dynamic>> _dailyDetail(int id) =>
      _MyWorkDailyOrderImpl(this)._dailyDetailImpl(id);

  Future<void> _dailyAction(int id, String action) =>
      _MyWorkDailyOrderImpl(this)._dailyActionImpl(id, action);

  Future<void> _additionalDaily(int id) =>
      _MyWorkDailyOrderImpl(this)._additionalDailyImpl(id);

  Future<void> _issueDaily(int id) =>
      _MyWorkDailyOrderImpl(this)._issueDailyImpl(id);

  Future<void> _editEvening(int id) =>
      _MyWorkDailyClosingImpl(this)._editEveningImpl(id);

  Future<void> _finalPost(int id) =>
      _MyWorkDailyClosingImpl(this)._finalPostImpl(id);

  Future<void> _showDaily(int id) =>
      _MyWorkDailyDetailImpl(this)._showDailyImpl(id);

  Widget _dailyInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) =>
      _MyWorkDailyDetailImpl(this)._dailyInfoRowImpl(
        context,
        icon,
        label,
        value,
      );

  String _requestTypeText(String type) =>
      _MyWorkDailyDetailImpl(this)._requestTypeTextImpl(type);
}
