import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/collections/reorder_items.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/settings/presentation/category_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _tabIndicatorInset = 2.0;

class CategoryManagementPage extends ConsumerStatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  ConsumerState<CategoryManagementPage> createState() =>
      _CategoryManagementPageState();
}

class _CategoryManagementPageState extends ConsumerState<CategoryManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('记账分类'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(
            AppSizes.control + AppSpacing.controlGap,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal,
              vertical: AppSpacing.xxs,
            ),
            child: AppSegmentedSurface(
              child: TabBar(
                controller: _tabs,
                indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: _tabIndicatorInset,
                  vertical: _tabIndicatorInset,
                ),
                tabs: const [
                  Tab(text: '支出'),
                  Tab(text: '收入'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _CategoryList(type: EntryType.expense),
          _CategoryList(type: EntryType.income),
        ],
      ),
    );
  }
}

class _CategoryList extends ConsumerStatefulWidget {
  const _CategoryList({required this.type});

  final EntryType type;

  @override
  ConsumerState<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<_CategoryList> {
  List<CategoryRow> _items = const [];
  bool _savingOrder = false;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesByTypeProvider(widget.type));
    return categories.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stackTrace) => const Center(child: Text('分类加载失败')),
      data: (items) {
        if (!_savingOrder && !_sameOrder(_items, items)) {
          _items = List<CategoryRow>.of(items);
        }
        final visibleItems = _items;
        return Stack(
          children: [
            if (visibleItems.isEmpty)
              const Center(child: Text('暂无分类'))
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageHorizontal,
                      AppSpacing.componentGap,
                      AppSpacing.pageHorizontal,
                      96,
                    ),
                    itemCount: visibleItems.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: AppSpacing.controlGap,
                          mainAxisSpacing: AppSpacing.controlGap,
                          childAspectRatio: .82,
                        ),
                    itemBuilder: (context, index) => _DraggableCategoryCard(
                      category: visibleItems[index],
                      index: index,
                      tileWidth:
                          (constraints.maxWidth -
                              AppSpacing.pageHorizontal * 2 -
                              AppSpacing.controlGap * 3) /
                          4,
                      onTap: () => _edit(visibleItems[index]),
                      onDrop: (from, to) => _reorder(from, to),
                    ),
                  );
                },
              ),
            Positioned(
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: FloatingActionButton(
                onPressed: () => _edit(null),
                child: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reorder(int from, int to) async {
    if (_savingOrder || from == to || from < 0 || to < 0) return;
    final previous = List<CategoryRow>.of(_items);
    final reordered = reorderItems(_items, from, to);
    setState(() {
      _items = reordered;
      _savingOrder = true;
    });
    try {
      await ref
          .read(bookkeepingRepositoryProvider)
          .reorderCategories(
            type: widget.type,
            orderedIds: [for (final category in reordered) category.id],
          );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _items = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '分类排序保存失败，请重试')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _edit(CategoryRow? category) async {
    await context.push(
      AppRoutes.categoryEditor,
      extra: CategoryEditorArgs(type: widget.type, category: category),
    );
  }

  static bool _sameOrder(List<CategoryRow> left, List<CategoryRow> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].name != right[index].name ||
          left[index].iconCode != right[index].iconCode ||
          left[index].colorValue != right[index].colorValue) {
        return false;
      }
    }
    return true;
  }
}

class _DraggableCategoryCard extends StatelessWidget {
  const _DraggableCategoryCard({
    required this.category,
    required this.index,
    required this.tileWidth,
    required this.onTap,
    required this.onDrop,
  });

  final CategoryRow category;
  final int index;
  final double tileWidth;
  final VoidCallback onTap;
  final void Function(int from, int to) onDrop;

  @override
  Widget build(BuildContext context) {
    final card = _CategoryCard(category: category, onTap: onTap);
    return LongPressDraggable<int>(
      data: index,
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: tileWidth, child: card),
      ),
      childWhenDragging: Opacity(opacity: .32, child: card),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) => onDrop(details.data, index),
        builder: (context, candidates, rejected) => AnimatedScale(
          scale: candidates.isEmpty ? 1 : 1.05,
          duration: AppMotion.fast,
          child: card,
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final CategoryRow category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return AppCard(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.controlGap,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryIcon(
                code: category.iconCode,
                color: color,
                size: AppSizes.categoryIconLarge,
              ),
              const SizedBox(height: AppSpacing.controlGap),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
