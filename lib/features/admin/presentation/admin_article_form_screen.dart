import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'admin_providers.dart';
import 'admin_read.dart';
import 'widgets/not_authorized_view.dart';

import 'package:fyp_foreseeme/core/theme/foreseeme_surface.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_theme.dart';
import 'package:fyp_foreseeme/core/theme/foreseeme_tokens.dart';
import 'package:fyp_foreseeme/core/widgets/app_button.dart';
import 'package:fyp_foreseeme/features/admin/presentation/admin_content_providers.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/services/article_slug.dart';
import 'package:fyp_foreseeme/features/resources/presentation/widgets/resource_visuals.dart';

/// Create/edit form for one Resource Center article (Sprint M8.3, SDS FR8.3).
/// Pushed (not a shell branch) from [AdminContentScreen]'s "Add article"
/// button or an existing article's tile — mirrors the medication feature's
/// `AddMedicationScreen(medication: ...)` optional-extra convention for
/// add-vs-edit.
///
/// Deliberately a structured block editor (heading/paragraph/tip/warning), not
/// a single free-text body: [ResourceArticle.content] is genuinely typed, and
/// this is the only way an admin can reproduce that structure (e.g. a
/// "warning" callout) rather than flattening every article to one paragraph.
class AdminArticleFormScreen extends ConsumerStatefulWidget {
  /// `null` for "add"; the article being edited otherwise. Its [id] is fixed
  /// for the lifetime of the article — an edit never changes it, even if the
  /// title changes (bookmarks/deep-links point at the id).
  final ResourceArticle? article;

  const AdminArticleFormScreen({super.key, this.article});

  @override
  ConsumerState<AdminArticleFormScreen> createState() =>
      _AdminArticleFormScreenState();
}

class _BlockDraft {
  ArticleBlockKind kind;
  final TextEditingController controller;
  _BlockDraft({required this.kind, String text = ''})
    : controller = TextEditingController(text: text);
}

class _AdminArticleFormScreenState
    extends ConsumerState<AdminArticleFormScreen> {
  late final _titleController = TextEditingController(
    text: widget.article?.title ?? '',
  );
  late final _summaryController = TextEditingController(
    text: widget.article?.summary ?? '',
  );
  late final _sourceNameController = TextEditingController(
    text: widget.article?.sourceName ?? '',
  );
  late final _sourceUrlController = TextEditingController(
    text: widget.article?.sourceUrl ?? '',
  );
  late ResourceTopic _topic = widget.article?.topic ?? ResourceTopic.lungs;
  late final List<_BlockDraft> _blocks = widget.article != null
      ? widget.article!.content
            .map((b) => _BlockDraft(kind: b.kind, text: b.text))
            .toList()
      : [_BlockDraft(kind: ArticleBlockKind.paragraph)];

  bool get _isNew => widget.article == null;

  /// True only once [_submit] has actually called `save()`. Needed because
  /// [AsyncNotifier.build] itself transitions `AsyncLoading` → `AsyncData` the
  /// moment the controller is first created — identical in shape to a real
  /// save completing — so gating the `ref.listen` pop below on
  /// `previous is AsyncLoading` alone would pop the screen the instant it
  /// opens, before the admin has done anything.
  bool _submitted = false;

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _sourceNameController.dispose();
    _sourceUrlController.dispose();
    for (final b in _blocks) {
      b.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(adminArticleFormControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (e, _) {
          _submitted = false;
          _snack('Could not save article: $e', isError: true);
        },
        data: (_) {
          if (_submitted && previous is AsyncLoading && mounted) {
            _submitted = false;
            context.pop();
          }
        },
      );
    });

    final session = ref.watch(isAdminProvider);
    if (session.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (session.hasError) {
      return Center(
        child: AdminReadError(
          message: 'Could not verify the administrator session.',
          error: session.error!,
          retry: () => ref.invalidate(isAdminProvider),
        ),
      );
    }
    if (session.value != true) return const NotAuthorizedView();

    final controllerState = ref.watch(adminArticleFormControllerProvider);
    final isBusy = controllerState.isLoading;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ForeSeeMeSpacing.gutter,
          ForeSeeMeSpacing.md,
          ForeSeeMeSpacing.gutter,
          ForeSeeMeSpacing.xxxl,
        ),
        children: [
          _label(_isNew ? 'Title' : 'Title (id stays "${widget.article!.id}")'),
          _textField(
            _titleController,
            hint: 'e.g. Staying safe in extreme heat',
            key: const Key('article-title-field'),
          ),
          const SizedBox(height: ForeSeeMeSpacing.lg),
          _label('Category'),
          _TopicDropdown(
            value: _topic,
            onChanged: (t) => setState(() => _topic = t),
          ),
          const SizedBox(height: ForeSeeMeSpacing.lg),
          _label('Summary'),
          _textField(
            _summaryController,
            hint: 'One line shown in the article list.',
            key: const Key('article-summary-field'),
          ),
          const SizedBox(height: ForeSeeMeSpacing.lg),
          _label('Source name'),
          _textField(
            _sourceNameController,
            hint: 'e.g. World Health Organization (WHO)',
            key: const Key('article-source-name-field'),
          ),
          const SizedBox(height: ForeSeeMeSpacing.lg),
          _label('Source URL (must be https)'),
          _textField(
            _sourceUrlController,
            hint: 'https://...',
            key: const Key('article-source-url-field'),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xl),
          _label('Content'),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          for (var i = 0; i < _blocks.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: ForeSeeMeSpacing.md),
              child: _BlockEditor(
                draft: _blocks[i],
                canRemove: _blocks.length > 1,
                onKindChanged: (k) => setState(() => _blocks[i].kind = k),
                onRemove: () => setState(() {
                  _blocks[i].controller.dispose();
                  _blocks.removeAt(i);
                }),
              ),
            ),
          AppButton(
            text: 'Add block',
            isOutlined: true,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => setState(
              () => _blocks.add(_BlockDraft(kind: ArticleBlockKind.paragraph)),
            ),
          ),
          const SizedBox(height: ForeSeeMeSpacing.xxl),
          AppButton(
            text: _isNew ? 'Publish article' : 'Save changes',
            isLoading: isBusy,
            onPressed: isBusy ? null : _submit,
          ),
        ],
      ),
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    final summary = _summaryController.text.trim();
    final sourceName = _sourceNameController.text.trim();
    final sourceUrl = _sourceUrlController.text.trim();

    if (title.isEmpty) return _snack('Title is required.', isError: true);
    if (summary.isEmpty) return _snack('Summary is required.', isError: true);
    if (sourceName.isEmpty) {
      return _snack('Source name is required.', isError: true);
    }
    final source = Uri.tryParse(sourceUrl);
    if (source == null ||
        source.scheme != 'https' ||
        source.host.isEmpty ||
        source.userInfo.isNotEmpty) {
      return _snack('Source URL must start with https://.', isError: true);
    }
    final content = [
      for (final b in _blocks)
        if (b.controller.text.trim().isNotEmpty)
          _blockFor(b.kind, b.controller.text.trim()),
    ];
    if (content.isEmpty) {
      return _snack('At least one content block is required.', isError: true);
    }

    if (content.every((block) => block.kind == ArticleBlockKind.heading)) {
      return _snack('Add a paragraph, tip, or warning.', isError: true);
    }

    final article = ResourceArticle(
      id: widget.article?.id ?? slugifyArticleTitle(title),
      title: title,
      summary: summary,
      content: content,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      topic: _topic,
      categories: {
        _topic,
        for (final category
            in widget.article?.categories ?? const <ResourceTopic>[])
          if (category != widget.article?.topic) category,
      }.toList(),
    );
    _submitted = true;
    ref
        .read(adminArticleFormControllerProvider.notifier)
        .save(article, isNew: _isNew);
  }

  static ArticleBlock _blockFor(ArticleBlockKind kind, String text) =>
      switch (kind) {
        ArticleBlockKind.heading => ArticleBlock.heading(text),
        ArticleBlockKind.paragraph => ArticleBlock.paragraph(text),
        ArticleBlockKind.tip => ArticleBlock.tip(text),
        ArticleBlockKind.warning => ArticleBlock.warning(text),
      };

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    final palette = context.fsmPalette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: context.fsmText.bodyLarge?.copyWith(
            color: isError ? palette.onError : palette.onSecondary,
          ),
        ),
        backgroundColor: isError ? palette.error : palette.secondary,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: ForeSeeMeSpacing.sm),
    child: Text(
      text,
      style: context.fsmText.labelSmall?.copyWith(letterSpacing: 1.2),
    ),
  );

  Widget _textField(
    TextEditingController controller, {
    required String hint,
    Key? key,
  }) {
    final palette = context.fsmPalette;
    return TextField(
      key: key,
      controller: controller,
      style: context.fsmText.bodyLarge?.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: context.fsmText.bodySmall,
        filled: true,
        fillColor: ForeSeeMeSurface.fill(context),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          borderSide: BorderSide(color: ForeSeeMeSurface.stroke(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
          borderSide: BorderSide(color: palette.secondary),
        ),
      ),
    );
  }
}

class _TopicDropdown extends StatelessWidget {
  final ResourceTopic value;
  final ValueChanged<ResourceTopic> onChanged;
  const _TopicDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ForeSeeMeSpacing.lg),
      decoration: BoxDecoration(
        color: ForeSeeMeSurface.fill(context),
        borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
        border: Border.all(color: ForeSeeMeSurface.stroke(context)),
      ),
      child: DropdownButton<ResourceTopic>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: palette.surfaceContainerHigh,
        style: context.fsmText.bodyLarge?.copyWith(color: palette.textPrimary),
        items: [
          for (final t in ResourceTopic.values)
            DropdownMenuItem(value: t, child: Text(resourceTopicLabel(t))),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

class _BlockEditor extends StatelessWidget {
  final _BlockDraft draft;
  final bool canRemove;
  final ValueChanged<ArticleBlockKind> onKindChanged;
  final VoidCallback onRemove;

  const _BlockEditor({
    required this.draft,
    required this.canRemove,
    required this.onKindChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.fsmPalette;
    return Container(
      padding: const EdgeInsets.all(ForeSeeMeSpacing.md),
      decoration: ForeSeeMeSurface.card(context, radius: ForeSeeMeRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ForeSeeMeSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: ForeSeeMeSurface.fill(context),
                    borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                    border: Border.all(color: ForeSeeMeSurface.stroke(context)),
                  ),
                  child: DropdownButton<ArticleBlockKind>(
                    value: draft.kind,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: palette.surfaceContainerHigh,
                    style: context.fsmText.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ArticleBlockKind.heading,
                        child: Text('Heading'),
                      ),
                      DropdownMenuItem(
                        value: ArticleBlockKind.paragraph,
                        child: Text('Paragraph'),
                      ),
                      DropdownMenuItem(
                        value: ArticleBlockKind.tip,
                        child: Text('Tip'),
                      ),
                      DropdownMenuItem(
                        value: ArticleBlockKind.warning,
                        child: Text('Warning'),
                      ),
                    ],
                    onChanged: (k) => k == null ? null : onKindChanged(k),
                  ),
                ),
              ),
              if (canRemove) ...[
                const SizedBox(width: ForeSeeMeSpacing.sm),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: palette.textTertiary),
                  tooltip: 'Remove block',
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
          const SizedBox(height: ForeSeeMeSpacing.sm),
          TextField(
            controller: draft.controller,
            maxLines: 4,
            minLines: 2,
            style: context.fsmText.bodyMedium?.copyWith(
              color: palette.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Block text…',
              hintStyle: context.fsmText.bodySmall,
              filled: true,
              fillColor: ForeSeeMeSurface.fill(context),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                borderSide: BorderSide(color: ForeSeeMeSurface.stroke(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ForeSeeMeRadius.sm),
                borderSide: BorderSide(color: palette.secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
