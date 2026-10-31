import 'package:excel_herbal_erp/core/api_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HR lifecycle paths match backend v7.3.5 contract', () {
    expect(ApiPaths.hrCandidates, '/organization/candidates');
    expect(ApiPaths.hrSeparations, '/organization/separations');
    expect(ApiPaths.candidateDetail(7), '/organization/candidates/7');
    expect(
      ApiPaths.candidateReview(7),
      '/organization/candidates/7/review',
    );
    expect(
      ApiPaths.candidateJoining(7),
      '/organization/candidates/7/joining',
    );
    expect(
      ApiPaths.candidateCredentials(7),
      '/organization/candidates/7/credentials',
    );
    expect(
      ApiPaths.candidateNoShow(7),
      '/organization/candidates/7/no-show',
    );
    expect(
      ApiPaths.candidateDocuments(7),
      '/organization/candidates/7/documents',
    );
    expect(
      ApiPaths.candidateDocumentUpload(7),
      '/organization/candidates/7/documents/upload',
    );
    expect(
      ApiPaths.candidateDocumentDeactivate(7, 9),
      '/organization/candidates/7/documents/9/deactivate',
    );
    expect(
      ApiPaths.employeeSeparation(11),
      '/organization/employees/11/separations',
    );
    expect(
      ApiPaths.separationReview(5),
      '/organization/separations/5/review',
    );
    expect(
      ApiPaths.separationComplete(5),
      '/organization/separations/5/complete',
    );
  });
}
