import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stock_pick.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Stream<List<StockPick>> getStockPicks({bool premiumOnly = false}) {
    Query query = _db
        .collection('stock_picks')
        .orderBy('createdAt', descending: true);

    if (premiumOnly) {
      query = query.where('isPremium', isEqualTo: true);
    }

    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => StockPick.fromFirestore(doc)).toList());
  }

  Future<void> addStockPick(StockPick pick) {
    return _db.collection('stock_picks').add(pick.toFirestore());
  }

  Future<void> updateStockPick(StockPick pick) {
    return _db
        .collection('stock_picks')
        .doc(pick.id)
        .update(pick.toFirestore());
  }

  Future<void> deleteStockPick(String id) {
    return _db.collection('stock_picks').doc(id).delete();
  }
}
