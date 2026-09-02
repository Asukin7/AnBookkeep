import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/prompt_template.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final class PromptRepository {
  PromptRepository(this._preferences);

  static const _templatesKey = 'smartBookkeeping.prompts.templates';
  static const _activeIdKey = 'smartBookkeeping.prompts.activeId';

  final SharedPreferences _preferences;

  PromptLibrary load() {
    final custom = decodeCustomPrompts(_preferences.getString(_templatesKey));
    final templates = [PromptTemplate.defaultTemplate, ...custom];
    final savedActive = _preferences.getString(_activeIdKey);
    final activeId = templates.any((item) => item.id == savedActive)
        ? savedActive!
        : defaultPromptId;
    return PromptLibrary(templates: templates, activeId: activeId);
  }

  Future<void> save(PromptLibrary library) async {
    await Future.wait([
      _preferences.setString(
        _templatesKey,
        encodeCustomPrompts(library.templates),
      ),
      _preferences.setString(_activeIdKey, library.activeId),
    ]);
  }
}

final promptRepositoryProvider = Provider<PromptRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  if (preferences == null) {
    throw StateError('SharedPreferences尚未初始化');
  }
  return PromptRepository(preferences);
});

final class PromptLibraryNotifier extends Notifier<PromptLibrary> {
  final _uuid = const Uuid();

  @override
  PromptLibrary build() => ref.watch(promptRepositoryProvider).load();

  Future<void> setActive(String id) async {
    if (state.byId(id) == null || state.activeId == id) return;
    state = PromptLibrary(templates: state.templates, activeId: id);
    await ref.read(promptRepositoryProvider).save(state);
  }

  Future<PromptTemplate> create({
    required String name,
    String content = defaultPromptContent,
  }) async {
    final template = PromptTemplate(
      id: _uuid.v7(),
      name: name.trim(),
      content: content,
      isBuiltIn: false,
    );
    state = PromptLibrary(
      templates: [...state.templates, template],
      activeId: state.activeId,
    );
    await ref.read(promptRepositoryProvider).save(state);
    return template;
  }

  Future<PromptTemplate> duplicate(PromptTemplate source) {
    return create(name: '${source.name} 副本', content: source.content);
  }

  Future<void> update(PromptTemplate template) async {
    if (template.isBuiltIn) return;
    state = PromptLibrary(
      templates: [
        for (final item in state.templates)
          if (item.id == template.id) template else item,
      ],
      activeId: state.activeId,
    );
    await ref.read(promptRepositoryProvider).save(state);
  }

  Future<void> delete(String id) async {
    final template = state.byId(id);
    if (template == null || template.isBuiltIn) return;
    state = PromptLibrary(
      templates: [
        for (final item in state.templates)
          if (item.id != id) item,
      ],
      activeId: state.activeId == id ? defaultPromptId : state.activeId,
    );
    await ref.read(promptRepositoryProvider).save(state);
  }
}

final promptLibraryProvider =
    NotifierProvider<PromptLibraryNotifier, PromptLibrary>(
      PromptLibraryNotifier.new,
    );
