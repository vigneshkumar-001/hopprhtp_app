import 'package:escrow/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // PaymentDraft.trustRate is a static, so tests set it explicitly rather
  // than relying on whatever a previous test (or the shipped default) left
  // it at — avoids order-dependent flakiness.
  setUp(() {
    PaymentDraft.trustRate = 0.015;
  });

  PaymentDraft draft({
    required double itemSubtotal,
    required PlatformFeePayer payer,
    double deliveryFee = 0,
  }) => PaymentDraft(
    productName: 'Test product',
    sellerName: 'Test seller',
    sellerCode: 'HTP-TEST',
    itemSubtotal: itemSubtotal,
    platformFeePayer: payer,
    deliveryFee: deliveryFee,
  );

  group('PaymentDraft — money breakdown (mirrors backend computeFees)', () {
    test('buyer pays the full platform fee on top of the item price', () {
      final d = draft(itemSubtotal: 100000, payer: PlatformFeePayer.buyer);

      expect(d.trustFull, 1500); // 1.5% of 100,000
      expect(d.buyerTrustShare, 1500);
      expect(d.sellerTrustShare, 0);
      expect(d.grandTotal, 101500); // item + full fee, no delivery
      expect(d.sellerReceivable, 100000); // seller keeps every naira of the item price
    });

    test('seller absorbs the full platform fee — buyer pays item price only', () {
      final d = draft(itemSubtotal: 100000, payer: PlatformFeePayer.seller);

      expect(d.buyerTrustShare, 0);
      expect(d.sellerTrustShare, 1500);
      expect(d.grandTotal, 100000);
      expect(d.sellerReceivable, 98500);
    });

    test('split50 divides the fee, and the two shares sum back to the full fee', () {
      final d = draft(itemSubtotal: 100000, payer: PlatformFeePayer.split50);

      expect(d.trustFull, 1500);
      expect(d.buyerTrustShare, 750);
      expect(d.sellerTrustShare, 750);
      expect(d.buyerTrustShare + d.sellerTrustShare, d.trustFull);
      expect(d.grandTotal, 100750);
      expect(d.sellerReceivable, 99250);
    });

    test('delivery fee is added to what the buyer pays but never touches what the seller receives', () {
      final d = draft(
        itemSubtotal: 100000,
        payer: PlatformFeePayer.buyer,
        deliveryFee: 2000,
      );

      expect(d.grandTotal, 103500); // 100,000 item + 1,500 fee + 2,000 delivery
      expect(d.sellerReceivable, 100000); // delivery fee never reduces the seller's payout
    });

    test('a zero item amount produces a zero fee and a zero grand total', () {
      final d = draft(itemSubtotal: 0, payer: PlatformFeePayer.buyer);

      expect(d.trustFull, 0);
      expect(d.grandTotal, 0);
      expect(d.sellerReceivable, 0);
    });

    test('reflects whatever trustRate is currently set to (kept in sync from the backend at startup)', () {
      PaymentDraft.trustRate = 0.02; // simulates a different admin-configured percentage
      final d = draft(itemSubtotal: 100000, payer: PlatformFeePayer.buyer);

      expect(d.trustFull, 2000);
    });
  });
}
