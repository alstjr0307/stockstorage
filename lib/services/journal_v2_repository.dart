import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trading_journal.dart';
import 'firestore_service.dart';
import 'journal_ledger.dart';

class JournalWriteException implements Exception {
  const JournalWriteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Uses the existing collection/schema. No migration or writes on view.
class JournalV2Repository {
  JournalV2Repository(this.uid, {FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  final String uid;
  final FirebaseFirestore _db;
  static final _writing = <String>{};
  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('trading_journal');
  String newId() => _collection.doc().id;
  Stream<List<TradingJournal>> watch() => _collection
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(TradingJournal.fromFirestore).toList());

  static Map<String, dynamic> editablePayload(
    TradingJournal next,
    TradingJournal old,
  ) => {
    'price': next.price,
    'quantity': next.quantity,
    'tradeDate': Timestamp.fromDate(next.tradeDate),
    'note': next.note,
    'isPublic': next.isPublic,
    if (!old.isPublic && next.isPublic)
      'publishedAt': FieldValue.serverTimestamp(),
  };

  Future<void> save(TradingJournal next, {TradingJournal? original}) =>
      _mutate(next: next, original: original);
  Future<void> remove(TradingJournal original) => _mutate(original: original);

  /// Old deployed rules do not expose journal_revisions. Only that read's
  /// permission denial enables compatibility; journal access is still enforced.
  static Future<int?> readCompatibleRevision(
    Future<int> Function() read,
  ) async {
    try {
      return await read();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  static bool sameEditableRecord(TradingJournal a, TradingJournal b) =>
      a.id == b.id &&
      JournalLedger.sameFinancialRecord(a, b) &&
      a.note == b.note &&
      a.isPublic == b.isPublic;

  /// A lost acknowledgement must not turn a successful edit retry into a stale
  /// edit error. Only accept the exact desired editable values; never overwrite.
  static bool editAlreadyApplied(
    TradingJournal? stored,
    TradingJournal original,
    TradingJournal next,
  ) =>
      stored != null &&
      !sameEditableRecord(original, next) &&
      sameEditableRecord(stored, next);

  Future<void> _mutate({TradingJournal? next, TradingJournal? original}) async {
    if (next != null && original != null && next.id != original.id) {
      throw const JournalWriteException('수정할 기록의 ID가 일치하지 않습니다.');
    }
    if (next?.uid != null && next!.uid != uid ||
        original?.uid != null && original!.uid != uid) {
      throw const JournalWriteException('계정이 변경되었습니다. 다시 열어주세요.');
    }
    if (!_writing.add(uid)) {
      throw const JournalWriteException('다른 기록을 저장 중이에요. 잠시 후 다시 시도해주세요.');
    }
    try {
      // Read the revision BEFORE the query. A revision change in the transaction
      // means that the whole validation snapshot (including new documents) is stale.
      final gate = _db.collection('journal_revisions').doc(uid);
      var committed = false;
      for (var attempt = 0; attempt < 4 && !committed; attempt++) {
        final revision = await readCompatibleRevision(() async {
          final snapshot = await gate.get(
            const GetOptions(source: Source.server),
          );
          return (snapshot.data()?['revision'] as num?)?.toInt() ?? 0;
        });
        final snap = await _collection
            .where('uid', isEqualTo: uid)
            .get(const GetOptions(source: Source.server));
        final all = snap.docs.map(TradingJournal.fromFirestore).toList();
        TradingJournal? stored;
        final id = next?.id ?? original!.id;
        for (final j in all) {
          if (j.id == id) stored = j;
        }
        if (next != null &&
            original != null &&
            editAlreadyApplied(stored, original, next)) {
          return;
        }
        if (original != null &&
            (stored == null ||
                !JournalLedger.sameFinancialRecord(stored, original) ||
                stored.note != original.note ||
                stored.isPublic != original.isPublic)) {
          throw const JournalWriteException('다른 곳에서 변경된 기록입니다. 닫고 다시 열어주세요.');
        }
        if (original == null && stored != null) {
          if (next != null &&
              JournalLedger.sameFinancialRecord(stored, next) &&
              stored.note == next.note &&
              stored.isPublic == next.isPublic) {
            return;
          }
          throw const JournalWriteException('이미 저장된 기록입니다. 목록을 확인해주세요.');
        }
        if (next != null &&
            original != null &&
            (JournalLedger.stockKey(next) != JournalLedger.stockKey(original) ||
                next.action != original.action)) {
          throw const JournalWriteException('수정할 때 종목과 거래 종류는 바꿀 수 없어요.');
        }
        final problem = JournalLedger.validateMutation(
          all,
          next: next,
          deleteId: next == null ? original!.id : null,
        );
        if (problem != null) throw JournalWriteException(problem);
        try {
          committed = await _db.runTransaction<bool>((tx) async {
            if (revision != null) {
              final latestGate = await tx.get(gate);
              final latestRevision =
                  (latestGate.data()?['revision'] as num?)?.toInt() ?? 0;
              if (latestRevision != revision) return false;
            }
            // Detect edits/deletions of records used by the validation snapshot.
            for (final doc in snap.docs) {
              final latest = await tx.get(doc.reference);
              if (!latest.exists ||
                  !JournalLedger.sameFinancialRecord(
                    TradingJournal.fromFirestore(latest),
                    TradingJournal.fromFirestore(doc),
                  )) {
                throw const JournalWriteException('거래 기록이 변경되었습니다. 다시 확인해주세요.');
              }
              if (doc.id == original?.id &&
                  ((latest.data()?['note'] ?? '') != original!.note ||
                      (latest.data()?['isPublic'] ?? false) !=
                          original.isPublic)) {
                throw const JournalWriteException(
                  '수정 중 기록이 변경되었습니다. 다시 열어주세요.',
                );
              }
            }
            final ref = _collection.doc(id);
            if (next == null) {
              tx.delete(ref);
            } else if (original != null) {
              // Preserve likes, uid, createdAt, buyPrice, linkedBuyId and unknown fields.
              tx.update(ref, editablePayload(next, original));
            } else {
              final existing = await tx.get(ref);
              if (existing.exists) {
                throw const JournalWriteException('이미 저장된 기록입니다. 목록을 확인해주세요.');
              }
              tx.set(ref, {
                ...next.toFirestore(),
                if (next.isPublic) 'publishedAt': FieldValue.serverTimestamp(),
              });
            }
            if (revision != null) {
              tx.set(gate, {'revision': revision + 1, 'journalId': id});
            }
            return true;
          });
        } on FirebaseException catch (error) {
          // Security rules can reject a stale revision before the SDK reports
          // contention as `aborted`. Retry only when another writer advanced it.
          if (revision == null ||
              (error.code != 'permission-denied' && error.code != 'aborted')) {
            rethrow;
          }
          final current = await gate.get(
            const GetOptions(source: Source.server),
          );
          final currentRevision =
              (current.data()?['revision'] as num?)?.toInt() ?? 0;
          if (currentRevision == revision) rethrow;
        }
      }
      if (!committed) {
        throw const JournalWriteException(
          '다른 기기에서 기록을 변경 중입니다. 잠시 후 다시 저장해주세요.',
        );
      }
      // A reward failure is not a failed trade; never invite duplicate writes.
      try {
        final fs = FirestoreService();
        if (original == null) await fs.grantDailyJournalMissionXp(uid);
        if (original?.isPublic != true && next?.isPublic == true) {
          await fs.recordPostCreated(uid);
        }
        if (original?.isPublic == true && next?.isPublic != true) {
          await fs.recordPostRemoved(uid);
        }
      } catch (_) {}
    } finally {
      _writing.remove(uid);
    }
  }
}
