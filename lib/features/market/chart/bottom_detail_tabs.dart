import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_webview_page.dart';
import '../../../l10n/app_localizations.dart';
import '../market_repository.dart';
import 'chart_theme.dart';
import 'indicators_section.dart';
import 'order_book_section.dart';

class BottomDetailTabs extends StatefulWidget {
  const BottomDetailTabs({
    super.key,
    required this.currentPrice,
    this.quote,
    this.symbol,
    this.overlayIndicator = 'none',
    this.subChartIndicator = 'vol',
    this.showPrevCloseLine = true,
    this.onOverlayChanged,
    this.onSubChartChanged,
    this.onShowPrevCloseLineChanged,
    this.klineCandles = const [],
    this.desktopMode = false,
  });

  final double? currentPrice;
  final MarketQuote? quote;
  final String? symbol;
  final String overlayIndicator;
  final String subChartIndicator;
  final bool showPrevCloseLine;
  final ValueChanged<String>? onOverlayChanged;
  final ValueChanged<String>? onSubChartChanged;
  final ValueChanged<bool>? onShowPrevCloseLineChanged;
  final List<ChartCandle> klineCandles;
  final bool desktopMode;

  @override
  State<BottomDetailTabs> createState() => _BottomDetailTabsState();
}

class _BottomDetailTabsState extends State<BottomDetailTabs> {
  int _index = 0;
  Timer? _orderBookTimer;
  List<(double, int)> _bids = [];
  List<(double, int)> _asks = [];
  final _market = MarketRepository();
  bool _loadingCapital = false;
  bool _loadingNews = false;
  bool _loadingAnnouncements = false;
  Map<String, dynamic>? _keyRatios;
  List<Map<String, dynamic>> _dividends = const [];
  List<Map<String, dynamic>> _splits = const [];
  List<MarketNewsItem> _news = const [];
  List<MarketNewsItem> _announcements = const [];

  @override
  void initState() {
    super.initState();
    _loadCapital();
    _loadTickerNews();
    _loadAnnouncements();
  }

  @override
  void didUpdateWidget(covariant BottomDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _stopOrderBookPolling();
      _bids = [];
      _asks = [];
      if (_index == 0 && widget.symbol?.trim().isNotEmpty == true) {
        _startOrderBookPolling();
      }
      _loadCapital();
      _loadTickerNews();
      _loadAnnouncements();
    }
  }

  @override
  void dispose() {
    _stopOrderBookPolling();
    super.dispose();
  }

  List<String> _labels(BuildContext context) => [
        AppLocalizations.of(context)!.chartTabOrderBook,
        AppLocalizations.of(context)!.chartTabIndicator,
        AppLocalizations.of(context)!.chartTabCapital,
        AppLocalizations.of(context)!.chartTabNews,
        AppLocalizations.of(context)!.chartTabAnnouncement,
      ];

  void _startOrderBookPolling() {
    _orderBookTimer?.cancel();
    final symbol = widget.symbol?.trim();
    if (symbol == null || symbol.isEmpty) return;
    Future<void> poll() async {
      try {
        final quote = await _market.getQuote(symbol, realtime: true);
        if (!mounted || _index != 0) return;
        setState(() {
          _bids = quote.bid != null && quote.bid! > 0
              ? [(quote.bid!, quote.bidSize ?? 0)]
              : [];
          _asks = quote.ask != null && quote.ask! > 0
              ? [(quote.ask!, quote.askSize ?? 0)]
              : [];
        });
      } catch (_) {}
    }

    poll();
    _orderBookTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => poll(),
    );
  }

  void _stopOrderBookPolling() {
    _orderBookTimer?.cancel();
    _orderBookTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels(context);
    final outerPadding = widget.desktopMode
        ? const EdgeInsets.only(top: 2)
        : const EdgeInsets.fromLTRB(16, 0, 16, 18);
    return Padding(
      padding: outerPadding,
      child: Container(
        decoration: BoxDecoration(
          color: widget.desktopMode ? Colors.transparent : ChartTheme.cardBackground,
          borderRadius: BorderRadius.circular(widget.desktopMode ? 0 : ChartTheme.radiusCard),
          border: widget.desktopMode ? null : Border.all(color: ChartTheme.border),
          boxShadow: widget.desktopMode ? null : ChartTheme.cardShadow,
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                widget.desktopMode ? 0 : 14,
                widget.desktopMode ? 0 : 14,
                widget.desktopMode ? 0 : 14,
                0,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(labels.length, (index) {
                    final selected = _index == index;
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == labels.length - 1 ? 0 : 8,
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() => _index = index);
                          if (index == 0) {
                            _startOrderBookPolling();
                          } else {
                            _stopOrderBookPolling();
                          }
                        },
                        borderRadius: BorderRadius.circular(widget.desktopMode ? 10 : 999),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.desktopMode ? 12 : 14,
                            vertical: widget.desktopMode ? 8 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? ChartTheme.tabSelectedBg : ChartTheme.surface2,
                            borderRadius: BorderRadius.circular(widget.desktopMode ? 10 : 999),
                            border: Border.all(
                              color: selected ? ChartTheme.accentGold : ChartTheme.borderSubtle,
                            ),
                          ),
                          child: Text(
                            labels[index],
                            style: TextStyle(
                              color: selected
                                  ? ChartTheme.textPrimary
                                  : ChartTheme.textSecondary,
                              fontSize: widget.desktopMode ? 12 : 13,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.desktopMode ? 0 : 14,
                  12,
                  widget.desktopMode ? 0 : 14,
                  widget.desktopMode ? 0 : 14,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _buildContent(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_index) {
      case 0:
        if (_orderBookTimer == null && widget.symbol?.trim().isNotEmpty == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _index == 0) _startOrderBookPolling();
          });
        }
        return SingleChildScrollView(
          key: const ValueKey('order-book'),
          child: OrderBookSection(
            currentPrice: widget.currentPrice,
            quote: widget.quote,
            symbol: widget.symbol,
            bids: _bids,
            asks: _asks,
          ),
        );
      case 1:
        return SingleChildScrollView(
          key: const ValueKey('indicators'),
          child: IndicatorsSection(
            overlayIndicator: widget.overlayIndicator,
            subChartIndicator: widget.subChartIndicator,
            showPrevCloseLine: widget.showPrevCloseLine,
            onOverlayChanged: widget.onOverlayChanged ?? (_) {},
            onSubChartChanged: widget.onSubChartChanged ?? (_) {},
            onShowPrevCloseLineChanged: widget.onShowPrevCloseLineChanged,
            candles: widget.klineCandles,
          ),
        );
      case 2:
        return SingleChildScrollView(
          key: const ValueKey('capital'),
          child: _buildCapitalTab(context),
        );
      case 3:
        return SingleChildScrollView(
          key: const ValueKey('news'),
          child: _buildNewsTab(
            loading: _loadingNews,
            items: _news,
            emptyText: widget.symbol?.trim().isNotEmpty == true
                ? '${widget.symbol} 暂无新闻'
                : '暂无新闻',
          ),
        );
      case 4:
        return SingleChildScrollView(
          key: const ValueKey('announcements'),
          child: _buildNewsTab(
            loading: _loadingAnnouncements,
            items: _announcements,
            emptyText: widget.symbol?.trim().isNotEmpty == true
                ? '${widget.symbol} 暂无公告'
                : '暂无公告',
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _loadCapital() async {
    final symbol = widget.symbol?.trim() ?? '';
    if (symbol.isEmpty) return;
    setState(() => _loadingCapital = true);
    final ratios = await _market.getKeyRatios(symbol);
    final dividends = await _market.getDividends(symbol);
    final splits = await _market.getSplits(symbol);
    if (!mounted) return;
    setState(() {
      _keyRatios = ratios;
      _dividends = dividends;
      _splits = splits;
      _loadingCapital = false;
    });
  }

  Future<void> _loadTickerNews() async {
    final symbol = widget.symbol?.trim() ?? '';
    if (symbol.isEmpty) return;
    setState(() => _loadingNews = true);
    final rows = await _market.getTickerNews(symbol, limit: 20);
    if (!mounted) return;
    setState(() {
      _news = rows;
      _loadingNews = false;
    });
  }

  Future<void> _loadAnnouncements() async {
    final symbol = widget.symbol?.trim() ?? '';
    if (symbol.isEmpty) return;
    setState(() => _loadingAnnouncements = true);
    final rows = await _market.getTickerAnnouncements(symbol, limit: 20);
    if (!mounted) return;
    setState(() {
      _announcements = rows;
      _loadingAnnouncements = false;
    });
  }

  Widget _buildCapitalTab(BuildContext context) {
    if (_loadingCapital) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final hasRatios = _keyRatios != null && _keyRatios!.isNotEmpty;
    final hasActions = _dividends.isNotEmpty || _splits.isNotEmpty;
    if (!hasRatios && !hasActions) {
      return _emptyPanel('暂无资金与财务数据');
    }

    final chips = [
      ('P/E', _numText(_keyRatios?['price_to_earnings'])),
      ('P/B', _numText(_keyRatios?['price_to_book'])),
      ('Div Yield', _percentText(_keyRatios?['dividend_yield'])),
      ('ROE', _percentText(_keyRatios?['return_on_equity'])),
      ('Mkt Cap', _largeNumText(_keyRatios?['market_cap'])),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: chips
              .map(
                (chip) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: ChartTheme.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${chip.$1}: ${chip.$2}',
                    style: const TextStyle(
                      color: ChartTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (_dividends.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionTitle('Dividends'),
          const SizedBox(height: 8),
          ..._dividends.take(3).map(
                (item) => _listRow(
                  '${item['ex_dividend_date'] ?? '-'}',
                  '\$${item['cash_amount'] ?? '-'}',
                ),
              ),
        ],
        if (_splits.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionTitle('Splits'),
          const SizedBox(height: 8),
          ..._splits.take(3).map(
                (item) => _listRow(
                  '${item['execution_date'] ?? '-'}',
                  '${item['split_from'] ?? '-'}:${item['split_to'] ?? '-'}',
                ),
              ),
        ],
      ],
    );
  }

  Widget _buildNewsTab({
    required bool loading,
    required List<MarketNewsItem> items,
    required String emptyText,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (items.isEmpty) {
      return _emptyPanel(emptyText);
    }
    return Column(
      children: items.take(12).map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: ChartTheme.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ChartTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${item.source} · ${_formatTime(item.publishedAt)}',
                style: const TextStyle(
                  color: ChartTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            trailing: const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: ChartTheme.textSecondary,
            ),
            onTap: () => _openNews(item),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: ChartTheme.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _listRow(String left, String right) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: const TextStyle(
                color: ChartTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            right,
            style: const TextStyle(
              color: ChartTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPanel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: ChartTheme.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _openNews(MarketNewsItem item) async {
    await openInAppWebView(
      context,
      url: item.url,
      title: item.title,
    );
  }

  static String _numText(dynamic value) {
    final parsed =
        value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    return parsed == null ? '--' : parsed.toStringAsFixed(2);
  }

  static String _percentText(dynamic value) {
    final parsed =
        value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    return parsed == null ? '--' : '${(parsed * 100).toStringAsFixed(2)}%';
  }

  static String _largeNumText(dynamic value) {
    final parsed =
        value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    if (parsed == null) return '--';
    if (parsed >= 1000000000) return '${(parsed / 1000000000).toStringAsFixed(2)}B';
    if (parsed >= 1000000) return '${(parsed / 1000000).toStringAsFixed(2)}M';
    return parsed.toStringAsFixed(0);
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '--';
    final local = dt.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
