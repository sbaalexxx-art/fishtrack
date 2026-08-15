enum BillingRestoreResult { restored, nothingToRestore, unavailable, error }

abstract interface class BillingRepository {
  Future<BillingRestoreResult> restorePurchases();
}

class UnavailableBillingRepository implements BillingRepository {
  const UnavailableBillingRepository();

  @override
  Future<BillingRestoreResult> restorePurchases() async =>
      BillingRestoreResult.unavailable;
}
