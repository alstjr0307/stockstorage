import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';

class NightFuturesTick {
  final DateTime time;
  final double price;
  final double change;
  final double changeRate;

  NightFuturesTick({
    required this.time,
    required this.price,
    required this.change,
    required this.changeRate,
  });
}

class KisWebSocketService {
  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<NightFuturesTick>.broadcast();

  Stream<NightFuturesTick> get stream => _controller.stream;

  void connect(String approvalKey, String symbol) {
    _channel = IOWebSocketChannel.connect(
      Uri.parse('ws://ops.koreainvestment.com:31000'),
    );

    _channel!.sink.add(jsonEncode({
      'header': {
        'approval_key': approvalKey,
        'custtype': 'P',
        'tr_type': '1',
        'content-type': 'utf-8',
      },
      'body': {
        'input': {'tr_id': 'H0UPANC0', 'tr_key': symbol},
      },
    }));

    _sub = _channel!.stream.listen(
      (raw) => _handleMessage(raw.toString()),
      onError: (_) {},
      onDone: () {},
    );
  }

  void _handleMessage(String msg) {
    if (msg.startsWith('{')) {
      try {
        final json = jsonDecode(msg) as Map<String, dynamic>;
        if (json['header']?['tr_id'] == 'PINGPONG') {
          _channel?.sink.add(msg);
        }
      } catch (_) {}
      return;
    }

    final parts = msg.split('|');
    if (parts.length < 4 || parts[1] != 'H0UPANC0') return;

    final fields = parts[3].split('^');
    if (fields.length < 6) return;

    final price = double.tryParse(fields[2]);
    final change = double.tryParse(fields[4]);
    final changeRate = double.tryParse(fields[5]);
    if (price == null || price <= 0) return;

    _controller.add(NightFuturesTick(
      time: DateTime.now(),
      price: price,
      change: change ?? 0,
      changeRate: changeRate ?? 0,
    ));
  }

  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
