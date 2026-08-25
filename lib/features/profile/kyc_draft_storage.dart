import 'dart:convert';
import 'dart:io' show File;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'identity_verification_screen.dart';

/// Persists in-progress KYC capture (document photos + selfie) across app
/// restarts. Nothing here is ever uploaded to the backend until the user
/// actually taps Submit on [ReviewSubmitScreen] — this only remembers local
/// file paths, so a seller who backgrounds mid-flow (or whose phone/OS kills
/// the app process while they're away, which the OS is free to do at any
/// time once an app is backgrounded — not just a rare edge case) doesn't
/// have to re-photograph documents they already captured.
///
/// A saved path can still go stale — Android may reclaim the temp/cache
/// directory image_picker/camera write into while the app is gone — so
/// [load] drops any file that no longer exists rather than trusting it
/// blindly; the caller just re-captures that one piece, never the whole flow.
class KycDraftStorage {
  KycDraftStorage._();

  static const _key = 'hoppr.kycDraft.v1';

  static Future<void> save(KycDraft draft) async {
    if (draft.selectedDocIndexes.isEmpty) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode({
      'selectedDocIndexes': draft.selectedDocIndexes,
      'docs': draft.docs
          .map(
            (d) => {
              'docIndex': d.docIndex,
              'frontPath': d.front?.path,
              'backPath': d.back?.path,
            },
          )
          .toList(),
      'selfiePath': draft.selfie?.path,
    });
    await prefs.setString(_key, json);
  }

  /// Returns null when there's nothing saved, or nothing salvageable from
  /// what was saved (every referenced file is gone) — the caller treats
  /// either the same way: start fresh.
  static Future<KycDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final draft = KycDraft();
      draft.selectedDocIndexes = (json['selectedDocIndexes'] as List)
          .cast<int>();
      final docsJson = (json['docs'] as List).cast<Map<String, dynamic>>();
      draft.docs = docsJson.map((d) {
        final slot = KycDocSlot(d['docIndex'] as int);
        slot.front = _existingFile(d['frontPath'] as String?);
        slot.back = _existingFile(d['backPath'] as String?);
        return slot;
      }).toList();
      draft.selfie = _existingFile(json['selfiePath'] as String?);

      if (draft.selectedDocIndexes.isEmpty) return null;
      return draft;
    } catch (_) {
      // Malformed/unreadable — never crash the entry screen over a bad
      // local cache; just behave as if nothing was saved.
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static XFile? _existingFile(String? path) {
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? XFile(path) : null;
  }
}
