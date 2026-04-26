import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/post.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

// ─── Content block types ─────────────────────────────────────────────────────

class _TextBlock {
  final TextEditingController ctrl;
  final FocusNode focus;
  _TextBlock([String text = ''])
    : ctrl = TextEditingController(text: text),
      focus = FocusNode();
  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}

class _ImageBlock {
  final XFile file;
  String? uploadedUrl;
  _ImageBlock(this.file);
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class WritePostScreen extends StatefulWidget {
  final String uid;
  final String nickname;

  const WritePostScreen({super.key, required this.uid, required this.nickname});

  @override
  State<WritePostScreen> createState() => _WritePostScreenState();
}

class _WritePostScreenState extends State<WritePostScreen> {
  final _titleCtrl = TextEditingController();
  final _fs = FirestoreService();

  final List<Object> _blocks = []; // _TextBlock | _ImageBlock
  _TextBlock? _lastFocused;
  bool _saving = false;
  static const _maxImages = 5;

  @override
  void initState() {
    super.initState();
    _blocks.add(_listenedTextBlock());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final b in _blocks) {
      if (b is _TextBlock) b.dispose();
    }
    super.dispose();
  }

  // ── Block helpers ─────────────────────────────────────────────────────────

  _TextBlock _listenedTextBlock([String text = '']) {
    final b = _TextBlock(text);
    b.focus.addListener(() {
      if (b.focus.hasFocus) _lastFocused = b;
    });
    return b;
  }

  int get _imageCount => _blocks.whereType<_ImageBlock>().length;

  // ── 포맷팅 ────────────────────────────────────────────────────────────────

  void _applyFormat(String prefix, String suffix) {
    final block = _lastFocused ?? _blocks.whereType<_TextBlock>().lastOrNull;
    if (block == null) return;
    final ctrl = block.ctrl;
    final sel = ctrl.selection;
    final text = ctrl.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = text.substring(start, end);
    final before = text.substring(0, start);
    final after = text.substring(end);

    if (selected.isEmpty) {
      ctrl.value = ctrl.value.copyWith(
        text: before + prefix + suffix + after,
        selection: TextSelection.collapsed(offset: start + prefix.length),
      );
    } else if (selected.startsWith(prefix) && selected.endsWith(suffix)) {
      final inner = selected.substring(
        prefix.length,
        selected.length - suffix.length,
      );
      ctrl.value = ctrl.value.copyWith(
        text: before + inner + after,
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + inner.length,
        ),
      );
    } else {
      ctrl.value = ctrl.value.copyWith(
        text: before + prefix + selected + suffix + after,
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + prefix.length + selected.length + suffix.length,
        ),
      );
    }
    block.focus.requestFocus();
  }

  void _applyBullet() {
    final block = _lastFocused ?? _blocks.whereType<_TextBlock>().lastOrNull;
    if (block == null) return;
    final ctrl = block.ctrl;
    final text = ctrl.text;
    final pos = ctrl.selection.isValid
        ? ctrl.selection.baseOffset
        : text.length;
    final lineStart = text.lastIndexOf('\n', pos > 0 ? pos - 1 : 0);
    final insertAt = lineStart == -1 ? 0 : lineStart + 1;
    if (text.substring(insertAt, pos).startsWith('- ')) {
      ctrl.value = ctrl.value.copyWith(
        text: text.substring(0, insertAt) + text.substring(insertAt + 2),
        selection: TextSelection.collapsed(offset: pos - 2),
      );
    } else {
      ctrl.value = ctrl.value.copyWith(
        text: '${text.substring(0, insertAt)}- ${text.substring(insertAt)}',
        selection: TextSelection.collapsed(offset: pos + 2),
      );
    }
    block.focus.requestFocus();
  }

  // ── 이미지 ────────────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final remaining = _maxImages - _imageCount;
    if (remaining <= 0) {
      _showMaxSnack();
      return;
    }
    final picked = await StorageService.pickImages(maxImages: remaining);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        _insertImage(_ImageBlock(f));
      }
    });
  }

  Future<void> _pickFromCamera() async {
    if (_imageCount >= _maxImages) {
      _showMaxSnack();
      return;
    }
    final f = await StorageService.pickFromCamera();
    if (f == null || !mounted) return;
    setState(() => _insertImage(_ImageBlock(f)));
  }

  void _insertImage(_ImageBlock img) {
    int insertAfter;
    if (_lastFocused != null) {
      final idx = _blocks.indexOf(_lastFocused!);
      insertAfter = idx == -1 ? _blocks.length - 1 : idx;
    } else {
      insertAfter = _blocks.length - 1;
    }
    _blocks.insert(insertAfter + 1, img);
    // Ensure a text block follows the image
    if (insertAfter + 2 >= _blocks.length ||
        _blocks[insertAfter + 2] is _ImageBlock) {
      final next = _listenedTextBlock();
      _blocks.insert(insertAfter + 2, next);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => next.focus.requestFocus(),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _blocks.removeAt(index);
      // Merge consecutive text blocks
      for (int i = _blocks.length - 1; i > 0; i--) {
        if (_blocks[i] is _TextBlock && _blocks[i - 1] is _TextBlock) {
          final a = _blocks[i - 1] as _TextBlock;
          final b = _blocks[i] as _TextBlock;
          final merged = _listenedTextBlock(
            [a.ctrl.text, b.ctrl.text].where((s) => s.isNotEmpty).join('\n'),
          );
          a.dispose();
          b.dispose();
          _blocks.removeAt(i);
          _blocks[i - 1] = merged;
        }
      }
      if (_blocks.isEmpty) _blocks.add(_listenedTextBlock());
    });
  }

  void _moveImageUp(int index) {
    setState(() {
      int prev = index - 1;
      while (prev >= 0 && _blocks[prev] is _TextBlock) {
        prev--;
      }
      if (prev < 0) return;
      final tmp = _blocks[index];
      _blocks[index] = _blocks[prev];
      _blocks[prev] = tmp;
    });
  }

  void _moveImageDown(int index) {
    setState(() {
      int next = index + 1;
      while (next < _blocks.length && _blocks[next] is _TextBlock) {
        next++;
      }
      if (next >= _blocks.length) return;
      final tmp = _blocks[index];
      _blocks[index] = _blocks[next];
      _blocks[next] = tmp;
    });
  }

  void _showMaxSnack() => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('사진은 최대 5장까지 첨부할 수 있습니다')));

  void _showImageSourceSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFF10B981),
              ),
              title: Text('갤러리에서 선택', style: TextStyle(color: cs.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Color(0xFF10B981),
              ),
              title: Text('카메라로 촬영', style: TextStyle(color: cs.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _pickFromCamera();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── 등록 ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제목을 입력해주세요')));
      return;
    }
    setState(() => _saving = true);

    final imgBlocks = _blocks.whereType<_ImageBlock>().toList();
    if (imgBlocks.isNotEmpty) {
      try {
        for (int i = 0; i < imgBlocks.length; i++) {
          imgBlocks[i].uploadedUrl = await StorageService.uploadImage(
            file: imgBlocks[i].file,
            folder: 'posts',
            uid: widget.uid,
          );
        }
      } catch (e) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('사진 업로드 실패'),
            content: Text('사진 업로드에 실패했습니다.\n사진 없이 글을 등록할까요?\n\n(오류: $e)'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '사진 없이 등록',
                  style: TextStyle(color: Color(0xFF10B981)),
                ),
              ),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        for (final b in imgBlocks) {
          b.uploadedUrl = null;
        }
      }
    }

    // Build markdown body with inline images
    final sb = StringBuffer();
    for (final block in _blocks) {
      if (block is _TextBlock) {
        final t = block.ctrl.text.trim();
        if (t.isNotEmpty) {
          if (sb.isNotEmpty) sb.write('\n\n');
          sb.write(t);
        }
      } else if (block is _ImageBlock && block.uploadedUrl != null) {
        if (sb.isNotEmpty) sb.write('\n\n');
        sb.write('![](${block.uploadedUrl})');
      }
    }

    try {
      await _fs.createPost(
        Post(
          id: '',
          uid: widget.uid,
          nickname: widget.nickname,
          title: title,
          content: sb.toString(),
          likes: 0,
          createdAt: DateTime.now(),
          imageUrls: const [],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('글 저장 실패: $e')));
        setState(() => _saving = false);
      }
    }
  }

  // ── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '새 글 작성',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _submit,
                  child: Text(
                    '등록',
                    style: TextStyle(
                      color: const Color(0xFF10B981),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, thickness: 0.5),

          // ── 스크롤 영역 ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: '제목',
                      hintStyle: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.next,
                  ),
                  Divider(
                    height: 24,
                    thickness: 0.5,
                    color: cs.onSurface.withValues(alpha: 0.1),
                  ),

                  // ── 본문 블록들 ──
                  for (int i = 0; i < _blocks.length; i++)
                    if (_blocks[i] is _TextBlock)
                      _buildTextBlock(_blocks[i] as _TextBlock, i)
                    else
                      _buildImageBlock(_blocks[i] as _ImageBlock, i),
                ],
              ),
            ),
          ),

          // ── 하단 툴바 ──
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  top: BorderSide(
                    color: cs.onSurface.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _FmtBtn(
                    label: 'B',
                    bold: true,
                    onTap: () => _applyFormat('**', '**'),
                  ),
                  _FmtBtn(
                    label: 'I',
                    italic: true,
                    onTap: () => _applyFormat('*', '*'),
                  ),
                  _FmtBtn(
                    label: 'S',
                    strikethrough: true,
                    onTap: () => _applyFormat('~~', '~~'),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.format_list_bulleted,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    onPressed: _applyBullet,
                  ),
                  Container(
                    width: 0.5,
                    height: 20,
                    color: cs.onSurface.withValues(alpha: 0.15),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.image_outlined,
                      size: 22,
                      color: _imageCount >= _maxImages
                          ? cs.onSurface.withValues(alpha: 0.3)
                          : cs.onSurface.withValues(alpha: 0.6),
                    ),
                    tooltip: '사진 삽입',
                    onPressed: _imageCount >= _maxImages
                        ? null
                        : _showImageSourceSheet,
                  ),
                  if (_imageCount > 0)
                    Text(
                      '$_imageCount/$_maxImages',
                      style: TextStyle(
                        color: const Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(_TextBlock block, int index) {
    final cs = Theme.of(context).colorScheme;
    final isFirstText = _blocks.whereType<_TextBlock>().firstOrNull == block;
    return TextField(
      controller: block.ctrl,
      focusNode: block.focus,
      style: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.7),
      decoration: InputDecoration(
        hintText: isFirstText ? '내용을 입력해주세요' : null,
        hintStyle: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.3),
          fontSize: 15,
        ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
      maxLines: null,
      minLines: 1,
    );
  }

  Widget _buildImageBlock(_ImageBlock block, int index) {
    final imgBlocks = _blocks.whereType<_ImageBlock>().toList();
    final imgIdx = imgBlocks.indexOf(block);
    final isFirstImg = imgIdx == 0;
    final isLastImg = imgIdx == imgBlocks.length - 1;

    return Padding(
      key: ValueKey(block),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(block.file.path),
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isFirstImg)
                    _ImgCtrlBtn(
                      icon: Icons.keyboard_arrow_up,
                      onTap: () => _moveImageUp(index),
                    ),
                  if (!isLastImg)
                    _ImgCtrlBtn(
                      icon: Icons.keyboard_arrow_down,
                      onTap: () => _moveImageDown(index),
                    ),
                  _ImgCtrlBtn(
                    icon: Icons.close,
                    onTap: () => _removeImage(index),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 공통 위젯 ───────────────────────────────────────────────────────────────

class _ImgCtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ImgCtrlBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _FmtBtn extends StatelessWidget {
  final String label;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final VoidCallback onTap;

  const _FmtBtn({
    required this.label,
    required this.onTap,
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.6),
            fontSize: 15,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            decoration: strikethrough
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            decorationColor: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
