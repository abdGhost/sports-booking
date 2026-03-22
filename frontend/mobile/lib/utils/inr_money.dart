/// India (INR) formatting — join fees and prize money use ₹.
String formatInr(double amount) {
  if (amount < 0) {
    return '₹0';
  }
  if (amount == amount.roundToDouble()) {
    return '₹${amount.toStringAsFixed(0)}';
  }
  return '₹${amount.toStringAsFixed(2)}';
}
