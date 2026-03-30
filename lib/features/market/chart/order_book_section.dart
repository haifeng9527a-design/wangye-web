import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'chart_theme.dart';

class OrderBookSection extends StatelessWidget {
  const OrderBookSection({
    super.key,
    required this.currentPrice,
    this.bids = const [],
    this.asks = const [],
  });

  final double? currentPrice;
  final List<(double, int)> bids;
  final List<(double, int)> asks;

  @override
  Widget build(BuildContext context) {
    final topAsk = asks.isNotEmpty ? asks.first : null;
    final topBid = bids.isNotEmpty ? bids.first : null;
    final spread =
        topAsk != null && topBid != null ? topAsk.$1 - topBid.$1 : null;
    final rows = <({double? askPrice, int? askQty, double? bidPrice, int? bidQty})>[];
    final maxDepth = [asks.length, bids.length].fold<int>(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < maxDepth && i < 5; i++) {
      rows.add((
        askPrice: i < asks.length ? asks[i].$1 : null,
        askQty: i < asks.length ? asks[i].$2 : null,
        bidPrice: i < bids.length ? bids[i].$1 : null,
        bidQty: i < bids.length ? bids[i].$2 : null,
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  label: 'Ask',
                  price: topAsk?.$1,
                  qty: topAsk?.$2,
                  color: ChartTheme.down,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  label: 'Bid',
                  price: topBid?.$1,
                  qty: topBid?.$2,
                  color: ChartTheme.up,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  label: 'Spread',
                  price: spread,
                  qty: null,
                  color: ChartTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _headerRow(context),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ChartTheme.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '当前数据源只提供实时买一卖一，暂未提供更深盘口。',
                style: TextStyle(
                  color: ChartTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...rows.map(_depthRow),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String label,
    required double? price,
    required int? qty,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price != null ? ChartTheme.formatPrice(price) : '—',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            qty != null ? 'Qty $qty' : 'Realtime top level',
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(child: _headerCell(l10n.chartOrderBookSell)),
        Expanded(child: _headerCell(l10n.chartOrderBookQty)),
        Expanded(child: _headerCell(l10n.chartOrderBookBuy)),
        Expanded(child: _headerCell(l10n.chartOrderBookQty)),
      ],
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: ChartTheme.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _depthRow(
    ({double? askPrice, int? askQty, double? bidPrice, int? bidQty}) row,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: ChartTheme.surface2.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _priceCell(row.askPrice, ChartTheme.down)),
          Expanded(child: _qtyCell(row.askQty)),
          Expanded(child: _priceCell(row.bidPrice, ChartTheme.up)),
          Expanded(child: _qtyCell(row.bidQty)),
        ],
      ),
    );
  }

  Widget _priceCell(double? value, Color color) {
    return Text(
      value != null ? ChartTheme.formatPrice(value) : '—',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: value != null ? color : ChartTheme.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: ChartTheme.fontMono,
        fontFeatures: const [ChartTheme.tabularFigures],
      ),
    );
  }

  Widget _qtyCell(int? value) {
    return Text(
      value?.toString() ?? '—',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: ChartTheme.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
