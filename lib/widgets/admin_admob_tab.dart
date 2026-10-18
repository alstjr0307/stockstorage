import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admob_revenue_service.dart';
import '../services/auth_service.dart';

class AdminAdmobTab extends StatefulWidget {
  const AdminAdmobTab({super.key});
  @override
  State<AdminAdmobTab> createState() => _AdminAdmobTabState();
}

class _AdminAdmobTabState extends State<AdminAdmobTab> {
  late final AdmobRevenueService _service;
  Map<String, dynamic>? _report;
  bool _loading = false;
  bool _connectRequired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (AuthService().isAdmin) {
      _service = AdmobRevenueService();
      _load();
    }
  }

  Future<void> _load({bool connect = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (connect && !await _service.connect()) return;
      final report = await _service.load(refresh: _report != null || connect);
      if (mounted) {
        setState(() {
          _report = report;
          _connectRequired = false;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? '수익 정보를 불러오지 못했습니다.';
          _connectRequired =
              e.details is Map && e.details['reason'] == 'connect-required';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Google 계정 연결을 완료하지 못했습니다. 다시 시도해 주세요.';
          _connectRequired = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic value) => NumberFormat.simpleCurrency(
    name: _report!['currency'] as String,
    decimalDigits: _report!['currency'] == 'KRW' ? 0 : 2,
  ).format(value ?? 0);

  Widget _summary(String title, String key) {
    final values = Map<String, dynamic>.from(_report![key] as Map);
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 6),
              Text(
                _money(values['earnings']),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '노출 ${NumberFormat.decimalPattern().format(values['impressions'])}회 · 클릭 ${values['clicks']}회',
              ),
              Text(
                '광고 요청 ${NumberFormat.decimalPattern().format(values['requests'])}회',
              ),
              Text('1,000회 노출당 수익 ${_money(values['ecpm'])}'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService().isAdmin) {
      return const Center(child: Text('관리자만 조회할 수 있습니다.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('애드몹 예상 수익', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          '주식저장소 Android·iOS의 AdMob 네트워크 수익입니다.\n애드몹 집계가 늦게 반영되거나 금액이 조정될 수 있습니다.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : () => _load(connect: true),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(_connectRequired ? '애드몹 계정 연결' : 'Google 계정 연결'),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh),
              label: const Text('새로고침'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://apps.admob.com/'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('애드몹 열기'),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_report == null && !_loading)
          const Text('애드몹에 접근할 수 있는 Google 계정으로 연결하고 보고서 조회를 허용해 주세요.'),
        if (_report != null) ...[
          if (_error != null) const Text('아래는 마지막으로 조회한 자료입니다.'),
          Text(
            '보고서 날짜 ${_report!['reportDate']} · ${_report!['timeZone']} · ${_report!['currency']}',
          ),
          Text(
            '조회 ${DateFormat('MM.dd HH:mm').format(DateTime.parse(_report!['fetchedAt'] as String).toLocal())}${_report!['cached'] == true ? ' · 저장된 자료' : ''}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summary('오늘', 'today'),
              _summary('어제', 'yesterday'),
              _summary('이번 달', 'month'),
            ],
          ),
          const SizedBox(height: 20),
          Text('최근 7일', style: Theme.of(context).textTheme.titleMedium),
          for (final raw in _report!['week'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${raw['date'].toString().substring(4, 6)}.${raw['date'].toString().substring(6, 8)}',
              ),
              subtitle: Text(
                '노출 ${raw['impressions']}회 · 클릭 ${raw['clicks']}회',
              ),
              trailing: Text(
                _money(raw['earnings']),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          const Text('조회 결과는 최대 5분간 재사용합니다. 새로고침은 최소 1분 간격으로 갱신됩니다.'),
        ],
      ],
    );
  }
}
