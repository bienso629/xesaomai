import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Bảng dữ liệu ảo hóa (Virtualized Data Table) kết hợp tự động tải thêm khi cuộn (Infinite Scroll / Load More).
///
/// - Dòng tiêu đề (Header) được ghim cố định (Sticky Header) ở phía trên.
/// - Phần thân bảng sử dụng [ListView.builder] kèm [itemExtent] cố định (`SliverFixedExtentList`),
///   giúp Flutter tính toán vị trí cuộn với độ phức tạp O(1) và CHỈ dựng (mount) các dòng
///   đang thực sự nằm trong vùng nhìn thấy (viewport) + `cacheExtent`.
/// - Tự động lắng nghe sự kiện cuộn gần chạm đáy để kích hoạt [onLoadMore] mà không cần bất kỳ thanh footer phân trang nào.
class VirtualizedDataTable extends StatefulWidget {
  final List<DataColumn> columns;
  final int itemCount;
  final DataRow Function(int index) rowBuilder;
  final List<int>? columnFlexes;
  final List<double?>? fixedColumnWidths;
  final double headingRowHeight;
  final double rowHeight;
  final double horizontalMargin;
  final double columnSpacing;
  final double minTableWidth;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final void Function(int index)? onRowTap;

  const VirtualizedDataTable({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.rowBuilder,
    this.columnFlexes,
    this.fixedColumnWidths,
    this.headingRowHeight = 44.0,
    this.rowHeight = 64.0,
    this.horizontalMargin = 16.0,
    this.columnSpacing = 20.0,
    this.minTableWidth = 0.0,
    this.hasMore = false,
    this.onLoadMore,
    this.onRowTap,
  });

  @override
  State<VirtualizedDataTable> createState() => _VirtualizedDataTableState();
}

class _VirtualizedDataTableState extends State<VirtualizedDataTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  DateTime _lastLoadMoreTriggered = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _tryTriggerLoadMore() {
    if (!widget.hasMore || widget.onLoadMore == null) return;
    final now = DateTime.now();
    if (now.difference(_lastLoadMoreTriggered).inMilliseconds < 80) return;
    _lastLoadMoreTriggered = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.hasMore) {
        widget.onLoadMore?.call();
      }
    });
  }

  List<double> _computeColumnWidths(double totalWidth) {
    final colCount = widget.columns.length;
    if (colCount == 0) return const [];

    final available = math.max(
      200.0,
      totalWidth -
          (widget.horizontalMargin * 2) -
          (widget.columnSpacing * math.max(0, colCount - 1)),
    );

    final fixed = List<double?>.generate(colCount, (i) {
      if (widget.fixedColumnWidths != null &&
          i < widget.fixedColumnWidths!.length) {
        return widget.fixedColumnWidths![i];
      }
      return null;
    });

    final flexes = List<int>.generate(colCount, (i) {
      if (widget.columnFlexes != null && i < widget.columnFlexes!.length) {
        return math.max(1, widget.columnFlexes![i]);
      }
      return 10;
    });

    double usedFixed = 0.0;
    int totalFlex = 0;
    for (int i = 0; i < colCount; i++) {
      if (fixed[i] != null) {
        usedFixed += fixed[i]!;
      } else {
        totalFlex += flexes[i];
      }
    }

    final flexSpace = math.max(0.0, available - usedFixed);
    final rawWidths = List<double>.generate(colCount, (i) {
      if (fixed[i] != null) return fixed[i]!;
      if (totalFlex <= 0) return flexSpace / colCount;
      return flexSpace * (flexes[i] / totalFlex);
    });
    final totalRaw = rawWidths.fold<double>(0.0, (a, b) => a + b);
    if (totalRaw > available && totalRaw > 0) {
      final scale = available / totalRaw;
      return rawWidths.map((w) => w * scale).toList();
    }
    return rawWidths;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(constraints.maxWidth, widget.minTableWidth);
        final tableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 560.0;
        final colWidths = _computeColumnWidths(tableWidth);

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical &&
                widget.hasMore &&
                widget.onLoadMore != null) {
              final metrics = notification.metrics;
              if (metrics.maxScrollExtent > 0 &&
                  metrics.pixels >= metrics.maxScrollExtent - 200) {
                _tryTriggerLoadMore();
              }
            }
            return false;
          },
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: tableWidth > constraints.maxWidth + 4,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                height: tableHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Dòng tiêu đề bảng cố định (Sticky Header)
                    Container(
                      height: widget.headingRowHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.horizontalMargin,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (int i = 0; i < widget.columns.length; i++) ...[
                            if (i > 0) SizedBox(width: widget.columnSpacing),
                            SizedBox(
                              width: colWidths[i],
                              child: Align(
                                alignment: widget.columns[i].numeric
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: DefaultTextStyle.merge(
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  child: widget.columns[i].label,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Thân bảng ảo hóa bằng ListView.builder (SliverFixedExtentList)
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _verticalController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemExtent: widget.rowHeight,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemCount:
                              widget.itemCount + (widget.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= widget.itemCount) {
                              // Dòng kích hoạt tải thêm tự động khi cuộn tới đáy
                              _tryTriggerLoadMore();
                              return Container(
                                height: widget.rowHeight,
                                alignment: Alignment.center,
                                color: Colors.blue.shade50.withValues(
                                  alpha: 0.35,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Đang tải thêm dữ liệu...",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final dataRow = widget.rowBuilder(index);
                            final bgColor =
                                dataRow.color?.resolve(const <WidgetState>{}) ??
                                (index % 2 == 0
                                    ? Colors.white
                                    : Colors.grey.shade50);
                            final rowTap = widget.onRowTap != null
                                ? () => widget.onRowTap!(index)
                                : (dataRow.onSelectChanged != null
                                    ? () => dataRow.onSelectChanged!(true)
                                    : null);

                            return Material(
                              color: bgColor,
                              child: InkWell(
                                onTap: rowTap,
                                hoverColor: Colors.blue.shade50.withValues(
                                  alpha: 0.45,
                                ),
                                child: Container(
                                  height: widget.rowHeight,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: widget.horizontalMargin,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                        width: 0.8,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      for (
                                        int c = 0;
                                        c < widget.columns.length;
                                        c++
                                      ) ...[
                                        if (c > 0)
                                          SizedBox(width: widget.columnSpacing),
                                        SizedBox(
                                          width: colWidths[c],
                                          child: c < dataRow.cells.length
                                              ? (dataRow.cells[c].onTap != null
                                                  ? GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTap: dataRow
                                                          .cells[c].onTap,
                                                      child: Align(
                                                        alignment: widget
                                                                .columns[c]
                                                                .numeric
                                                            ? Alignment
                                                                .centerRight
                                                            : Alignment
                                                                .centerLeft,
                                                        child: dataRow
                                                            .cells[c].child,
                                                      ),
                                                    )
                                                  : Align(
                                                      alignment: widget
                                                              .columns[c]
                                                              .numeric
                                                          ? Alignment
                                                              .centerRight
                                                          : Alignment
                                                              .centerLeft,
                                                      child: dataRow
                                                          .cells[c].child,
                                                    ))
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
