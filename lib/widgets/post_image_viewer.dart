import '../services/post_image_save_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

void showPostImage(BuildContext context, String url) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PostImageViewer(url: url)));
}

class PostImage extends StatelessWidget {
  const PostImage({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '이미지 확대',
    button: true,
    child: InkWell(
      onTap: () => showPostImage(context, url),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}

class PostImageViewer extends StatefulWidget {
  const PostImageViewer({super.key, required this.url});
  final String url;

  @override
  State<PostImageViewer> createState() => _PostImageViewerState();
}

class _PostImageViewerState extends State<PostImageViewer> {
  final _transform = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final message = await savePostImage(widget.url);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미지를 저장하지 못했습니다. 네트워크와 사진 저장 권한을 확인해 주세요.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: IconButton(
        tooltip: '닫기',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          tooltip: '확대 초기화',
          onPressed: () => _transform.value = Matrix4.identity(),
          icon: const Icon(Icons.fit_screen),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(_saving ? '저장 중' : '저장'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
      ],
    ),
    body: SizedBox.expand(
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 8,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.contain,
            placeholder: (_, _) => const CircularProgressIndicator(),
            errorWidget: (_, _, _) => const Text(
              '이미지를 불러오지 못했습니다.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
