import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'chart_theme.dart';

List<({String label, String interval})> _extendedKlineOptions(
  AppLocalizations l10n,
) => [
      (label: l10n.chartWeekK, interval: '1week'),
      (label: l10n.chartMonthK, interval: '1month'),
      (label: l10n.chartYearK, interval: '1year'),
    ];

class ChartModeTabs extends StatelessWidget {
  const ChartModeTabs({
    super.key,
    required this.tabIndex,
    required this.onTabChanged,
    required this.isIntraday,
    required this.intradayPeriod,
    required this.klineTimespan,
    required this.onIntradayPeriodChanged,
    required this.onKlineTimespanChanged,
    this.labels,
    this.extendedKlineInterval = '1week',
    this.onExtendedKlineChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final bool isIntraday;
  final String intradayPeriod;
  final String klineTimespan;
  final ValueChanged<String> onIntradayPeriodChanged;
  final ValueChanged<String> onKlineTimespanChanged;
  final List<String>? labels;
  final String extendedKlineInterval;
  final ValueChanged<String>? onExtendedKlineChanged;

  static List<String> stockLabels(AppLocalizations l10n) => [
        l10n.chart1Min,
        l10n.chart5Min,
        l10n.chart15Min,
        l10n.chart30Min,
        l10n.chartDayK,
        l10n.chartWeekK,
      ];

  static List<String> genericLabels(AppLocalizations l10n) => [
        l10n.chartTimeshare,
        l10n.chartDayK,
      ];

  String _extendedLabel(AppLocalizations l10n) {
    final options = _extendedKlineOptions(l10n);
    return options
        .firstWhere(
          (option) => option.interval == extendedKlineInterval,
          orElse: () => options.first,
        )
        .label;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tabLabels = labels ?? stockLabels(l10n);
    final hasExtendedDropdown =
        tabLabels.length >= 6 && onExtendedKlineChanged != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabLabels.length, (index) {
            final selected = tabIndex == index;
            final isExtendedTab =
                hasExtendedDropdown && index == tabLabels.length - 1;
            return Padding(
              padding: EdgeInsets.only(right: index == tabLabels.length - 1 ? 0 : 8),
              child: isExtendedTab
                  ? _extendedTab(context, selected, l10n)
                  : _tabChip(
                      label: tabLabels[index],
                      selected: selected,
                      onTap: () => onTabChanged(index),
                    ),
            );
          }),
        ),
      ),
    );
  }

  Widget _extendedTab(
    BuildContext context,
    bool selected,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      onOpened: () => onTabChanged(5),
      onSelected: onExtendedKlineChanged,
      color: ChartTheme.surface2,
      itemBuilder: (context) => _extendedKlineOptions(l10n)
          .map(
            (option) => PopupMenuItem<String>(
              value: option.interval,
              child: Text(option.label),
            ),
          )
          .toList(),
      child: _tabChip(
        label: _extendedLabel(l10n),
        selected: selected,
        trailing: Icons.keyboard_arrow_down_rounded,
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
    IconData? trailing,
  }) {
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? ChartTheme.tabSelectedBg : ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? ChartTheme.accentGold : ChartTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Icon(
              trailing,
              size: 16,
              color:
                  selected ? ChartTheme.accentGold : ChartTheme.textSecondary,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }
}
