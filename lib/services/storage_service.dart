import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static final _storage = FirebaseStorage.instanceFor(
    bucket: 'gs://stockstorage-13828.firebasestorage.app',
  );
  static final _picker = ImagePicker();

  /// 갤러리에서 이미지 최대 [maxImages]장 선택
  static Future<List<XFile>> pickImages({int maxImages = 5}) async {
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return [];
    return picked.take(maxImages).toList();
  }

  /// 카메라로 이미지 1장 촬영
  static Future<XFile?> pickFromCamera() async {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
  }

  static const _allowedExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  static String _extensionOf(XFile file) {
    for (final candidate in [file.name, file.path]) {
      final ext = candidate.split('.').last.toLowerCase();
      if (_allowedExts.contains(ext)) return ext == 'jpeg' ? 'jpg' : ext;
    }
    return switch (file.mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
  }

  /// Firebase Storage에 이미지 업로드 → 다운로드 URL 반환
  /// putData(bytes) 방식: Android content URI에서도 안정적으로 동작
  static Future<String> uploadImage({
    required XFile file,
    required String folder,
    required String uid,
  }) async {
    // 웹에서는 XFile.path 가 blob URL 이라 확장자를 뽑을 수 없다 → name/mimeType 사용
    final ext = _extensionOf(file);
    final mime =
        file.mimeType ??
        (ext == 'png'
            ? 'image/png'
            : ext == 'webp'
            ? 'image/webp'
            : ext == 'gif'
            ? 'image/gif'
            : 'image/jpeg');
    final name = '${DateTime.now().millisecondsSinceEpoch}_$uid.$ext';
    final ref = _storage.ref('$folder/$name');
    final bytes = await file.readAsBytes();
    final snapshot = await ref.putData(
      bytes,
      SettableMetadata(contentType: mime),
    );
    return snapshot.ref.getDownloadURL();
  }

  /// 여러 이미지를 순서대로 업로드 → URL 리스트 반환
  static Future<List<String>> uploadImages({
    required List<XFile> files,
    required String folder,
    required String uid,
  }) async {
    final urls = await Future.wait(
      files.map((f) => uploadImage(file: f, folder: folder, uid: uid)),
    );
    return urls;
  }

  /// Storage URL로 파일 삭제
  static Future<void> deleteByUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {}
  }
}
