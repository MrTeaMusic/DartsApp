import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/presentation/game_setup_screen.dart';
import '../../games/presentation/game_texts.dart';
import '../data/plan_repository.dart';
import '../domain/training_plan.dart';
import 'plan_routes.dart';
import 'plan_texts.dart';

/// Eigenen Plan anlegen ([planId] `null`) oder bearbeiten.
class PlanEditorScreen extends ConsumerStatefulWidget {
  const PlanEditorScreen({super.key, this.planId});
  final String? planId;

  @override
  ConsumerState<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends ConsumerState<PlanEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<PlanStep> _steps = [];
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.planId;
    if (id != null) {
      _loading = true;
      ref.read(planRepositoryProvider).byId(id).then((plan) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          if (plan != null) {
            _name.text = plan.name;
            _description.text = plan.description;
            _steps = List.of(plan.steps);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _editStep(int? index) async {
    final initial = index == null ? null : _steps[index];
    final result = await Navigator.of(context).push<PlanStep>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlanStepEditor(initial: initial)),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _steps = [..._steps, result];
      } else {
        _steps = [..._steps]..[index] = result;
      }
      _error = null;
    });
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final list = [..._steps];
      final s = list.removeAt(index);
      list.insert(target, s);
      _steps = list;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = TrainingPlan.cleanName(_name.text);
    if (name.isEmpty) return setState(() => _error = l10n.planNameMissing);
    if (_steps.isEmpty) return setState(() => _error = l10n.planStepsMissing);
    setState(() => _saving = true);
    final repo = ref.read(planRepositoryProvider);
    final id = widget.planId;
    final String target;
    if (id == null) {
      target = await repo.create(name: name, description: _description.text, steps: _steps);
    } else {
      await repo.update(id, name: name, description: _description.text, steps: _steps);
      target = id;
    }
    if (mounted) context.go(PlanRoutes.plan(target));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppPageBar(
        maxWidth: 640,
        title: Text(widget.planId == null ? l10n.planNew : l10n.planEditTitle),
        actions: [
          TextButton(
            key: const Key('plan-save'),
            onPressed: _saving || _loading ? null : _save,
            child: Text(l10n.planSave),
          ),
        ],
      ),
      body: _loading
          ? const SizedBox.shrink()
          : AppPage(
        maxWidth: 640,
        children: [
                    TextField(
                      key: const Key('plan-name'),
                      controller: _name,
                      maxLength: TrainingPlan.maxNameLength,
                      decoration: InputDecoration(labelText: l10n.planName),
                      onChanged: (_) => _error == null ? null : setState(() => _error = null),
                    ),
                    TextField(
                      key: const Key('plan-description'),
                      controller: _description,
                      maxLength: TrainingPlan.maxDescriptionLength,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: l10n.planDescription),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    SectionHeader(l10n.planSteps),
                    if (_steps.isNotEmpty)
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Column(
                          children: [
                            for (final (i, s) in _steps.indexed)
                              PlanStepTile(
                                key: Key('plan-step-$i'),
                                index: i,
                                step: s,
                                onTap: s.available ? () => _editStep(i) : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: Key('plan-step-$i-up'),
                                      tooltip: l10n.planMoveUp,
                                      onPressed: i > 0 ? () => _move(i, -1) : null,
                                      icon: const Icon(Icons.arrow_upward_rounded),
                                    ),
                                    IconButton(
                                      key: Key('plan-step-$i-down'),
                                      tooltip: l10n.planMoveDown,
                                      onPressed: i < _steps.length - 1 ? () => _move(i, 1) : null,
                                      icon: const Icon(Icons.arrow_downward_rounded),
                                    ),
                                    IconButton(
                                      key: Key('plan-step-$i-remove'),
                                      tooltip: l10n.planRemoveStep,
                                      onPressed: () => setState(() => _steps = [..._steps]..removeAt(i)),
                                      icon: const Icon(Icons.delete_outline_rounded),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.m),
                    OutlinedButton.icon(
                      key: const Key('plan-add-step'),
                      onPressed: () => _editStep(null),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.planAddStep),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.m),
                      Text(_error!, key: const Key('plan-error'), style: theme.textTheme.bodyMedium?.copyWith(color: context.dartColors.danger)),
                    ],
                  ],
      ),
    );
  }
}

/// Spiel, Einstellungen und Hinweis eines Schritts. Die Felder sind
/// dieselben wie vor einem normalen Spielstart.
class PlanStepEditor extends StatefulWidget {
  const PlanStepEditor({super.key, this.initial});
  final PlanStep? initial;

  @override
  State<PlanStepEditor> createState() => _PlanStepEditorState();
}

class _PlanStepEditorState extends State<PlanStepEditor> {
  late String _gameId;
  late Map<String, Object?> _config;
  late final TextEditingController _note = TextEditingController(text: widget.initial?.note ?? '');

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null && initial.available) {
      _gameId = initial.gameId;
      _config = initial.resolvedConfig;
    } else {
      _select(GameCatalog.all.first.id);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _select(String id) {
    _gameId = id;
    _config = {...GameCatalog.byId(id)!.defaults};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final def = GameCatalog.byId(_gameId)!;
    return Scaffold(
      appBar: AppPageBar(
        maxWidth: 640,
        title: Text(l10n.planStepTitle),
        actions: [
          TextButton(
            key: const Key('step-save'),
            onPressed: () {
              final note = _note.text.trim();
              Navigator.pop(context, PlanStep(gameId: _gameId, config: def.resolve(_config), note: note.isEmpty ? null : note));
            },
            child: Text(l10n.planStepApply),
          ),
        ],
      ),
      body: AppPage(
        maxWidth: 640,
        children: [
              SectionHeader(l10n.planStepGame),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  for (final g in GameCatalog.all)
                    ChoiceChip(
                      key: Key('step-game-${g.id}'),
                      avatar: Icon(gameIcon(g.id), size: 18),
                      label: Text(l10n.gameTitle(g.id)),
                      selected: g.id == _gameId,
                      onSelected: (_) => setState(() => _select(g.id)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              Text(l10n.gameDescription(def.id), style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(l10n.gameSettings),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, o) in def.options.indexed) ...[
                      if (i > 0) const Divider(height: AppSpacing.xl),
                      GameOptionField(
                        key: ValueKey('${def.id}-${o.key}'),
                        option: o,
                        gameId: def.id,
                        value: _config[o.key],
                        onChanged: (v) => setState(() => _config = {..._config, o.key: v}),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                key: const Key('step-note'),
                controller: _note,
                maxLength: 120,
                decoration: InputDecoration(labelText: l10n.planStepNote),
              ),
            ],
      ),
    );
  }
}
