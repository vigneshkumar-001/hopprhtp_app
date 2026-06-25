import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../data/dto/transaction_dto.dart';

/// Loads and caches the signed-in user's transactions. Call [refresh] after a
/// lifecycle action (fund/ship/confirm) to re-sync from the server.
class TransactionsNotifier extends AsyncNotifier<List<ApiTransaction>> {
  @override
  Future<List<ApiTransaction>> build() =>
      ref.read(transactionRepositoryProvider).list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(transactionRepositoryProvider).list());
  }
}

/// The full transaction list (one network fetch, cached).
final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<ApiTransaction>>(
        TransactionsNotifier.new);

/// A Home-tab slice derived from [transactionsProvider]. Because it filters the
/// already-loaded list, switching tabs is instant and triggers no extra fetch —
/// and a widget watching one stage only rebuilds when that stage changes.
final transactionsByStageProvider =
    Provider.family<AsyncValue<List<ApiTransaction>>, ApiTxStage>((ref, stage) {
  return ref.watch(transactionsProvider).whenData(
        (list) => list.where((t) => t.stage == stage).toList(growable: false),
      );
});

/// Single-transaction detail, auto-disposed when no screen is watching it.
final transactionDetailProvider =
    FutureProvider.autoDispose.family<ApiTransaction, String>((ref, id) {
  return ref.watch(transactionRepositoryProvider).getById(id);
});
