import 'package:escrow/data/dto/transaction_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiTransaction.fromJson', () {
    test('parses the lean list shape (_id, kobo money, status/stage)', () {
      final tx = ApiTransaction.fromJson({
        '_id': '64f0aabbccddeeff00112233',
        'code': 'HTP-7Q2K',
        'reference': 'HTP-XYZ',
        'merchantName': 'Mira Atelier',
        'productName': 'Linen Set',
        'status': 'out_for_delivery',
        'stage': 'active',
        'itemSubtotalKobo': 5122000,
        'deliveryFeeKobo': 750000,
        'grandTotalKobo': 5872000,
        'trustFullKobo': 76830,
        'feeSplit': 'split',
        'currency': 'NGN',
        'inspectionPeriodSeconds': 86400,
        'createdAt': '2026-06-24T10:00:00.000Z',
      });

      expect(tx.id, '64f0aabbccddeeff00112233');
      expect(tx.status, ApiTxStatus.outForDelivery);
      expect(tx.stage, ApiTxStage.active);
      expect(tx.itemSubtotalNaira, 51220.0); // kobo → naira
      expect(tx.grandTotalNaira, 58720.0);
    });

    test('prefers the id virtual over _id (detail shape)', () {
      final tx = ApiTransaction.fromJson({
        'id': 'abc',
        '_id': 'zzz',
        'code': 'C',
        'status': 'cooling',
        'stage': 'cooling',
      });
      expect(tx.id, 'abc');
      expect(tx.status, ApiTxStatus.cooling);
      expect(tx.stage, ApiTxStage.cooling);
    });

    test('unknown/absent fields fall back safely', () {
      final tx = ApiTransaction.fromJson({'status': 'martian', 'stage': 'done'});
      expect(tx.status, ApiTxStatus.unknown);
      expect(tx.stage, ApiTxStage.done);
      expect(tx.grandTotalKobo, 0);
    });
  });
}
