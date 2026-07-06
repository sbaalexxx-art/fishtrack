import 'package:fishtrack/services/reputation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = ReputationCalculator();

  test('starts at 50 with no activity', () {
    expect(
      calculator.calculate(
        confirmedCount: 0,
        notAccurateCount: 0,
        abuseFlagsCount: 0,
        suspiciousReportsCount: 0,
        catchesCount: 0,
        reportsCount: 0,
      ),
      50,
    );
  });

  test('applies every reputation weight', () {
    expect(
      calculator.calculate(
        confirmedCount: 4,
        notAccurateCount: 2,
        abuseFlagsCount: 1,
        suspiciousReportsCount: 1,
        catchesCount: 3,
        reportsCount: 5,
      ),
      51,
    );
  });

  test('clamps scores to zero and one hundred', () {
    expect(
      calculator.calculate(
        confirmedCount: 100,
        notAccurateCount: 0,
        abuseFlagsCount: 0,
        suspiciousReportsCount: 0,
        catchesCount: 100,
        reportsCount: 100,
      ),
      100,
    );
    expect(
      calculator.calculate(
        confirmedCount: 0,
        notAccurateCount: 100,
        abuseFlagsCount: 100,
        suspiciousReportsCount: 100,
        catchesCount: 0,
        reportsCount: 0,
      ),
      0,
    );
  });

  test('maps trust thresholds', () {
    expect(TrustLevel.fromScore(39), TrustLevel.newUser);
    expect(TrustLevel.fromScore(40), TrustLevel.trusted);
    expect(TrustLevel.fromScore(65), TrustLevel.reliable);
    expect(TrustLevel.fromScore(85), TrustLevel.expert);
  });
}
