import 'paste_image.dart';

// 네이티브에는 문서 단위 붙여넣기 이벤트가 없으므로 no-op.
void Function() listenPastedContent(void Function(List<PastedPart>) onPasted) =>
    () {};
