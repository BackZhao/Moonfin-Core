import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'book_glass.dart';

/// Pill track with a raised sliding segment. The Library/Discover tabs and
/// the format filter share it so the two read as one control family.
class BookSegmentedControl extends StatelessWidget {
  const BookSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColorScheme.onSurface;
    final count = labels.length;
    final index = count == 0 ? 0 : selectedIndex.clamp(0, count - 1);

    return bookGlassOrSolid(
      cornerRadius: 999,
      blur: 12,
      fallbackColor: onSurface.withValues(alpha: 0.08),
      context: context,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  count <= 1 ? 0 : -1 + index * (2 / (count - 1)),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: count == 0 ? 1 : 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.16),
                      borderRadius: AppRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(i),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: i == index
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: i == index
                                      ? onSurface
                                      : onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
