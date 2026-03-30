import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../watchlist_repository.dart';
import 'chart_theme.dart';

class DetailHeader extends StatefulWidget {
  const DetailHeader({
    super.key,
    required this.symbol,
    this.name,
    this.exchangeOrName,
    this.onBack,
    this.onShare,
    this.onMore,
    this.onPrev,
    this.onNext,
  });

  final String symbol;
  final String? name;
  final String? exchangeOrName;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  State<DetailHeader> createState() => _DetailHeaderState();
}

class _DetailHeaderState extends State<DetailHeader> {
  static const double _swipeThreshold = 100.0;
  bool _inWatchlist = false;

  @override
  void initState() {
    super.initState();
    _checkWatchlist();
  }

  @override
  void didUpdateWidget(covariant DetailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _checkWatchlist();
    }
  }

  Future<void> _checkWatchlist() async {
    final list = await WatchlistRepository.instance.getWatchlist();
    if (mounted) {
      setState(() => _inWatchlist = list.contains(widget.symbol.trim()));
    }
  }

  Future<void> _toggleWatchlist() async {
    final symbol = widget.symbol.trim();
    if (symbol.isEmpty) return;
    if (_inWatchlist) {
      await WatchlistRepository.instance.removeWatchlist(symbol);
    } else {
      await WatchlistRepository.instance.addWatchlist(symbol);
    }
    if (!mounted) return;
    setState(() => _inWatchlist = !_inWatchlist);
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _inWatchlist
              ? l10n.searchAddedToWatchlist(symbol)
              : l10n.watchlistRemove,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = (widget.name ?? widget.exchangeOrName)?.trim();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Container(
          height: ChartTheme.topBarHeight,
          decoration: BoxDecoration(
            color: ChartTheme.cardBackground,
            borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
            border: Border.all(color: ChartTheme.border),
            boxShadow: ChartTheme.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _circleButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final velocity = details.velocity.pixelsPerSecond.dx;
                      if (velocity < -_swipeThreshold && widget.onNext != null) {
                        widget.onNext!();
                      } else if (velocity > _swipeThreshold &&
                          widget.onPrev != null) {
                        widget.onPrev!();
                      }
                    },
                    child: Row(
                      children: [
                        if (widget.onPrev != null)
                          _miniSwitchButton(
                            icon: Icons.chevron_left_rounded,
                            onPressed: widget.onPrev!,
                          ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.symbol,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: ChartTheme.textPrimary,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: ChartTheme.fontMono,
                                        fontFeatures: [
                                          ChartTheme.tabularFigures,
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ChartTheme.tabSelectedBg,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'US',
                                      style: TextStyle(
                                        color: ChartTheme.accentGold,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (subtitle != null && subtitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ChartTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (widget.onNext != null)
                          _miniSwitchButton(
                            icon: Icons.chevron_right_rounded,
                            onPressed: widget.onNext!,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _circleButton(
                  icon: _inWatchlist
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color:
                      _inWatchlist ? ChartTheme.accentGold : ChartTheme.textPrimary,
                  onPressed: _toggleWatchlist,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: ChartTheme.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 20, color: color ?? ChartTheme.textPrimary),
        ),
      ),
    );
  }

  Widget _miniSwitchButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: ChartTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}
