abstract final class ApiPaths {
  static const health = '/health',
      appCapabilities = '/app/capabilities',
      login = '/auth/login',
      refresh = '/auth/refresh',
      logout = '/auth/logout',
      authSessions = '/auth/sessions',
      logoutAll = '/auth/logout-all',
      bootstrap = '/bootstrap',
      me = '/me',
      appVersionPolicy = '/app/version-policy';

  static const branches = '/organization/branches',
      employees = '/organization/employees',
      hrEmployeeChoices = '/organization/hr/employee-choices',
      hrCandidates = '/organization/candidates',
      hrSeparations = '/organization/separations',
      masterData = '/organization/master-data',
      designations = '/organization/designations',
      roles = '/organization/roles',
      branchAuthority = '/organization/branch-authority';

  static const attendanceToday = '/workforce/attendance/today',
      checkIn = '/workforce/attendance/check-in',
      checkOut = '/workforce/attendance/check-out',
      attendanceReport = '/workforce/attendance/report',
      gpsPoints = '/workforce/gps/points',
      gpsRoute = '/workforce/gps/route',
      gpsTeam = '/workforce/gps/team',
      holidays = '/workforce/holidays';

  static const fieldVisitCurrent = '/workforce/field-visits/current',
      fieldVisitStart = '/workforce/field-visits/start',
      leave = '/workforce/leave',
      leaveMine = '/workforce/leave/mine',
      leavePending = '/workforce/leave/pending',
      products = '/catalog/products',
      dailyTargetEmployees = '/daily/target-employees',
      dailyCycles = '/daily/cycles';

  static const inventoryStock = '/inventory/stock',
      transfers = '/inventory/transfers',
      adjustments = '/inventory/adjustments',
      quarantine = '/inventory/quarantine';

  static const customers = '/sales/customers',
      availableStock = '/sales/available-stock',
      openSales = '/sales/open-sales',
      counterSale = '/sales/counter',
      customerReceipt = '/sales/receipts';

  static const suppliers = '/purchase/suppliers',
      openBills = '/purchase/open-bills',
      purchaseBills = '/purchase/bills',
      supplierPayments = '/purchase/payments';

  static const financeBootstrap = '/finance/bootstrap',
      financeAccounts = '/finance/accounts',
      expenseHeads = '/finance/expense-heads',
      expenses = '/finance/expenses',
      closingPreflight = '/finance/branch-closing/preflight',
      branchClosing = '/finance/branch-closing',
      reversals = '/finance/reversals',
      periods = '/finance/periods',
      periodClose = '/finance/periods/close',
      bankReconciliations = '/finance/bank-reconciliations';

  static const payrollPolicy = '/payroll/policy',
      payrollRuns = '/payroll/runs',
      salaryStructures = '/payroll/salary-structures',
      performanceSummary = '/performance/summary',
      performanceTargets = '/performance/targets',
      performanceTargetEmployees = '/performance/target-employees',
      performanceRewards = '/performance/rewards',
      performancePromotions = '/performance/promotions';

  static const reportsSales = '/reports/sales',
      reportsPurchase = '/reports/purchase',
      reportsStock = '/reports/stock',
      stockReconciliation = '/reports/stock-reconciliation',
      reportsFinance = '/reports/finance',
      trialBalance = '/reports/trial-balance',
      accountLedger = '/reports/account-ledger',
      profitLoss = '/reports/profit-loss',
      balanceSheet = '/reports/balance-sheet',
      receivables = '/reports/receivables',
      payables = '/reports/payables',
      financeReconciliation = '/reports/finance-reconciliation',
      priceDistribution = '/reports/price-distribution';

  static const communicationSummary = '/communication/summary',
      communicationTargetEmployees = '/communication/target-employees',
      taskManage = '/communication/tasks/manage',
      announcementManage = '/communication/announcements/manage',
      announcements = '/communication/announcements',
      notifications = '/communication/notifications',
      notificationReadAll = '/communication/notifications/read-all',
      pushDevices = '/communication/push-devices',
      pushDeactivate = '/communication/push-devices/deactivate',
      tasks = '/communication/tasks',
      actingDelegations = '/administration/delegations',
      actingInbox = '/administration/acting-inbox',
      actingAuthorityStatus = '/administration/authority-status',
      actingUnavailability = '/administration/unavailability',
      accessMatrix = '/administration/access',
      adminRoles = '/administration/roles',
      audit = '/administration/audit',
      diagnostics = '/administration/diagnostics',
      maintenanceCleanup = '/administration/maintenance/cleanup';

  static String authSessionRevoke(int id) => '/auth/sessions/$id/revoke';
  static String branchUpdate(int id) => '/organization/branches/$id';
  static String branchStatus(int id) => '/organization/branches/$id/status';
  static String employeeUpdate(int id) => '/organization/employees/$id';
  static String employeeCredentials(int id) =>
      '/organization/employees/$id/login-credentials';
  static String employeeLoginStatus(int id) =>
      '/organization/employees/$id/login-status';
  static String employeeRevokeSessions(int id) =>
      '/organization/employees/$id/revoke-sessions';
  static String employeeOffboardingPreflight(int id) =>
      '/organization/employees/$id/offboarding-preflight';
  static String employeeOffboard(int id) =>
      '/organization/employees/$id/offboard';
  static String employeeReactivate(int id) =>
      '/organization/employees/$id/reactivate';
  static String employeeReportingManager(int id) =>
      '/organization/employees/$id/reporting-manager';
  static String employeeDesignations(int id) =>
      '/organization/employees/$id/designations';
  static String employeeDesignationDeactivate(int id, int assignmentId) =>
      '/organization/employees/$id/designations/$assignmentId/deactivate';
  static String employeeHistory(int id) =>
      '/organization/employees/$id/branch-history';
  static String employeeTransfer(int id) =>
      '/organization/employees/$id/transfer-branch';
  static String employeeDocuments(int id) =>
      '/organization/employees/$id/documents';
  static String candidateDetail(int id) => '/organization/candidates/$id';
  static String candidateReview(int id) =>
      '/organization/candidates/$id/review';
  static String candidateJoining(int id) =>
      '/organization/candidates/$id/joining';
  static String candidateCredentials(int id) =>
      '/organization/candidates/$id/credentials';
  static String candidateNoShow(int id) =>
      '/organization/candidates/$id/no-show';
  static String candidateDocuments(int id) =>
      '/organization/candidates/$id/documents';
  static String candidateDocumentUpload(int id) =>
      '/organization/candidates/$id/documents/upload';
  static String candidateDocumentDeactivate(int id, int documentId) =>
      '/organization/candidates/$id/documents/$documentId/deactivate';
  static String employeeSeparation(int id) =>
      '/organization/employees/$id/separations';
  static String separationReview(int id) =>
      '/organization/separations/$id/review';
  static String separationComplete(int id) =>
      '/organization/separations/$id/complete';
  static String employeeDocumentUpload(int id) =>
      '/organization/employees/$id/documents/upload';
  static String employeeDocumentDeactivate(int id, int documentId) =>
      '/organization/employees/$id/documents/$documentId/deactivate';

  static String holidayUpdate(int id) => '/workforce/holidays/$id';
  static String holidayDeactivate(int id) =>
      '/workforce/holidays/$id/deactivate';

  static String productUpdate(int id) => '/catalog/products/$id';
  static String productStatus(int id) => '/catalog/products/$id/status';
  static String productHistory(int id) =>
      '/catalog/products/$id/commercial-history';
  static String productRevision(int id) =>
      '/catalog/products/$id/commercial-revision';
  static String visitComplete(int id) => '/workforce/field-visits/$id/complete';
  static String leaveDecision(int id) => '/workforce/leave/$id/decision';
  static String dailyDetail(int id) => '/daily/cycles/$id';
  static String dailySubmit(int id) => '/daily/cycles/$id/submit';
  static String dailyAdditional(int id) => '/daily/cycles/$id/additional';
  static String dailyApprove(int id) => '/daily/requests/$id/approve';
  static String dailyIssue(int id) => '/daily/requests/$id/issue';
  static String eveningStart(int id) => '/daily/cycles/$id/evening/start';
  static String eveningSave(int id) => '/daily/cycles/$id/evening/save';
  static String eveningSubmit(int id) => '/daily/cycles/$id/evening/submit';
  static String finalPost(int id) => '/daily/cycles/$id/final-post';
  static String transferDetail(int id) => '/inventory/transfers/$id';
  static String transferPack(int id) => '/inventory/transfers/$id/pack';
  static String transferDispatch(int id) => '/inventory/transfers/$id/dispatch';
  static String transferReceive(int id) => '/inventory/transfers/$id/receive';
  static String transferCorrect(int id) =>
      '/inventory/transfers/$id/approve-correction';
  static String transferCancel(int id) => '/inventory/transfers/$id/cancel';
  static String adjustmentDecision(int id) =>
      '/inventory/adjustments/$id/decision';
  static String quarantineResolve(int id) =>
      '/inventory/quarantine/$id/resolve';
  static String customerUpdate(int id) => '/sales/customers/$id';
  static String customerStatus(int id) => '/sales/customers/$id/status';
  static String supplierUpdate(int id) => '/purchase/suppliers/$id';
  static String supplierStatus(int id) => '/purchase/suppliers/$id/status';
  static String expenseDecision(int id) => '/finance/expenses/$id/decision';
  static String closingClose(int id) => '/finance/branch-closing/$id/close';
  static String closingReopen(int id) => '/finance/branch-closing/$id/reopen';
  static String reversalDecision(int id) => '/finance/reversals/$id/decision';
  static String reversalExecute(int id) => '/finance/reversals/$id/execute';
  static String periodReopen(int id) => '/finance/periods/$id/reopen';
  static String bankDetail(int id) => '/finance/bank-reconciliations/$id';
  static String bankImport(int id) =>
      '/finance/bank-reconciliations/$id/import';
  static String bankMatch(int id) => '/finance/bank-lines/$id/match';
  static String bankExclude(int id) => '/finance/bank-lines/$id/exclude';
  static String bankFinalize(int id) =>
      '/finance/bank-reconciliations/$id/finalize';
  static String salaryRevisions(int employeeId) =>
      '/payroll/employees/$employeeId/salary-revisions';
  static String salaryRevisionReview(int id) =>
      '/payroll/salary-revisions/$id/review';
  static String payrollDetail(int id) => '/payroll/runs/$id';
  static String payrollItemUpdate(int id, int itemId) =>
      '/payroll/runs/$id/items/$itemId';
  static String payrollApprove(int id) => '/payroll/runs/$id/approve';
  static String payrollPay(int id) => '/payroll/runs/$id/pay';
  static String payrollDiscard(int id) => '/payroll/runs/$id/discard';
  static String salaryStructureApprove(int id) =>
      '/payroll/salary-structures/$id/approve';
  static String targetApprove(int id) => '/performance/targets/$id/approve';
  static String rewardDecision(int id) => '/performance/rewards/$id/decision';
  static String rewardPay(int id) => '/performance/rewards/$id/pay';
  static String promotionDecision(int id) =>
      '/performance/promotions/$id/decision';

  static String notificationRead(int id) =>
      '/communication/notifications/$id/read';
  static String announcementAcknowledge(int id) =>
      '/communication/announcements/$id/acknowledge';
  static String announcementExpire(int id) =>
      '/communication/announcements/$id/expire';
  static String taskAssign(int id) => '/communication/tasks/$id/assign';
  static String taskReassign(int id) => '/communication/tasks/$id/reassign';
  static String taskComplete(int id) => '/communication/tasks/$id/complete';

  static String delegationRevoke(int id) =>
      '/administration/delegations/$id/revoke';
  static String unavailabilityRevoke(int id) =>
      '/administration/unavailability/$id/revoke';
  static String roleCapabilities(int id) =>
      '/administration/roles/$id/capabilities';
  static String employeeAccess(int id) =>
      '/administration/employees/$id/access';
  static String employeeRoles(int id) => '/administration/employees/$id/roles';
  static String employeeOverrides(int id) =>
      '/administration/employees/$id/overrides';
}