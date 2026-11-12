import 'dart:async';

import 'package:flutter/material.dart';

/// Ô nhập autocomplete IN-LINE (không dùng Overlay/OverlayPortal).
///
/// Lý do tồn tại: widget `Autocomplete` của Flutter hiển thị gợi ý qua
/// OverlayPortal mount vào cây Navigator. Khi dialog đóng trong khi gợi ý
/// đang mở, overlay bị gỡ sai pha với cây inherited -> assertion
/// `_dependents.isEmpty` (framework.dart) và cascade "Tried to build dirty
/// widget in the wrong build scope". Panel gợi ý in-line nằm trong layout
/// của dialog nên khi dialog đóng, cả panel bị gỡ theo cây widget thông
/// thường - không còn overlay nào phải gỡ sai pha, không thể crash.
class InlineAutocompleteOption {
  final String value;
  final String title;
  final String sub;
  final Map<String, Object?> badge;
  final IconData? icon;
  final Map<String, dynamic> raw;

  const InlineAutocompleteOption({
    required this.value,
    this.title = '',
    this.sub = '',
    this.badge = const {},
    this.icon,
    this.raw = const {},
  });
}

class InlineAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool isRequired;
  final IconData prefixIcon;
  final List<InlineAutocompleteOption> options;
  final int maxOptions;
  final void Function(InlineAutocompleteOption option)? onOptionSelected;
  final void Function(String text)? onChanged;
  final Widget? suffix;
  final Widget? helperBelow;
  final bool showSuggestionsOnFocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool showLabel;

  const InlineAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.isRequired = false,
    this.prefixIcon = Icons.search,
    required this.options,
    this.maxOptions = 8,
    this.onOptionSelected,
    this.onChanged,
    this.suffix,
    this.helperBelow,
    this.showSuggestionsOnFocus = true,
    this.focusNode,
    this.enabled = true,
    this.showLabel = true,
  });

  @override
  State<InlineAutocompleteField> createState() =>
      _InlineAutocompleteFieldState();
}

class _InlineAutocompleteFieldState extends State<InlineAutocompleteField> {
  late final FocusNode _ownFocus = FocusNode();
  bool _open = false;
  String _lastSynced = '';
  Timer? _debounce;
  Timer? _blurTimer;

  FocusNode get _effectiveFocus => widget.focusNode ?? _ownFocus;

  @override
  void initState() {
    super.initState();
    _effectiveFocus.addListener(_onFocusChanged);
    widget.controller.addListener(_onControllerChanged);
    _lastSynced = widget.controller.text;
  }

  @override
  void didUpdateWidget(covariant InlineAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      _effectiveFocus.addListener(_onFocusChanged);
    }
    // Giá trị được điền từ bên ngoài (không phải do gõ) -> cập nhật trạng thái mở.
    if (widget.controller.text != _lastSynced) {
      _lastSynced = widget.controller.text;
      if (_open && !_effectiveFocus.hasFocus) {
        _open = false;
      }
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    _blurTimer?.cancel();
    if (_effectiveFocus.hasFocus) {
      // Chỉ mở gợi ý khi ô được focus; nội dung gợi ý do build tự tính theo text.
      if (!_open) setState(() => _open = true);
    } else {
      // Trì hoãn đóng gợi ý để sự kiện click chuột (pointer up / onTap) hoặc
      // onTapDown trên danh sách gợi ý luôn kịp chạy trước khi danh sách ẩn đi.
      _blurTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted && !_effectiveFocus.hasFocus && _open) {
          setState(() => _open = false);
        }
      });
    }
  }

  void _onControllerChanged() {
    final text = widget.controller.text;
    if (text == _lastSynced) return;
    _lastSynced = text;
    if (mounted) {
      setState(() {
        if (_effectiveFocus.hasFocus) _open = true;
      });
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) widget.onChanged?.call(text);
    });
  }

  List<InlineAutocompleteOption> get _filtered {
    final q = widget.controller.text.trim().toLowerCase();
    final List<InlineAutocompleteOption> src = List.of(widget.options);
    if (q.isEmpty) {
      return src.take(widget.maxOptions).toList();
    }
    final matched = src
        .where(
          (o) =>
              o.value.toLowerCase().contains(q) ||
              o.title.toLowerCase().contains(q) ||
              o.sub.toLowerCase().contains(q),
        )
        .toList();
    if (matched.isEmpty) return const [];
    return matched.take(widget.maxOptions).toList();
  }

  void _select(InlineAutocompleteOption o) {
    _debounce?.cancel();
    _blurTimer?.cancel();
    _lastSynced = o.value;
    widget.controller
      ..text = o.value
      ..selection = TextSelection.collapsed(offset: o.value.length);
    if (mounted) setState(() => _open = false);
    widget.onOptionSelected?.call(o);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _blurTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _effectiveFocus.removeListener(_onFocusChanged);
    _ownFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opts = _open ? _filtered : const <InlineAutocompleteOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.isRequired ? '${widget.label} *' : widget.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode ?? _ownFocus,
          enabled: widget.enabled,
          onTap: () {
            if (!_open) setState(() => _open = true);
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            prefixIcon: Icon(widget.prefixIcon, size: 17),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 0,
            ),
            suffixIcon: widget.suffix,
          ),
        ),
        if (opts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: opts.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, index) {
                  final o = opts[index];
                  final badge = o.badge;
                  final itemIcon = o.icon ?? widget.prefixIcon;
                  return InkWell(
                    canRequestFocus: false,
                    hoverColor: Colors.blue.shade50,
                    onTapDown: (_) => _select(o),
                    onTap: () => _select(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            itemIcon,
                            size: 15,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (o.title.isNotEmpty)
                                  Text(
                                    o.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (o.value.isNotEmpty &&
                                    o.value != o.title &&
                                    o.sub.isEmpty &&
                                    !o.title.contains(o.value))
                                  Text(
                                    o.value,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                if (o.sub.isNotEmpty)
                                  Text(
                                    o.sub,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if ((badge['text'] as String? ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    badge['bg'] as Color? ??
                                    Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      badge['border'] as Color? ??
                                      Colors.teal.shade200,
                                ),
                              ),
                              child: Text(
                                badge['text'] as String? ?? '',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      badge['fg'] as Color? ??
                                      Colors.teal.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (widget.helperBelow != null) widget.helperBelow!,
      ],
    );
  }
}
