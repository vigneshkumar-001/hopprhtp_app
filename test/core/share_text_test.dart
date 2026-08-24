import 'package:escrow/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareText.paymentRequest', () {
    test('personalizes the buyer greeting and every field, matching the requested format', () {
      final message = ShareText.paymentRequest(
        sellerName: 'Samuel Stephen',
        productName: '2023 Lexus GX460 Steering Wheel',
        amount: 708150,
        code: 'HTP-CZ4R',
        link: 'https://hoppr-htp-ccf74f30631f.herokuapp.com/pay/HTP-CZ4R',
        buyerName: 'Godfrey',
      );

      expect(
        message,
        'Hoppr Secure Payment\n\n'
        'Hello Godfrey, Samuel Stephen has created a secure payment request '
        'for your 2023 Lexus GX460 Steering Wheel through Hoppr Trust Protocol (HTP).\n\n'
        'Amount: ₦708,150\n'
        'Transaction ID: HTP-CZ4R\n'
        'Pay securely: https://hoppr-htp-ccf74f30631f.herokuapp.com/pay/HTP-CZ4R\n\n'
        'Your payment is protected in escrow until delivery is verified.',
      );
    });

    test('falls back to a plain "Hello," when the buyer name is null', () {
      final message = ShareText.paymentRequest(
        sellerName: 'Samuel Stephen',
        productName: 'Steering Wheel',
        amount: 5000,
        code: 'HTP-ABCD',
        link: 'https://example.com/pay/HTP-ABCD',
      );
      expect(message, startsWith('Hoppr Secure Payment\n\nHello, Samuel Stephen has created'));
    });

    test('falls back to a plain "Hello," when the buyer name is blank/whitespace-only', () {
      final message = ShareText.paymentRequest(
        sellerName: 'Samuel Stephen',
        productName: 'Steering Wheel',
        amount: 5000,
        code: 'HTP-ABCD',
        link: 'https://example.com/pay/HTP-ABCD',
        buyerName: '   ',
      );
      expect(message, startsWith('Hoppr Secure Payment\n\nHello, Samuel Stephen has created'));
    });

    test('trims a buyer name with surrounding whitespace', () {
      final message = ShareText.paymentRequest(
        sellerName: 'Samuel Stephen',
        productName: 'Steering Wheel',
        amount: 5000,
        code: 'HTP-ABCD',
        link: 'https://example.com/pay/HTP-ABCD',
        buyerName: '  Godfrey  ',
      );
      expect(message, startsWith('Hoppr Secure Payment\n\nHello Godfrey, Samuel Stephen has created'));
    });

    test('formats whole-naira amounts with no decimals, thousands-grouped', () {
      final message = ShareText.paymentRequest(
        sellerName: 'S',
        productName: 'P',
        amount: 1250000,
        code: 'HTP-X',
        link: 'l',
      );
      expect(message, contains('Amount: ₦1,250,000'));
    });
  });
}
