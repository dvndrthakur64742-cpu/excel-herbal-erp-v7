abstract final class HrApiPaths {
  static const candidates = '/organization/candidates';
  static const separations = '/organization/separations';

  static String candidate(int id) => '/organization/candidates/$id';
  static String candidateReview(int id) => '/organization/candidates/$id/review';
  static String candidateJoining(int id) => '/organization/candidates/$id/joining';
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

  static String employeeSeparation(int employeeId) =>
      '/organization/employees/$employeeId/separations';
  static String separationReview(int id) =>
      '/organization/separations/$id/review';
  static String separationComplete(int id) =>
      '/organization/separations/$id/complete';
}
