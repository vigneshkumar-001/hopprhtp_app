import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../data/dto/delivery_code_dto.dart';
import '../../../data/dto/delivery_verification_status_dto.dart';
import '../../../data/dto/dispute_dto.dart';
import '../../../data/dto/tracking_dto.dart';
import '../../../data/dto/transaction_dto.dart';
import '../../../data/dto/transaction_ledger_dto.dart';

/// Loads and caches the signed-in user's transactions. Call [refresh] after a
/// lifecycle action (fund/ship/confirm) to re-sync from the server.
class TransactionsNotifier extends AsyncNotifier<List<ApiTransaction>> {
  @override
  Future<List<ApiTransaction>> build() =>
      ref.read(transactionRepositoryProvider).list();

  Future<void> refresh() async {
    // Keep the previous list attached to the loading state (instead of a bare
    // AsyncLoading) so `.when()` can keep rendering cached data while this
    // reload is in flight — `skipLoadingOnRefresh` (Riverpod default: true)
    // then skips straight to `data:` with the stale list, no flicker.
    state = const AsyncLoading<List<ApiTransaction>>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(transactionRepositoryProvider).list(),
    );
  }
}

/// The full transaction list (one network fetch, cached).
final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<ApiTransaction>>(
      TransactionsNotifier.new,
    );

/// A Home-tab slice derived from [transactionsProvider]. Because it filters the
/// already-loaded list, switching tabs is instant and triggers no extra fetch —
/// and a widget watching one stage only rebuilds when that stage changes.
final transactionsByStageProvider =
    Provider.family<AsyncValue<List<ApiTransaction>>, ApiTxStage>((ref, stage) {
      return ref
          .watch(transactionsProvider)
          .whenData(
            (list) =>
                list.where((t) => t.stage == stage).toList(growable: false),
          );
    });

/// Single-transaction detail, auto-disposed when no screen is watching it.
final transactionDetailProvider = FutureProvider.autoDispose
    .family<ApiTransaction, String>((ref, id) {
      return ref.watch(transactionRepositoryProvider).getById(id);
    });

/// Tracking snapshot for one transaction. Manual refresh only — the Track
/// Package screen calls `ref.invalidate(trackingProvider(id))` to re-fetch;
/// nothing here polls on its own.
final trackingProvider = FutureProvider.autoDispose
    .family<TransactionTracking, String>((ref, id) {
      return ref.watch(transactionRepositoryProvider).getTracking(id);
    });

/// Seller-side delivery-confirmation eligibility. Manual refresh only, via
/// `ref.invalidate(deliveryVerificationStatusProvider(id))`.
final deliveryVerificationStatusProvider = FutureProvider.autoDispose
    .family<DeliveryVerificationStatus, String>((ref, id) {
      return ref
          .watch(transactionRepositoryProvider)
          .getDeliveryVerificationStatus(id);
    });

/// Buyer-only delivery code to share with the seller in person. Manual
/// refresh only, via `ref.invalidate(deliveryCodeProvider(id))`.
final deliveryCodeProvider = FutureProvider.autoDispose
    .family<DeliveryCode, String>((ref, id) {
      return ref.watch(transactionRepositoryProvider).getDeliveryCode(id);
    });

/// Seller-only pickup code to read out to the dispatcher in person. Manual
/// refresh only, via `ref.invalidate(pickupCodeProvider(id))`.
final pickupCodeProvider = FutureProvider.autoDispose
    .family<DeliveryCode, String>((ref, id) {
      return ref.watch(transactionRepositoryProvider).getPickupCode(id);
    });

/// Settlement/resolution ledger for one transaction. Manual refresh only, via
/// `ref.invalidate(transactionLedgerProvider(id))`.
final transactionLedgerProvider = FutureProvider.autoDispose
    .family<TransactionLedger, String>((ref, id) {
      return ref.watch(transactionRepositoryProvider).getTransactionLedger(id);
    });

/// Every dispute raised against one transaction. Manual refresh only, via
/// `ref.invalidate(transactionDisputesProvider(id))`.
final transactionDisputesProvider = FutureProvider.autoDispose
    .family<List<Dispute>, String>((ref, id) {
      return ref
          .watch(transactionRepositoryProvider)
          .getTransactionDisputes(id);
    });

/// A single dispute's full detail, keyed by dispute id (not transaction id).
final disputeDetailProvider = FutureProvider.autoDispose
    .family<Dispute, String>((ref, id) {
      return ref.watch(disputeRepositoryProvider).getById(id);
    });
