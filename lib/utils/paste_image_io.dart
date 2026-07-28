import 'package:cross_file/cross_file.dart';

// 네이티브에는 문서 단위 붙여넣기 이벤트가 없으므로 no-op.
void Function() listenPastedImages(void Function(List<XFile>) onImages) =>
    () {};
