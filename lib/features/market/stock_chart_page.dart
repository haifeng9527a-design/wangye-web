import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/chat_web_socket_service.dart';
import '../../l10n/app_localizations.dart';
import '../trading/trading_cache.dart';
import 'chart/bottom_detail_tabs.dart';
import 'chart/chart_theme.dart';
import 'chart/chart_mode_tabs.dart';
import 'chart/detail_header.dart';
import 'chart/intraday_chart.dart';
import 'chart/stats_bar.dart';
import 'chart/tv_chart_container.dart';
import 'chart_viewport.dart';
import 'chart_viewport_controller.dart';
import 'market_colors.dart';
import 'market_repository.dart';

/// 鑲＄エ璇︽儏椤靛垏鎹㈡椂鐨勫唴瀛樼紦瀛橈紙鏈€杩?5 鍙級锛屽垏鎹㈡椂鍏堝睍绀虹紦瀛樺啀鍚庡彴鍒锋柊
class _StockDetailCache {
  double? currentPrice;
  double? changePercent;
  double? prevClose;
  double? dayOpen;
  double? dayHigh;
  double? dayLow;
  int? dayVolume;
  String? stockName;
  List<ChartCandle> candlesIntraday = [];
  List<ChartCandle> candlesKLine = [];
  String klineInterval = '5min';
}

const int _detailCacheMaxSize = 5;
final Map<String, _StockDetailCache> _stockDetailCache = {};

void _trimDetailCache() {
  if (_stockDetailCache.length > _detailCacheMaxSize) {
    final keys = _stockDetailCache.keys.toList();
    for (var i = 0; i < keys.length - _detailCacheMaxSize; i++) {
      _stockDetailCache.remove(keys[i]);
    }
  }
}

/// 鑲＄エ璇︽儏锛氬疄鏃朵环銆佸巻鍙茶蛋鍔裤€佹垚浜ら噺銆佹垚浜ら銆佸紑楂樹綆鏀讹紙瀵归綈 MOMO 绛夌湅鐩?App锛?
///
/// 鏁版嵁鏉ユ簮锛堣娉ㄩ噴锛夛細
/// - 瀹炴椂浠凤細WebSocket trade锛圥olygon 鎴愪氦娴侊級
/// - 褰撴棩 OHLC + volume锛氫紭鍏?Polygon 鍗曟爣鐨?Snapshot锛?v2/snapshot/.../tickers/{ticker}锛夛紝鍚﹀垯 Polygon aggregates(1, day, today)
/// - 鏄ㄦ敹锛歅olygon getPreviousClose锛?v2/aggs/ticker/prev锛夋垨 Snapshot prevDay
/// - 鑻ユ煇瀛楁鎷夸笉鍒帮紝鏄剧ず "鈥? 涓嶆樉绀?0
class StockChartPage extends StatefulWidget {
  const StockChartPage({
    super.key,
    required this.symbol,
    this.name,
    this.initialSnapshot,
    this.isMockData = false,
    this.symbolList,
    this.symbolIndex,
  });

  final String symbol;
  /// 鑲＄エ鍚嶇О锛堝銆岀壒鏂媺銆嶏級锛屾棤鍒欑敤 symbol
  final String? name;
  /// 浠庤鎯呭垪琛ㄧ偣杩涙椂浼犲叆锛岀敤浜庣珛鍗冲睍绀轰粖寮€/鏈€楂?鏈€浣?鏄ㄦ敹锛屼笉绛夊浘琛?
  final PolygonGainer? initialSnapshot;
  /// 鏄惁涓烘ā鎷熸暟鎹紙鍒楄〃鏃?API 鏃朵紶鍏ワ紝璇︽儏椤甸《閮ㄦ樉绀恒€屾ā鎷熸暟鎹€嶆彁绀猴級
  final bool isMockData;
  /// 鑲＄エ鍒楄〃锛屼紶鍏ュ悗椤舵爮鏄剧ず宸﹀彸绠ご鍙垏鎹㈣偂绁?
  final List<String>? symbolList;
  /// 褰撳墠鍦?symbolList 涓殑绱㈠紩锛屼笉浼犲垯鎸?symbol 鏌ユ壘
  final int? symbolIndex;

  @override
  State<StockChartPage> createState() => _StockChartPageState();
}

class _StockChartPageState extends State<StockChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _market = MarketRepository();

  List<ChartCandle> _candlesIntraday = [];
  List<ChartCandle> _candlesKLine = [];
  /// K 绾胯姹傚け璐ユ椂鐨勯敊璇俊鎭紙渚夸簬鐣岄潰涓婄洿鎺ョ湅鍒板師鍥狅級
  String? _klineLoadError;
  late final ChartViewportController _klineController;
  bool _klineLoadingMore = false;
  int? _lastLoadedEarliestTs;
  bool _chartLoading = true;
  /// 瀹炴椂浠凤紝鏉ユ簮锛歐ebSocket trade
  double? _currentPrice;
  double? _changePercent;
  /// 鏄ㄦ敹锛屾潵婧愶細getPreviousClose / Snapshot prevDay
  double? _prevClose;
  /// 褰撴棩寮€/楂?浣?閲忥紝鏉ユ簮锛歅olygon Snapshot day 鎴?aggregates(1, day, today)
  double? _dayOpen;
  double? _dayHigh;
  double? _dayLow;
  int? _dayVolume;
  /// 褰撴棩绱鎴愪氦閲忥紙WebSocket 鎴愪氦绱姞锛夛紝涓?_dayVolume 浜岄€変竴鎴栧彔鍔犲睍绀?
  int _realtimeVolume = 0;
  StreamSubscription<dynamic>? _realtimeSub;
  /// 鍒嗘椂鍛ㄦ湡锛氫粎 Tab 0锛?鍒嗭級鐢ㄦ姌绾垮浘锛屽浐瀹?1min
  static const String _intradayInterval = '1min';
  /// K绾垮懆鏈燂紙Tab 1-5锛夛細5min/15min/30min/1day/1week|1month|1year
  String _klineInterval = '5min';
  /// 鍛↘ Tab 涓嬫媺閫変腑锛?week | 1month | 1year
  String _extendedKlineInterval = '1week';
  /// 涓诲浘鍙犲姞锛歮a / ema
  String _overlayIndicator = 'none';
  /// 鍓浘锛歷ol / macd / rsi
  String _subChartIndicator = 'vol';
  /// 鏄惁鏄剧ず鏄ㄦ敹浠疯櫄绾匡紙Prev Close锛?
  bool _showPrevCloseLine = true;
  Timer? _quoteTimer;
  Timer? _chartTimer;
  Timer? _autoRetryTimer;
  Map<String, dynamic>? _keyRatios;
  String? _stockName;
  /// 鏈?symbolList 鏃剁敤浜庡師鍦板垏鎹紝閬垮厤 pushReplacement 閲嶅缓椤甸潰
  late String _currentSymbol;
  int _currentIndex = 0;

  String get _effectiveSymbol => widget.symbolList != null ? _currentSymbol : widget.symbol;
  int get _effectiveIndex => widget.symbolList != null ? _currentIndex : _prevNextIndex;

  @override
  void initState() {
    super.initState();
    _currentSymbol = widget.symbol.trim().toUpperCase();
    _currentIndex = _prevNextIndex;
    _tabController = TabController(length: 6, vsync: this, initialIndex: 1);
    _klineController = ChartViewportController(initialVisibleCount: 80, minVisibleCount: 30, maxVisibleCount: 400);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final i = _tabController.index;
      if (i == 0) {
        setState(() {});
        return;
      }
      // Tab 1-5: 5鍒?15鍒?30鍒?鏃/鍛↘(鎴栨湀K/骞碖) 鍧囦负 K 绾垮浘
      final interval = i == 5 ? _extendedKlineInterval : ['5min', '15min', '30min', '1day'][i - 1];
      if (_klineInterval != interval) {
        setState(() {
          _klineInterval = interval;
          _chartLoading = true;
        });
        _loadKLine().then((_) {
          if (mounted) setState(() => _chartLoading = false);
        });
      } else {
        setState(() {});
      }
    });
    final snap = widget.initialSnapshot;
    if (snap != null) {
      _currentPrice = snap.price;
      _prevClose = snap.prevClose;
      _changePercent = snap.todaysChangePerc;
      _dayOpen = snap.dayOpen;
      _dayHigh = snap.dayHigh;
      _dayLow = snap.dayLow;
      _dayVolume = snap.dayVolume;
      setState(() {});
    }
    // 鍏堝嚭浠枫€佸啀鍑哄浘锛氭姤浠蜂紭鍏堝睍绀猴紝鍥捐〃骞惰鍔犺浇锛屼换涓€鏂瑰畬鎴愬嵆鏇存柊 UI锛岄伩鍏嶃€岀偣杩涘幓鍗婂ぉ鐪嬩笉浜嗐€?
    _loadQuote().then((_) {
      if (mounted) setState(() {});
    });
    _loadTodayOHLC();
    _loadIntraday().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(_effectiveSymbol);
      }
    });
    _loadKLine().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(_effectiveSymbol);
      }
    });
    _connectRealtime();
    _startRealtimeTimers();
    _loadKeyRatios();
    if (widget.name == null) _loadStockName();
  }

  /// 鏃犲悕绉版椂閫氳繃鎼滅储鑾峰彇鑲＄エ鍚嶇О锛堝浠庨娑ㄦ杩涘叆璇︽儏椤碉級
  Future<void> _loadStockName() async {
    final sym = _effectiveSymbol.trim().toUpperCase();
    if (sym.isEmpty) return;
    final results = await _market.searchSymbols(sym);
    if (!mounted || results.isEmpty) return;
    MarketSearchResult? match;
    for (final r in results) {
      if (r.symbol.toUpperCase() == sym) {
        match = r;
        break;
      }
    }
    final m = match ?? results.first;
    if (m.name.isNotEmpty && m.name != sym) {
      setState(() => _stockName = m.name);
    }
  }

  void _startRealtimeTimers() {
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _autoRetryTimer?.cancel();
    _quoteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _loadQuote();
    });
    _chartTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadTodayOHLC();
      _loadIntraday();
      _loadKLine();
    });
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_candlesIntraday.isEmpty) _loadIntraday();
      if (_candlesKLine.isEmpty) _loadKLine();
    });
  }

  int get _symbolListLength => widget.symbolList?.length ?? 0;

  int get _prevNextIndex {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return -1;
    if (widget.symbolList != null) return _currentIndex.clamp(0, list.length - 1);
    if (widget.symbolIndex != null) {
      return widget.symbolIndex!.clamp(0, list.length - 1);
    }
    final i = list.indexWhere((s) => s.toUpperCase() == widget.symbol.toUpperCase());
    return i >= 0 ? i : 0;
  }

  void _switchToPrev() {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final i = _effectiveIndex;
    if (i <= 0) return;
    _switchToSymbolInPlace(list[i - 1]);
  }

  void _switchToNext() {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final i = _effectiveIndex;
    if (i >= list.length - 1) return;
    _switchToSymbolInPlace(list[i + 1]);
  }

  /// 鍘熷湴鍒囨崲锛氫笉 pushReplacement锛屽厛灞曠ず缂撳瓨鍐嶅悗鍙板埛鏂帮紝鍒囨崲鏇翠笣婊?
  void _switchToSymbolInPlace(String newSymbol) {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final newSym = newSymbol.trim().toUpperCase();
    final newIndex = list.indexWhere((s) => s.toUpperCase() == newSym);
    if (newIndex < 0) return;

    final oldSym = _currentSymbol;
    _saveToCache(oldSym);

    setState(() {
      _currentSymbol = newSym;
      _currentIndex = newIndex;
      _chartLoading = true;
      _realtimeVolume = 0;
    });

    final cached = _stockDetailCache[newSym];
    if (cached != null) {
      setState(() {
        _currentPrice = cached.currentPrice;
        _changePercent = cached.changePercent;
        _prevClose = cached.prevClose;
        _dayOpen = cached.dayOpen;
        _dayHigh = cached.dayHigh;
        _dayLow = cached.dayLow;
        _dayVolume = cached.dayVolume;
        _stockName = cached.stockName;
        _candlesIntraday = List.from(cached.candlesIntraday);
        _candlesKLine = List.from(cached.candlesKLine);
        _klineInterval = cached.klineInterval;
        _chartLoading = false;
      });
      _klineController.initFromCandlesLength(_candlesKLine.length);
    }

    _realtimeSub?.cancel();
    _realtimeSub = null;
    _connectRealtime();
    _loadQuote().then((_) {
      if (mounted) setState(() {});
    });
    _loadTodayOHLC();
    _loadIntraday().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(newSym);
      }
    });
    _loadKLine().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(newSym);
      }
    });
  }

  void _saveToCache(String sym) {
    if (_candlesIntraday.isEmpty && _candlesKLine.isEmpty) return;
    final c = _StockDetailCache()
      ..currentPrice = _currentPrice
      ..changePercent = _changePercent
      ..prevClose = _prevClose
      ..dayOpen = _dayOpen
      ..dayHigh = _dayHigh
      ..dayLow = _dayLow
      ..dayVolume = _dayVolume
      ..stockName = _stockName
      ..candlesIntraday = List.from(_candlesIntraday)
      ..candlesKLine = List.from(_candlesKLine)
      ..klineInterval = _klineInterval;
    _stockDetailCache[sym] = c;
    _trimDetailCache();
  }

  void _navigateToSymbol(String newSymbol) {
    final list = widget.symbolList;
    if (list != null && list.isNotEmpty) {
      _switchToSymbolInPlace(newSymbol);
      return;
    }
    final newIndex = list != null ? list.indexWhere((s) => s.toUpperCase() == newSymbol.toUpperCase()) : -1;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StockChartPage(
          symbol: newSymbol,
          symbolList: list,
          symbolIndex: newIndex >= 0 ? newIndex : null,
          isMockData: widget.isMockData,
        ),
      ),
    );
  }

  double? _marketCapForPriceSection() {
    final cap = _keyRatios != null && _keyRatios!['market_cap'] != null
        ? (_keyRatios!['market_cap'] as num).toDouble()
        : null;
    if (cap != null && cap > 0) return cap;
    return null;
  }

  double? _turnoverForPriceSection() {
    int? vol;
    if (_realtimeVolume > 0) vol = _realtimeVolume;
    else if (_candlesIntraday.isNotEmpty && _candlesIntraday.any((c) => (c.volume ?? 0) > 0)) {
      vol = _candlesIntraday.fold<int>(0, (s, c) => s + (c.volume ?? 0));
    } else if (_candlesKLine.isNotEmpty && _candlesKLine.last.volume != null && _candlesKLine.last.volume! > 0) {
      vol = _candlesKLine.last.volume;
    }
    if (vol == null || vol <= 0) vol = _dayVolume;
    if (vol == null || vol <= 0) return null;
    final price = _currentPrice ?? _dayOpen ?? _prevClose;
    if (price == null || price <= 0) return null;
    return vol * price;
  }

  double? _bestDisplayPrice() {
    if (_currentPrice != null && _currentPrice! > 0) return _currentPrice;
    if (_candlesIntraday.isNotEmpty) return _candlesIntraday.last.close;
    if (_candlesKLine.isNotEmpty) return _candlesKLine.last.close;
    if (_prevClose != null && _prevClose! > 0) return _prevClose;
    if (_dayOpen != null && _dayOpen! > 0) return _dayOpen;
    return null;
  }

  double? _bestOpen() {
    if (_dayOpen != null && _dayOpen! > 0) return _dayOpen;
    if (_candlesIntraday.isNotEmpty) return _candlesIntraday.first.open;
    if (_candlesKLine.isNotEmpty) return _candlesKLine.last.open;
    return null;
  }

  double? _bestHigh() {
    if (_dayHigh != null && _dayHigh! > 0) return _dayHigh;
    if (_candlesIntraday.isNotEmpty) {
      return _candlesIntraday.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    }
    if (_candlesKLine.isNotEmpty) return _candlesKLine.last.high;
    return null;
  }

  double? _bestLow() {
    if (_dayLow != null && _dayLow! > 0) return _dayLow;
    if (_candlesIntraday.isNotEmpty) {
      return _candlesIntraday.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    }
    if (_candlesKLine.isNotEmpty) return _candlesKLine.last.low;
    return null;
  }

  int? _bestVolume() {
    if (_realtimeVolume > 0) return _realtimeVolume;
    if (_dayVolume != null && _dayVolume! > 0) return _dayVolume;
    if (_candlesIntraday.isNotEmpty && _candlesIntraday.any((c) => (c.volume ?? 0) > 0)) {
      return _candlesIntraday.fold<int>(0, (sum, candle) => sum + (candle.volume ?? 0));
    }
    if (_candlesKLine.isNotEmpty) {
      final vol = _candlesKLine.last.volume;
      if (vol != null && vol > 0) return vol;
    }
    return null;
  }

  double? _bestChangeValue() {
    final price = _bestDisplayPrice();
    final prev = _prevClose;
    if (price == null || prev == null || prev <= 0) return null;
    return price - prev;
  }

  double? _bestChangePercent() {
    if (_changePercent != null) return _changePercent;
    final change = _bestChangeValue();
    final prev = _prevClose;
    if (change == null || prev == null || prev <= 0) return null;
    return change / prev * 100;
  }

  static String _formatVol(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  void _connectRealtime() {
    if (!ChatWebSocketService.instance.isConnected) return;
    _realtimeSub?.cancel();
    ChatWebSocketService.instance.subscribeMarket([_effectiveSymbol]);
    _realtimeSub = ChatWebSocketService.instance.marketQuoteStream.listen((u) {
      if (!mounted || u.symbol != _effectiveSymbol) return;
      setState(() {
        _currentPrice = u.price;
        _realtimeVolume += u.size;
      });
    });
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _autoRetryTimer?.cancel();
    _realtimeSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final quote = await _market.getQuote(_effectiveSymbol, realtime: true);
    final prev = _market.polygonAvailable ? await _market.getPreviousClose(_effectiveSymbol) : null;
    final isMarketOpen = _isRegularUsMarketOpenNow();
    if (!mounted) return;
    setState(() {
      if (!quote.hasError) {
        if (quote.price > 0 && (isMarketOpen || _currentPrice == null || _currentPrice! <= 0)) {
          _currentPrice = quote.price;
        }
        if (quote.changePercent != null && (isMarketOpen || _changePercent == null)) {
          _changePercent = quote.changePercent;
        }
        if (quote.open != null && quote.open! > 0 && (isMarketOpen || _dayOpen == null || _dayOpen! <= 0)) {
          _dayOpen = quote.open;
        }
        if (quote.high != null && quote.high! > 0 && (isMarketOpen || _dayHigh == null || _dayHigh! <= 0)) {
          _dayHigh = quote.high;
        }
        if (quote.low != null && quote.low! > 0 && (isMarketOpen || _dayLow == null || _dayLow! <= 0)) {
          _dayLow = quote.low;
        }
        if (quote.volume != null && quote.volume! > 0 && (isMarketOpen || _dayVolume == null || _dayVolume! <= 0)) {
          _dayVolume = quote.volume;
        }
        if ((_prevClose == null || _prevClose! <= 0) && quote.price > 0 && quote.change != 0) {
          _prevClose = quote.price - quote.change;
        }
        if (quote.name != null && quote.name!.isNotEmpty) _stockName = quote.name;
      }
      if (_prevClose == null || _prevClose! <= 0) _prevClose = prev;
    });
  }

  /// 褰撴棩 OHLC + volume锛氫紭鍏?Polygon Snapshot锛堝崟鏍囩殑 /v2/snapshot/.../tickers/{ticker}锛夛紝
  /// 鍚﹀垯 Polygon aggregates(1, day, today) 鍙栨渶鍚庝竴鏍逛綔涓哄綋鏃?bar
  Future<void> _loadKeyRatios() async {
    final data = await _market.getKeyRatios(_effectiveSymbol);
    if (mounted) setState(() => _keyRatios = data);
  }

  Future<void> _loadTodayOHLC() async {
    if (!_market.polygonAvailable || !_isRegularUsMarketOpenNow()) return;
    final snap = await _market.getDaySnapshot(_effectiveSymbol);
    if (!mounted) return;
    if (snap != null) {
      setState(() {
        if (snap.dayOpen != null && snap.dayOpen! > 0) _dayOpen = snap.dayOpen;
        if (snap.dayHigh != null && snap.dayHigh! > 0) _dayHigh = snap.dayHigh;
        if (snap.dayLow != null && snap.dayLow! > 0) _dayLow = snap.dayLow;
        if (snap.dayVolume != null && snap.dayVolume! > 0) _dayVolume = snap.dayVolume;
        if (_prevClose == null && snap.prevClose != null) _prevClose = snap.prevClose;
      });
      return;
    }
    final toMs = DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final fromMs = todayStart.millisecondsSinceEpoch;
    final list = await _market.getAggregates(
      _effectiveSymbol,
      multiplier: 1,
      timespan: 'day',
      fromMs: fromMs,
      toMs: toMs,
    );
    if (!mounted || list.isEmpty) return;
    final bar = list.last;
    setState(() {
      if (bar.open > 0) _dayOpen = bar.open;
      if (bar.high > 0) _dayHigh = bar.high;
      if (bar.low > 0) _dayLow = bar.low;
      _dayVolume = bar.volume != null && bar.volume! > 0 ? bar.volume : _dayVolume;
    });
  }

  /// 鍒嗘椂鍥撅紙浠?1 鍒嗭級锛氭姌绾垮浘锛屽綋鏃ユ暟鎹?
  Future<void> _loadIntraday() async {
    final sym = _effectiveSymbol.trim().toUpperCase();
    const lastDays = 3;
    const interval = '1min';
    List<ChartCandle> list = [];
    if (_market.useBackend) {
      list = await _market.getCandles(sym, interval, lastDays: lastDays);
    }
    if (list.isEmpty) {
      final toMs = DateTime.now().millisecondsSinceEpoch;
      final fromMs = toMs - lastDays * 24 * 3600 * 1000;
      final cache = TradingCache.instance;
      final cacheKey = 'polygon_aggs_${sym}_1_minute_${fromMs}_$toMs';
      final cached = await cache.getList(cacheKey, maxAge: const Duration(hours: 24));
      if (cached != null && cached.isNotEmpty) {
        for (final r in cached) {
          if (r is Map<String, dynamic>) {
            final bar = PolygonBar.fromJson(r);
            if (bar != null) list.add(ChartCandle.fromBar(bar));
          }
        }
      }
      if (_market.polygonAvailable && list.isEmpty) {
        list = await _market.getAggregates(sym, multiplier: 1, timespan: 'minute', fromMs: fromMs, toMs: toMs);
      }
      if (list.isEmpty && _market.twelveDataAvailable) {
        list = await _market.getCandles(sym, interval, lastDays: lastDays);
      }
    }
    list.sort((a, b) => a.time.compareTo(b.time));
    final preferred = _selectPreferredIntradaySession(list);
    final selectedSessionKey = preferred.isNotEmpty ? _etSessionKey(preferred.last.time) : null;
    final previousSessionClose = selectedSessionKey == null ? null : _previousSessionClose(list, selectedSessionKey);
    final forceSessionValues = !_isRegularUsMarketOpenNow();
    if (!mounted) return;
    setState(() {
      _candlesIntraday = preferred;
      _applyIntradayDerivedMetrics(
        preferred,
        previousClose: previousSessionClose,
        forceSessionValues: forceSessionValues,
      );
    });
  }

  /// Tab 0锛? 鍒嗗垎鏃舵姌绾垮浘
  Widget _buildIntradayTab(double chartHeight, double timeAxisHeight, double volumeHeight) {
    if (_candlesIntraday.isEmpty) {
      return _buildNoDataHint(true, stillLoading: _chartLoading);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: IntradayChart(
            candles: _candlesIntraday,
            prevClose: _prevClose,
            currentPrice: _currentPrice,
            chartHeight: chartHeight,
            timeAxisHeight: timeAxisHeight,
            volumeHeight: volumeHeight,
            periodLabel: '1m',
            useSessionMarketHours: true,
          ),
        ),
      ],
    );
  }

  /// K 绾垮浘锛?鍒?15鍒?30鍒?鏃/鍛↘锛屽潎鐢ㄨ湣鐑涘浘
  Future<void> _loadKLine() async {
    final sym = _effectiveSymbol.trim().toUpperCase();
    final interval = _klineInterval;
    int? lastDays;
    if (interval == '5min') lastDays = 5;
    else if (interval == '15min') lastDays = 10;
    else if (interval == '30min') lastDays = 15;
    List<ChartCandle> list = [];
    if (mounted) setState(() => _klineLoadError = null);

    if (kDebugMode) debugPrint('StockChartPage _loadKLine: symbol=$sym interval=$interval useBackend=${_market.useBackend}');
    if (_market.useBackend) {
      list = await _market.getCandles(
        sym,
        interval,
        lastDays: lastDays,
        onError: (msg) {
          if (mounted) setState(() => _klineLoadError = msg);
        },
      );
    }
    if (list.isEmpty) {
      final toMs = DateTime.now().millisecondsSinceEpoch;
      int fromMs;
      int multiplier = 1;
      String timespan = 'minute';
      if (interval == '5min') {
        fromMs = toMs - 5 * 24 * 3600 * 1000;
        multiplier = 5;
      } else if (interval == '15min') {
        fromMs = toMs - 10 * 24 * 3600 * 1000;
        multiplier = 15;
      } else if (interval == '30min') {
        fromMs = toMs - 15 * 24 * 3600 * 1000;
        multiplier = 30;
      } else if (interval == '1week') {
        fromMs = toMs - 52 * 7 * 24 * 3600 * 1000;
        timespan = 'week';
      } else if (interval == '1month') {
        fromMs = toMs - 24 * 30 * 24 * 3600 * 1000;
        timespan = 'month';
      } else if (interval == '1year') {
        fromMs = toMs - 20 * 365 * 24 * 3600 * 1000;
        timespan = 'year';
      } else {
        fromMs = toMs - 60 * 24 * 3600 * 1000;
        timespan = 'day';
      }
      final cache = TradingCache.instance;
      final cacheKey = 'polygon_aggs_${sym}_${multiplier}_${timespan}_${fromMs}_$toMs';
      final cached = await cache.getList(cacheKey, maxAge: const Duration(hours: 24));
      if (cached != null && cached.isNotEmpty) {
        for (final r in cached) {
          if (r is Map<String, dynamic>) {
            final bar = PolygonBar.fromJson(r);
            if (bar != null) list.add(ChartCandle.fromBar(bar));
          }
        }
      }
      if (list.isEmpty && _market.polygonAvailable) {
        list = await _market.getAggregates(sym, multiplier: multiplier, timespan: timespan, fromMs: fromMs, toMs: toMs);
      }
      if (list.isEmpty && _market.twelveDataAvailable) {
        list = await _market.getCandles(sym, interval, lastDays: lastDays);
      }
    }
    if (list.isEmpty) {
      debugPrint('StockChartPage: K绾挎棤鏁版嵁 symbol=$sym interval=$interval');
      if (_market.useBackend && kDebugMode) {
        debugPrint('  Backend-first mode enabled. Confirm backend is running and TONGXIN_API_URL is reachable.');
      }
    }
    if (mounted) {
      setState(() {
        _candlesKLine = list;
        _klineController.initFromCandlesLength(list.length);
      });
      if (_isKlineIntervalDayOrWeek()) _scheduleBackfillKLineTo20Years();
    }
  }

  bool _isKlineIntervalDayOrWeek() =>
      _klineInterval == '1day' || _klineInterval == '1week' || _klineInterval == '1month' || _klineInterval == '1year';

  /// 杩?20 骞?K 绾跨洰鏍囷細棣栧睆鏄剧ず鍚庢寔缁湪鍚庡彴琛ュ叏鏇存棭鏁版嵁锛岀洿鍒扮害 20 骞存垨鎺ュ彛鏃犳洿澶氭暟鎹?
  static final int _kline20YearsMs = (20 * 365.25 * 24 * 3600 * 1000).round();

  void _scheduleBackfillKLineTo20Years() {
    if (!_isKlineIntervalDayOrWeek()) return;
    if (_candlesKLine.isEmpty || _klineLoadingMore) return;
    final oldestMs = (_candlesKLine.first.time * 1000).round();
    final twentyYearsAgo = DateTime.now().millisecondsSinceEpoch - _kline20YearsMs;
    if (oldestMs <= twentyYearsAgo) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _klineLoadingMore) return;
      if (_candlesKLine.isEmpty) return;
      final earliest = (_candlesKLine.first.time * 1000).round();
      _loadKLineHistory(earliest).then((_) {
        if (mounted && _candlesKLine.isNotEmpty) _scheduleBackfillKLineTo20Years();
      });
    });
  }

  String _klineIntervalForLoadMore() => _klineInterval;

  /// 浼犵粰鍥捐〃鐨?K 绾垮垪琛細鍦ㄣ€屾渶鏂般€嶈鍙ｄ笖鏈夊疄鏃朵环鏃讹紝鏈€鍚庝竴鏍圭敤瀹炴椂浠锋洿鏂?high/low/close锛屼娇鏈€鍚庝竴鏍归殢琛屾儏娉㈠姩
  List<ChartCandle> get _kLineDisplayCandles {
    if (_candlesKLine.isEmpty) return _candlesKLine;
    final price = _currentPrice;
    if (price == null || price <= 0) return _candlesKLine;
    if (!_klineController.isAtRealtime(_candlesKLine.length)) return _candlesKLine;
    final last = _candlesKLine.last;
    final high = (last.high > price ? last.high : price).toDouble();
    final low = (last.low < price ? last.low : price).toDouble();
    final merged = ChartCandle(
      time: last.time,
      open: last.open,
      high: high,
      low: low,
      close: price,
      volume: _dayVolume ?? (_realtimeVolume > 0 ? _realtimeVolume : last.volume),
    );
    return [..._candlesKLine.sublist(0, _candlesKLine.length - 1), merged];
  }

  Future<void> _loadKLineHistory(int earliestTimestampMs) async {
    if (_klineLoadingMore) return;
    if (_lastLoadedEarliestTs != null && earliestTimestampMs >= _lastLoadedEarliestTs!) return;
    setState(() => _klineLoadingMore = true);
    try {
      final beforeLen = _candlesKLine.length;
      final earliestTsBefore = beforeLen > 0 ? (_candlesKLine.first.time * 1000).round() : null;
      final list = await _market.getCandlesOlderThan(
        _effectiveSymbol,
        _klineIntervalForLoadMore(),
        olderThanMs: earliestTimestampMs,
        limit: 500,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        final merged = MarketRepository.mergeAndDedupeCandles(list, _candlesKLine);
        final afterLen = merged.length;
        final newCandlesLen = afterLen - beforeLen;
        final earliestTsAfter = afterLen > 0 ? (merged.first.time * 1000).round() : null;
        if (kDebugMode) {
          debugPrint('[KLine loadMore] beforeLen=$beforeLen afterLen=$afterLen earliestTsBefore=$earliestTsBefore earliestTsAfter=$earliestTsAfter newCandlesLen=$newCandlesLen');
        }
        setState(() {
          _candlesKLine = merged;
          _klineController.addStartOffset(newCandlesLen);
          _lastLoadedEarliestTs = earliestTimestampMs;
        });
        _scheduleBackfillKLineTo20Years();
      }
    } finally {
      if (mounted) setState(() => _klineLoadingMore = false);
    }
  }

  static const double _chartMinHeight = 320.0;
  /// TvChartContainer 涓婁笅鍐呰竟璺濓紙缂╁皬浠ュ澶у浘琛ㄥ彲瑙嗗尯鍩燂級
  static const double _chartContainerPaddingV = 12.0;
  /// 鍒嗘椂鍥惧唴閮?Padding 鍗犵敤鐨勫瀭鐩寸┖闂?
  static const double _intradayChartPaddingV = 10.0;
  /// 鍒嗘椂鍥句笂鏂规憳瑕佽鍗犵敤鐨勯珮搴?
  static const double _intradaySummaryRowHeight = 44.0;
  /// K 绾胯鍙ｉ澶栧崰鐢紙缂╁皬浠ヨ涓诲浘+鎴愪氦閲忓崰婊″彲鐢ㄩ珮搴︼級
  static const double _klineViewportExtraV = 24.0;
  /// 鍒嗘椂锛氫富鍥惧崰姣旀彁楂橈紝鏀惧ぇ涓诲浘渚夸簬鐪嬫竻
  static const double _ratioChart = 250 / 320;
  static const double _ratioVolume = 48 / 320;
  static const double _ratioTimeAxis = 22 / 320;
  /// K 绾匡細涓诲浘 92%銆佹垚浜ら噺 8%锛屾椂闂磋酱鑷冲皯 28px 纭繚搴曢儴鏃ユ湡瀹屾暣鏄剧ず
  static const double _ratioTimeAxisK = 28 / 376;
  static const double _ratioChartK = 0.92 * (1 - _ratioTimeAxisK);
  static const double _ratioVolumeK = 0.08 * (1 - _ratioTimeAxisK);
  static const double _ratioIntradayVolume = 48 / 320;

  @override
  Widget build(BuildContext context) {
    final displayPrice = _bestDisplayPrice();
    final changeVal = _bestChangeValue();
    final changePercent = _bestChangePercent();
    final statusLabel = _statusLabel(context);
    return Scaffold(
      backgroundColor: ChartTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenH = MediaQuery.sizeOf(context).height;
            final isDesktop = constraints.maxWidth >= 1180;
            final fixedChartHeight = isDesktop
                ? (screenH - 150).clamp(520.0, 760.0)
                : (screenH * 0.56).clamp(420.0, 640.0);
            final detailPanelHeight = fixedChartHeight;
            final availableHeight = fixedChartHeight - _chartContainerPaddingV - _intradayChartPaddingV - 8;
            final contentHeight = availableHeight.clamp(160.0, double.infinity);
            final contentHeightIntraday = contentHeight.clamp(180.0, double.infinity);
            final contentHeightKline = (availableHeight - _klineViewportExtraV).clamp(200.0, double.infinity);
            final chartHeight = contentHeightKline * _ratioChartK;
            final volumeHeight = contentHeightKline * _ratioVolumeK;
            final timeAxisHeight = contentHeightKline * _ratioTimeAxisK;
            final chartHeightIntraday = contentHeightIntraday * _ratioChart;
            final timeAxisHeightIntraday = contentHeightIntraday * _ratioTimeAxis;
            final intradayVolumeHeight = contentHeightIntraday * _ratioIntradayVolume;

            Widget chartContent;
            if (_chartLoading) {
              chartContent = Center(
                child: Text(AppLocalizations.of(context)!.chartLoading, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 13)),
              );
            } else if (_candlesIntraday.isEmpty && _candlesKLine.isEmpty) {
              chartContent = _buildEmptyStateCard();
            } else {
              chartContent = TabBarView(
                controller: _tabController,
                children: [
                  _buildIntradayTab(chartHeightIntraday, timeAxisHeightIntraday, intradayVolumeHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                ],
              );
            }

            final pageBody = DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF111B26),
                    ChartTheme.background,
                    ChartTheme.background,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: isDesktop
                  ? SizedBox(
                      height: constraints.maxHeight,
                      child: Column(
                        children: [
                          DetailHeader(
                            symbol: _effectiveSymbol,
                            name: widget.name ?? _stockName,
                            onBack: () => Navigator.of(context).maybePop(),
                            onPrev: _prevNextIndex > 0 ? _switchToPrev : null,
                            onNext: _prevNextIndex >= 0 && _prevNextIndex < _symbolListLength - 1 ? _switchToNext : null,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildMainChartPanel(
                                      context,
                                      chartContent: chartContent,
                                      chartHeight: fixedChartHeight,
                                      displayPrice: displayPrice,
                                      changeVal: changeVal,
                                      changePercent: changePercent,
                                      statusLabel: statusLabel,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  SizedBox(
                                    width: constraints.maxWidth >= 1500 ? 360 : 340,
                                    child: _buildRightQuotePanel(
                                      displayPrice: displayPrice,
                                      changeVal: changeVal,
                                      changePercent: changePercent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          children: [
                            DetailHeader(
                              symbol: _effectiveSymbol,
                              name: widget.name ?? _stockName,
                              onBack: () => Navigator.of(context).maybePop(),
                              onPrev: _prevNextIndex > 0 ? _switchToPrev : null,
                              onNext: _prevNextIndex >= 0 && _prevNextIndex < _symbolListLength - 1 ? _switchToNext : null,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  _infoChip(
                                    statusLabel ?? 'US Market',
                                    tone: ChartTheme.up,
                                  ),
                                  const SizedBox(width: 8),
                                  _infoChip(
                                    'Symbol ${_effectiveSymbol}',
                                    tone: ChartTheme.accentGold,
                                  ),
                                  if (widget.isMockData) ...[
                                    const SizedBox(width: 8),
                                    _infoChip('Mock Data', tone: ChartTheme.down),
                                  ],
                                ],
                              ),
                            ),
                            ChartModeTabs(
                              tabIndex: _tabController.index,
                              onTabChanged: (i) => _tabController.animateTo(i),
                              isIntraday: _tabController.index == 0,
                              intradayPeriod: _intradayInterval,
                              klineTimespan: _klineInterval == '1day' ? 'day' : _klineInterval == '1week' ? 'week' : _klineInterval == '1month' ? 'month' : _klineInterval == '1year' ? 'year' : _klineInterval,
                              onIntradayPeriodChanged: (_) {},
                              onKlineTimespanChanged: (_) {},
                              extendedKlineInterval: _extendedKlineInterval,
                              onExtendedKlineChanged: (v) {
                                if (_extendedKlineInterval != v) {
                                  setState(() {
                                    _extendedKlineInterval = v;
                                    _klineInterval = v;
                                    _chartLoading = true;
                                  });
                                  _loadKLine().then((_) {
                                    if (mounted) setState(() => _chartLoading = false);
                                  });
                                }
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: ChartTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
                                  border: Border.all(color: ChartTheme.border),
                                  boxShadow: ChartTheme.cardShadow,
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                                      child: _buildStatsBar(),
                                    ),
                                    TvChartContainer(
                                      edgeToEdge: true,
                                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                                      child: SizedBox(
                                        height: fixedChartHeight,
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(
                                            bottom: Radius.circular(18),
                                          ),
                                          child: chartContent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              height: detailPanelHeight,
                              child: BottomDetailTabs(
                                symbol: _effectiveSymbol,
                                currentPrice: _currentPrice,
                                overlayIndicator: _overlayIndicator,
                                subChartIndicator: _subChartIndicator,
                                showPrevCloseLine: _showPrevCloseLine,
                                desktopMode: false,
                                onOverlayChanged: (v) => setState(() => _overlayIndicator = v),
                                onSubChartChanged: (v) => setState(() => _subChartIndicator = v),
                                onShowPrevCloseLineChanged: (v) => setState(() => _showPrevCloseLine = v),
                                klineCandles: _candlesKLine,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            );

            return pageBody;
          },
        ),
      ),
    );
  }

  /// 缇庤偂浜ゆ槗鏃舵鎸夌編涓滄椂闂达細9:30鈥?6:00锛圗ST/EDT锛?
  String? _statusLabel(BuildContext context) {
    final (hour, minute) = _usEasternHourMinute();
    final l10n = AppLocalizations.of(context)!;
    if (hour < 9 || (hour == 9 && minute < 30)) return l10n.chartPreMarket;
    if (hour > 16 || (hour == 16 && minute > 0)) return l10n.chartClosed;
    return l10n.chartIntraday;
  }

  /// 褰撳墠缇庝笢鏃堕棿锛堝皬鏃躲€佸垎锛夛紝杩戜技 EST/EDT锛? 鏈堢 2 涓懆鏃モ€?1 鏈堢 1 涓懆鏃ヤ负 EDT锛?
  static (int hour, int minute) _usEasternHourMinute() {
    final utc = DateTime.now().toUtc();
    final isEDT = _isUsEasternDST(utc);
    final offsetHours = isEDT ? 4 : 5;
    final eastern = utc.subtract(Duration(hours: offsetHours));
    return (eastern.hour, eastern.minute);
  }

  static bool _isUsEasternDST(DateTime utc) {
    final y = utc.year;
    final marchSecondSun = _nthSundayOfMonth(y, 3, 2);
    final novFirstSun = _nthSundayOfMonth(y, 11, 1);
    final at = DateTime.utc(y, utc.month, utc.day);
    return !at.isBefore(marchSecondSun) && at.isBefore(novFirstSun);
  }

  static DateTime _nthSundayOfMonth(int year, int month, int n) {
    var d = DateTime.utc(year, month, 1);
    var count = 0;
    while (d.month == month) {
      if (d.weekday == DateTime.sunday) {
        count++;
        if (count == n) return d;
      }
      d = d.add(const Duration(days: 1));
    }
    return DateTime.utc(year, month, 1);
  }

  static DateTime _toUsEastern(DateTime utc) {
    final isEDT = _isUsEasternDST(utc.toUtc());
    final offsetHours = isEDT ? 4 : 5;
    return utc.toUtc().subtract(Duration(hours: offsetHours));
  }

  static bool _isRegularUsMarketOpenNow() {
    final nowEt = _toUsEastern(DateTime.now().toUtc());
    if (nowEt.weekday == DateTime.saturday || nowEt.weekday == DateTime.sunday) {
      return false;
    }
    final minutes = nowEt.hour * 60 + nowEt.minute;
    return minutes >= (9 * 60 + 30) && minutes <= (16 * 60);
  }

  static int _etSessionKey(double timeSec) {
    final et = _toUsEastern(
      DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).round(), isUtc: true),
    );
    return et.year * 10000 + et.month * 100 + et.day;
  }

  List<ChartCandle> _selectPreferredIntradaySession(List<ChartCandle> source) {
    if (source.isEmpty) return source;
    final groups = <int, List<ChartCandle>>{};
    for (final candle in source) {
      groups.putIfAbsent(_etSessionKey(candle.time), () => <ChartCandle>[]).add(candle);
    }
    final sessionKeys = groups.keys.toList()..sort();
    if (sessionKeys.isEmpty) return source;
    final nowOpen = _isRegularUsMarketOpenNow();
    final todayKey = _etSessionKey(DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0);
    if (nowOpen && groups.containsKey(todayKey) && groups[todayKey]!.isNotEmpty) {
      return groups[todayKey]!..sort((a, b) => a.time.compareTo(b.time));
    }
    for (var i = sessionKeys.length - 1; i >= 0; i--) {
      final key = sessionKeys[i];
      if (key == todayKey) continue;
      final session = groups[key];
      if (session != null && session.isNotEmpty) {
        session.sort((a, b) => a.time.compareTo(b.time));
        return session;
      }
    }
    final fallback = groups[sessionKeys.last]!;
    fallback.sort((a, b) => a.time.compareTo(b.time));
    return fallback;
  }

  double? _previousSessionClose(List<ChartCandle> source, int selectedSessionKey) {
    final groups = <int, List<ChartCandle>>{};
    for (final candle in source) {
      groups.putIfAbsent(_etSessionKey(candle.time), () => <ChartCandle>[]).add(candle);
    }
    final keys = groups.keys.toList()..sort();
    final selectedIndex = keys.indexOf(selectedSessionKey);
    if (selectedIndex <= 0) return null;
    for (var i = selectedIndex - 1; i >= 0; i--) {
      final session = groups[keys[i]];
      if (session == null || session.isEmpty) continue;
      session.sort((a, b) => a.time.compareTo(b.time));
      final close = session.last.close;
      if (close > 0) return close;
    }
    return null;
  }

  void _applyIntradayDerivedMetrics(
    List<ChartCandle> candles, {
    double? previousClose,
    bool forceSessionValues = false,
  }) {
    if (candles.isEmpty) return;
    final first = candles.first;
    final last = candles.last;
    final high = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final low = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final totalVolume = candles.fold<int>(0, (sum, candle) => sum + (candle.volume ?? 0));
    if (forceSessionValues || _dayOpen == null || _dayOpen! <= 0) {
      _dayOpen = first.open > 0 ? first.open : _dayOpen;
    }
    if (forceSessionValues || _dayHigh == null || _dayHigh! <= 0) {
      _dayHigh = high > 0 ? high : _dayHigh;
    }
    if (forceSessionValues || _dayLow == null || _dayLow! <= 0) {
      _dayLow = low > 0 ? low : _dayLow;
    }
    if (totalVolume > 0 && (forceSessionValues || _dayVolume == null || _dayVolume! <= 0)) {
      _dayVolume = totalVolume;
    }
    if ((forceSessionValues || _currentPrice == null || _currentPrice! <= 0) && last.close > 0) {
      _currentPrice = last.close;
    }
    if (forceSessionValues || _prevClose == null || _prevClose! <= 0) {
      _prevClose = previousClose != null && previousClose > 0
          ? previousClose
          : (first.open > 0 ? first.open : _prevClose);
    }
    if (_prevClose != null && _prevClose! > 0 && _currentPrice != null && _currentPrice! > 0) {
      _changePercent = ((_currentPrice! - _prevClose!) / _prevClose!) * 100;
    }
  }

  Widget _infoChip(String label, {required Color tone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMainChartPanel(
    BuildContext context, {
    required Widget chartContent,
    required double chartHeight,
    required double? displayPrice,
    required double? changeVal,
    required double? changePercent,
    required String? statusLabel,
  }) {
    final tone =
        changeVal == null || changeVal >= 0 ? ChartTheme.up : ChartTheme.down;
    final bodyHeight = (chartHeight - 144).clamp(360.0, 640.0);
    final desktopMetrics = [
      ('Open', _formatRightMetric(_bestOpen())),
      ('High', _formatRightMetric(_bestHigh())),
      ('Low', _formatRightMetric(_bestLow())),
      ('Prev Close', _formatRightMetric(_prevClose)),
      ('Volume', _formatCompactVolume(_bestVolume())),
      ('Turnover', _formatRightLarge(_turnoverForPriceSection())),
    ];
    return SizedBox(
      height: chartHeight,
      child: Container(
        decoration: BoxDecoration(
          color: ChartTheme.cardBackground,
          borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
          border: Border.all(color: ChartTheme.border),
          boxShadow: ChartTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _effectiveSymbol,
                              style: const TextStyle(
                                color: ChartTheme.textPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                fontFamily: ChartTheme.fontMono,
                                fontFeatures: [ChartTheme.tabularFigures],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _infoChip(statusLabel ?? 'US Market', tone: tone),
                            const SizedBox(width: 8),
                            _infoChip('US', tone: ChartTheme.accentGold),
                            if (widget.isMockData) ...[
                              const SizedBox(width: 8),
                              _infoChip('Mock', tone: ChartTheme.down),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.name ?? _stockName ?? _effectiveSymbol,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ChartTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              displayPrice != null
                                  ? ChartTheme.formatPrice(displayPrice)
                                  : '—',
                              style: TextStyle(
                                color: tone,
                                fontSize: 46,
                                height: 0.95,
                                fontWeight: FontWeight.w800,
                                fontFamily: ChartTheme.fontMono,
                                fontFeatures: const [ChartTheme.tabularFigures],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _signedMetric(changeVal),
                                    style: TextStyle(
                                      color: tone,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: ChartTheme.fontMono,
                                      fontFeatures: const [ChartTheme.tabularFigures],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _signedPercentMetric(changePercent),
                                    style: TextStyle(
                                      color: tone,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: ChartTheme.fontMono,
                                      fontFeatures: const [ChartTheme.tabularFigures],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        for (var i = 0; i < desktopMetrics.length; i += 2)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i == desktopMetrics.length - 2 ? 0 : 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _desktopMetricTableCell(
                                    desktopMetrics[i].$1,
                                    desktopMetrics[i].$2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _desktopMetricTableCell(
                                    desktopMetrics[i + 1].$1,
                                    desktopMetrics[i + 1].$2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: ChartTheme.borderSubtle,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: _buildDesktopToolbar(),
            ),
            Expanded(
              child: TvChartContainer(
                edgeToEdge: true,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                child: SizedBox(
                  height: bodyHeight,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                    child: chartContent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightQuotePanel({
    required double? displayPrice,
    required double? changeVal,
    required double? changePercent,
  }) {
    final tone = changeVal == null || changeVal >= 0 ? ChartTheme.up : ChartTheme.down;
    final metrics = [
      ('Change', _signedMetric(changeVal)),
      ('Change %', _signedPercentMetric(changePercent)),
      ('Open', _formatRightMetric(_bestOpen())),
      ('High', _formatRightMetric(_bestHigh())),
      ('Low', _formatRightMetric(_bestLow())),
      ('Prev Close', _formatRightMetric(_prevClose)),
      ('Volume', _formatCompactVolume(_bestVolume())),
      ('Turnover', _formatRightLarge(_turnoverForPriceSection())),
    ];
    return Container(
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
        border: Border.all(color: ChartTheme.border),
        boxShadow: ChartTheme.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _effectiveSymbol,
              style: const TextStyle(
                color: ChartTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                fontFamily: ChartTheme.fontMono,
                fontFeatures: [ChartTheme.tabularFigures],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.name ?? _stockName ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ChartTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    displayPrice != null
                        ? ChartTheme.formatPrice(displayPrice)
                        : '—',
                    style: TextStyle(
                      color: tone,
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      fontFamily: ChartTheme.fontMono,
                      fontFeatures: const [ChartTheme.tabularFigures],
                    ),
                  ),
                ),
                Text(
                  '${_signedMetric(changeVal)}  ${_signedPercentMetric(changePercent)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: tone,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: ChartTheme.fontMono,
                    fontFeatures: const [ChartTheme.tabularFigures],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: ChartTheme.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ChartTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Snapshot',
                    style: TextStyle(
                      color: ChartTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < metrics.length; i++)
                    _sidebarMetricRow(
                      metrics[i].$1,
                      metrics[i].$2,
                      emphasize: i < 2,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: BottomDetailTabs(
                symbol: _effectiveSymbol,
                currentPrice: _currentPrice,
                overlayIndicator: _overlayIndicator,
                subChartIndicator: _subChartIndicator,
                showPrevCloseLine: _showPrevCloseLine,
                desktopMode: true,
                onOverlayChanged: (v) => setState(() => _overlayIndicator = v),
                onSubChartChanged: (v) => setState(() => _subChartIndicator = v),
                onShowPrevCloseLineChanged: (v) =>
                    setState(() => _showPrevCloseLine = v),
                klineCandles: _candlesKLine,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopMetricTableCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: ChartTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: ChartTheme.fontMono,
                fontFeatures: [ChartTheme.tabularFigures],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarMetricRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: ChartTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? ChartTheme.up : ChartTheme.textPrimary,
              fontSize: emphasize ? 15 : 13,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopToolbar() {
    final labels = ['1分', '5分', '15分', '30分', '日K', _extendedKlineLabel()];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          _desktopTabButton(
            labels[i],
            selected: _tabController.index == i,
            onTap: () => _tabController.animateTo(i),
          ),
          if (i != labels.length - 1) const SizedBox(width: 8),
        ],
        const Spacer(),
        _desktopToolChip(
          _overlayIndicator == 'none' ? '主图: 关闭' : '主图: ${_overlayIndicator.toUpperCase()}',
        ),
        const SizedBox(width: 8),
        _desktopToolChip(
          _subChartIndicator == 'vol' ? '副图: VOL' : '副图: ${_subChartIndicator.toUpperCase()}',
        ),
        const SizedBox(width: 8),
        _desktopToolChip(_showPrevCloseLine ? '昨收线' : '隐藏昨收'),
      ],
    );
  }

  Widget _desktopTabButton(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? ChartTheme.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? ChartTheme.accentGold : ChartTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _desktopToolChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ChartTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _extendedKlineLabel() {
    switch (_extendedKlineInterval) {
      case '1month':
        return '月K';
      case '1year':
        return '年K';
      default:
        return '周K';
    }
  }

  String _formatRightMetric(double? value) =>
      value != null && value > 0 ? ChartTheme.formatPrice(value) : '—';

  String _formatCompactVolume(int? vol) {
    if (vol == null || vol <= 0) return '—';
    if (vol >= 1000000000) return '${(vol / 1000000000).toStringAsFixed(2)}B';
    if (vol >= 1000000) return '${(vol / 1000000).toStringAsFixed(2)}M';
    if (vol >= 1000) return '${(vol / 1000).toStringAsFixed(2)}K';
    return '$vol';
  }

  String _formatRightVolume() {
    return _formatCompactVolume(_bestVolume());
  }


  String _formatRightLarge(double? value) {
    if (value == null || value <= 0) return '—';
    if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(2)}B';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
    return value.toStringAsFixed(0);
  }
  String _signedMetric(double? value) {
    if (value == null) return '—';
    return '${value >= 0 ? '+' : ''}${ChartTheme.formatPrice(value)}';
  }

  String _signedPercentMetric(double? value) {
    if (value == null) return '—';
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
  }

  Widget _buildStatsBar() {
    double? open;
    double? high;
    double? low;
    double? close;
    if (_candlesIntraday.isNotEmpty) {
      open = _candlesIntraday.first.open;
      high = _candlesIntraday.map((c) => c.high).reduce((a, b) => a > b ? a : b);
      low = _candlesIntraday.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      close = _candlesIntraday.last.close;
    } else if (_candlesKLine.isNotEmpty) {
      final last = _candlesKLine.last;
      open = last.open;
      high = last.high;
      low = last.low;
      close = last.close;
    }
    open ??= _dayOpen;
    high ??= _dayHigh;
    low ??= _dayLow;
    final displayClose = _currentPrice ?? close;
    final change = (displayClose != null && _prevClose != null && _prevClose! > 0)
        ? displayClose - _prevClose!
        : null;
    int? vol;
    if (_realtimeVolume > 0) vol = _realtimeVolume;
    else if (_candlesIntraday.isNotEmpty && _candlesIntraday.any((c) => (c.volume ?? 0) > 0)) {
      vol = _candlesIntraday.fold<int>(0, (s, c) => s + (c.volume ?? 0));
    } else if (_candlesKLine.isNotEmpty && _candlesKLine.last.volume != null && _candlesKLine.last.volume! > 0) {
      vol = _candlesKLine.last.volume;
    }
    if (vol == null || vol <= 0) vol = _dayVolume;
    if (vol != null && vol <= 0) vol = null;
    final priceForTurnover = (displayClose != null && displayClose > 0) ? displayClose : (open != null && open! > 0 ? open : _prevClose);
    final turnover = (vol != null && vol > 0 && priceForTurnover != null && priceForTurnover > 0)
        ? vol * priceForTurnover
        : null;
    final prev = (_prevClose != null && _prevClose! > 0) ? _prevClose! : 0.0;
    final amplitude = (high != null && low != null && prev > 0)
        ? (high! - low!) / prev * 100
        : null;
    final avgPrice = (high != null && low != null && displayClose != null)
        ? (high! + low! + displayClose) / 3
        : null;
    return ChartStatsBar(
      symbol: _effectiveSymbol,
      currentPrice: displayClose,
      change: change,
      changePercent: _changePercent,
      open: open,
      high: high,
      low: low,
      close: displayClose,
      prevClose: _prevClose,
      amplitude: amplitude,
      avgPrice: avgPrice,
      volume: vol,
      turnover: turnover,
      turnoverRate: null,
      dividendYieldPercent: _keyRatios != null && _keyRatios!['dividend_yield'] != null
          ? (_keyRatios!['dividend_yield'] as num).toDouble() * 100
          : null,
      peTtm: _keyRatios != null && _keyRatios!['price_to_earnings'] != null
          ? (_keyRatios!['price_to_earnings'] as num).toDouble()
          : null,
    );
  }

  Widget _buildKlineTab(double chartHeight, double volumeHeight, double timeAxisHeight) {
    if (_candlesKLine.isEmpty) {
      return _buildNoDataHint(false, stillLoading: _chartLoading, klineError: _klineLoadError, onRetry: () {
        setState(() => _chartLoading = true);
        _loadKLine().then((_) { if (mounted) setState(() => _chartLoading = false); });
      });
    }
    return Stack(
      children: [
        ChartViewport(
          controller: _klineController,
          candles: _kLineDisplayCandles,
          onLoadMoreHistory: _loadKLineHistory,
          isLoadingMore: _klineLoadingMore,
          chartHeight: chartHeight,
          volumeHeight: volumeHeight,
          timeAxisHeight: timeAxisHeight,
          overlayIndicator: _overlayIndicator,
          subChartIndicator: _subChartIndicator,
          prevClose: _showPrevCloseLine ? _prevClose : null,
          currentPrice: _showPrevCloseLine ? _currentPrice : null,
        ),
        ListenableBuilder(
          listenable: _klineController,
          builder: (_, __) {
            final atRealtime = _klineController.isAtRealtime(_candlesKLine.length);
            if (atRealtime) return const SizedBox.shrink();
            return Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: ChartTheme.cardBackground,
                borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                child: InkWell(
                  onTap: () => _klineController.goToRealtime(_candlesKLine.length),
                  borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(AppLocalizations.of(context)!.chartBackToLatest, style: TextStyle(color: ChartTheme.accentGold, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMockBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ChartTheme.accentGold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChartTheme.accentGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: ChartTheme.accentGold),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.chartMockDataHint, style: TextStyle(color: ChartTheme.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }


  /// 鍒嗘椂/K绾垮崟涓€涓虹┖鏃讹細鍔犺浇涓垨鏆傛棤鏁版嵁+閲嶈瘯
  Widget _buildNoDataHint(bool? isIntraday, {bool stillLoading = true, String? klineError, VoidCallback? onRetry}) {
    final l10n = AppLocalizations.of(context)!;
    final label = isIntraday == false ? l10n.chartKlineLabel : isIntraday == true ? l10n.chartTimeshareLabel : l10n.chartTimeshareLabel;
    final isIntradayEmpty = isIntraday == true && !stillLoading;
    final isKlineEmpty = isIntraday == false && !stillLoading;
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stillLoading) SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: ChartTheme.accentGold)),
            if (stillLoading) const SizedBox(height: 12),
            Text(
              isIntradayEmpty ? l10n.chartNoIntradayData : (isKlineEmpty ? l10n.chartNoKlineData : l10n.chartFetchingWithLabel(label)),
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            if (stillLoading) const SizedBox(height: 4),
            if (stillLoading) Text(l10n.chartQuoteRefreshHint, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 11), textAlign: TextAlign.center),
            if (isIntradayEmpty) const SizedBox(height: 6),
            if (isIntradayEmpty) Text(l10n.chartOhlcHint, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 12), textAlign: TextAlign.center),
            if (isKlineEmpty && klineError != null && klineError.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(l10n.chartRequestFailed(klineError), style: TextStyle(color: ChartTheme.down, fontSize: 12), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (isKlineEmpty) const SizedBox(height: 8),
            if (isKlineEmpty) Text(l10n.chartClickRetry, style: TextStyle(color: ChartTheme.accentGold, fontSize: 13), textAlign: TextAlign.center),
            if (isKlineEmpty) const SizedBox(height: 4),
            if (isKlineEmpty) Text(l10n.chartNoDataTroubleshoot, style: TextStyle(color: ChartTheme.textTertiary, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
    if (isKlineEmpty && onRetry != null) {
      return GestureDetector(onTap: onRetry, behavior: HitTestBehavior.opaque, child: content);
    }
    return content;
  }

  /// 鍒嗘椂涓?K 绾挎暟鎹殕绌烘椂锛氬眳涓┖鎬佸崱鐗囷紙浠?UI锛屼笉鏀规暟鎹€昏緫锛?
  Widget _buildEmptyStateCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(ChartTheme.sectionGap),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: ChartTheme.cardBackground,
          borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
          border: Border.all(color: ChartTheme.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded, size: 48, color: ChartTheme.textTertiary),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.chartNoData,
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.chartEmptyHint,
              style: TextStyle(color: ChartTheme.textTertiary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _emptyStateButton(AppLocalizations.of(context)!.chartRetry, onPressed: () {
                  setState(() => _chartLoading = true);
                  _loadIntraday().then((_) => _loadKLine()).then((_) {
                    if (mounted) setState(() => _chartLoading = false);
                  });
                }),
                const SizedBox(width: 12),
                _emptyStateButton(AppLocalizations.of(context)!.chartSwitchDataSource, onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyStateButton(String label, {required VoidCallback onPressed}) {
    return Material(
      color: ChartTheme.surface2,
      borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        hoverColor: ChartTheme.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label, style: TextStyle(color: ChartTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  static List<double?> _ma(List<ChartCandle> candles, int period) {
    if (candles.isEmpty) return [];
    final closes = candles.map((c) => c.close).toList();
    final out = <double?>[];
    for (var i = 0; i < closes.length; i++) {
      if (i + 1 < period) {
        out.add(null);
        continue;
      }
      double sum = 0;
      for (var j = i - period + 1; j <= i; j++) sum += closes[j];
      out.add(sum / period);
    }
    return out;
  }

  static const double _candleWidth = 8.0;
  static const double _chartHeight = 220.0;
  static const double _volumeHeight = 56.0;
  static const double _timeAxisHeight = 22.0;

  }






