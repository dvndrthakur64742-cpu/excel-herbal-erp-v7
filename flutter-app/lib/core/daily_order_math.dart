abstract final class DailyOrderMath {
  static double retailSold(num issued, num returned, num wholesale) {
    final value =
        issued.toDouble() - returned.toDouble() - wholesale.toDouble();
    return value > 0 ? value : 0;
  }

  static bool quantitiesFit(num issued, num returned, num wholesale) =>
      returned >= 0 &&
      wholesale >= 0 &&
      returned.toDouble() + wholesale.toDouble() <= issued.toDouble() + 0.0001;

  static bool wholesaleRateValid(
    num wholesaleQty,
    num wholesaleRate,
    num retailRate,
  ) {
    if (wholesaleQty <= 0) return true;
    return wholesaleRate > 0 &&
        wholesaleRate.toDouble() <= retailRate.toDouble() + 0.005;
  }

  static double totalAmount(
    num retailSold,
    num retailRate,
    num wholesaleQty,
    num wholesaleRate,
  ) =>
      retailSold.toDouble() * retailRate.toDouble() +
      wholesaleQty.toDouble() * wholesaleRate.toDouble();

  static bool depositMatches(num entered, num expected) =>
      (entered.toDouble() - expected.toDouble()).abs() <= 0.005;

  static bool paymentComponentsValid(num cash, num online) =>
      cash.toDouble().isFinite &&
      online.toDouble().isFinite &&
      cash.toDouble() >= 0 &&
      online.toDouble() >= 0;

  static bool reconciliationMatches(num serverExpected, num calculated) =>
      (serverExpected.toDouble() - calculated.toDouble()).abs() <= 0.01;

  static bool finalPostAllowed({
    required num cash,
    required num online,
    required num expected,
    required num calculatedExpected,
    num? serverExpected,
  }) {
    if (!paymentComponentsValid(cash, online)) return false;
    if (!depositMatches(cash.toDouble() + online.toDouble(), expected)) {
      return false;
    }
    if (serverExpected != null &&
        !reconciliationMatches(serverExpected, calculatedExpected)) {
      return false;
    }
    return true;
  }
}
