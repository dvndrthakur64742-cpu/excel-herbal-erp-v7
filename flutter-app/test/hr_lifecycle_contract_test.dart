import 'package:excel_herbal_erp/screens/organization/hr_api_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HR lifecycle paths match backend v7.3.5 contract', () {
    expect(HrApiPaths.candidates, '/organization/candidates');
    expect(HrApiPaths.separations, '/organization/separations');
    expect(HrApiPaths.candidate(7), '/organization/candidates/7');
    expect(
      HrApiPaths.candidateReview(7),
      '/organization/candidates/7/review',
    );
    expect(
      HrApiPaths.candidateJoining(7),
      '/organization/candidates/7/joining',
    );
    expect(
      HrApiPaths.candidateCredentials(7),
      '/organization/candidates/7/credentials',
    );
    expect(
      HrApiPaths.candidateNoShow(7),
      '/organization/candidates/7/no-show',
    );
    expect(
      HrApiPaths.candidateDocuments(7),
      '/organization/candidates/7/documents',
    );
    expect(
      HrApiPaths.candidateDocumentUpload(7),
      '/organization/candidates/7/documents/upload',
    );
    expect(
      HrApiPaths.candidateDocumentDeactivate(7, 9),
      '/organization/candidates/7/documents/9/deactivate',
    );
    expect(
      HrApiPaths.employeeSeparation(11),
      '/organization/employees/11/separations',
    );
    expect(
      HrApiPaths.separationReview(5),
      '/organization/separations/5/review',
    );
    expect(
      HrApiPaths.separationComplete(5),
      '/organization/separations/5/complete',
    );
  });
}
