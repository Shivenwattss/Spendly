import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class SmartInsightsScreen extends StatefulWidget {
  const SmartInsightsScreen({super.key});
  @override
  State<SmartInsightsScreen> createState() => _SmartInsightsScreenState();
}

class _SmartInsightsScreenState extends State<SmartInsightsScreen> {
  late Future<Map<String, dynamic>> future;
  Future<Map<String, dynamic>> _loadAll() async {
    final results = await Future.wait([ApiService.getSmartInsights(), ApiService.getSpendingForecast(), ApiService.getAnomalies(), ApiService.getRecommendations(), ApiService.getFinancialHealth()]);
    return {'insights_data': results[0], 'forecast': results[1], 'anomalies_data': results[2], 'recommendations_data': results[3], 'health': results[4]};
  }
  final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  @override
  void initState() { super.initState(); future = _loadAll(); }
  void reload() => setState(() => future = _loadAll());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Smart insights', style: TextStyle(fontWeight: FontWeight.w700)), actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 42), const SizedBox(height: 12), const Text('Could not load insights'), Text(snapshot.error.toString(), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: reload, child: const Text('Retry'))])));
        final bundle = snapshot.data!;
        final data = Map<String, dynamic>.from(bundle['insights_data'] as Map);
        final forecast = Map<String, dynamic>.from(bundle['forecast'] as Map);
        final anomalyData = Map<String, dynamic>.from(bundle['anomalies_data'] as Map);
        final recommendationData = Map<String, dynamic>.from(bundle['recommendations_data'] as Map);
        final health = Map<String, dynamic>.from(bundle['health'] as Map);
        final recommendations = (recommendationData['recommendations'] as List? ?? []).cast<Map>();
        final anomalies = (anomalyData['anomalies'] as List? ?? []).cast<Map>();
        final insights = (data['insights'] as List? ?? []).cast<Map>();
        final avg = (data['average_expenses_recent_months'] as num?)?.toDouble() ?? 0;
        final count = data['transaction_count'] ?? 0;
        final month = data['current_month']?.toString() ?? '';
        final monthIncome = (data['current_month_income'] as num?)?.toDouble() ?? 0;
        final monthExpenses = (data['current_month_expenses'] as num?)?.toDouble() ?? 0;
        return RefreshIndicator(onRefresh: () async => reload(), child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 30), children: [
          const Text('Your financial patterns', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5), const Text('Observations calculated from your saved transactions — no LLM involved.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 18),
          Row(children: [Expanded(child: _stat('Transactions', '$count')), const SizedBox(width: 10), Expanded(child: _stat('Recent monthly expense avg.', money.format(avg)))]),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Current month · $month', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 12), _amountRow('Income', monthIncome, Colors.green), const SizedBox(height: 8), _amountRow('Expenses', monthExpenses, Colors.deepOrange), const SizedBox(height: 8), _amountRow('Net cash flow', monthIncome - monthExpenses, null)]))),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Financial health indicator', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${health['score'] ?? 0}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)), const SizedBox(width: 8), Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('/ 100 · ${health['label'] ?? 'Building'}', style: const TextStyle(color: Colors.grey)))]),
            const SizedBox(height: 8), LinearProgressIndicator(value: (((health['score'] as num?)?.toDouble() ?? 0) / 100).clamp(0.0, 1.0)),
            const SizedBox(height: 10),
            ...((health['factors'] as List? ?? []).take(4).map((f) => Padding(padding: const EdgeInsets.only(top: 6), child: Text('• ${f['factor']}: ${f['detail']}', style: const TextStyle(fontSize: 12))))),
            const SizedBox(height: 8), Text(health['disclaimer']?.toString() ?? 'Based on recorded data only.', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]))),
          const SizedBox(height: 20),
          const Text('Month-end expense forecast', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _forecastCard(forecast),
          const SizedBox(height: 20),
          const Text('Unusual transactions', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (anomalies.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(anomalyData['message']?.toString() ?? 'No unusually large transactions detected.')))
          else
            ...anomalies.map((item) => _anomalyCard(item)),
          const SizedBox(height: 8),
          Text('Detection method: ${anomalyData['method'] ?? 'statistical outlier detection'} · ${anomalyData['sample_size'] ?? 0} expenses checked', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 20),
          const Text('Recommended next steps', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (recommendations.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No recommendations yet. Keep tracking transactions to build a more useful picture.')))
          else
            ...recommendations.map((item) => _recommendationCard(item)),
          Card(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(14), child: Text(recommendationData['disclaimer']?.toString() ?? 'Recommendations are based on recorded transactions only.', style: const TextStyle(fontSize: 11, color: Colors.grey)))),
          const SizedBox(height: 20), const Text('Insights', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 8),
          if (insights.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No patterns detected yet. Add more transactions across different dates and categories.'))),
          ...insights.map((item) => _insightCard(item)),
          const SizedBox(height: 12),
          Card(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(14), child: Text(data['disclaimer']?.toString() ?? 'Based on saved transactions only.', style: const TextStyle(fontSize: 12, color: Colors.grey)))),
        ]));
      },
    ),
  );

  Widget _recommendationCard(Map item) {
    final priority = item['priority']?.toString() ?? 'info';
    final color = priority == 'high' ? Colors.red : priority == 'medium' ? Colors.orange : priority == 'low' ? Colors.blue : Colors.grey;
    final potential = (item['potential_saving'] as num?)?.toDouble();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(item['title']?.toString() ?? 'Recommendation', style: const TextStyle(fontWeight: FontWeight.w700))), Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text(priority.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)))]),
      const SizedBox(height: 8), Text(item['reason']?.toString() ?? ''),
      const SizedBox(height: 10), Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber), const SizedBox(width: 8), Expanded(child: Text(item['action']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)))]),
      if (potential != null) ...[const SizedBox(height: 8), Text('Illustrative opportunity: ${money.format(potential)} · ${item['potential_saving_label'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.grey))],
      const SizedBox(height: 8), Text('Based on: ${item['basis'] ?? 'Recorded transactions'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ])));
  }

  Widget _forecastCard(Map<String, dynamic> data) {
    final projected = data['projected_month_end_expenses'];
    final current = (data['current_month_expenses'] as num?)?.toDouble() ?? 0;
    final rate = (data['run_rate_projection'] as num?)?.toDouble() ?? 0;
    final historical = (data['historical_monthly_average'] as num?)?.toDouble();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(projected == null ? 'Not enough history yet' : money.format((projected as num).toDouble()), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4), const Text('Estimated total expenses by month-end', style: TextStyle(color: Colors.grey, fontSize: 12)),
      const Divider(height: 22),
      _amountRow('Spent so far', current, Colors.deepOrange),
      const SizedBox(height: 7), _amountRow('Daily run-rate projection', rate, null),
      if (historical != null) ...[const SizedBox(height: 7), _amountRow('Recent completed-month average', historical, null)],
      const SizedBox(height: 10),
      Text('Method: ${data['method'] ?? 'Baseline estimate'} · Confidence: ${data['confidence'] ?? 'low'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 6), Text(data['disclaimer']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ])));
  }

  Widget _anomalyCard(Map item) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.trending_up, color: Colors.deepOrange), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['title']?.toString() ?? 'Unusual expense', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text('${item['category'] ?? 'Other'} · ${item['date']?.toString().split('T').first ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 5), Text(money.format((item['amount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), if (item['multiple_of_median'] != null) Text('${item['multiple_of_median']}× the median expense', style: const TextStyle(fontSize: 11, color: Colors.grey))]))])));

  Widget _stat(String label, String value) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)), const SizedBox(height: 7), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))])));
  Widget _amountRow(String label, double value, Color? color) => Row(children: [Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))), Text(money.format(value), style: TextStyle(fontWeight: FontWeight.w700, color: color))]);
  Widget _insightCard(Map item) {
    final severity = item['severity']?.toString() ?? 'info';
    final color = severity == 'warning' ? Colors.orange : severity == 'positive' ? Colors.green : Colors.blue;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(severity == 'warning' ? Icons.warning_amber_rounded : severity == 'positive' ? Icons.check_circle_outline : Icons.auto_awesome_outlined, color: color), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['title']?.toString() ?? 'Insight', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text(item['detail']?.toString() ?? '', style: const TextStyle(height: 1.35)), if (item['metric'] is Map && (item['metric'] as Map)['amount'] != null) ...[const SizedBox(height: 6), Text('Amount: ${money.format((item['metric'] as Map)['amount'])}', style: const TextStyle(fontSize: 12, color: Colors.grey))]]))])));
  }
}
