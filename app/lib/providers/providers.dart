import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent.dart';
import '../models/company.dart';
import '../models/latency_entry.dart';
import '../models/token_config.dart';
import '../models/usage_entry.dart';
import '../models/usage_stats.dart';
import '../services/api_service.dart';
import '../services/backend_service.dart';
import '../services/tray_service.dart';

// ── Core services ──────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final backendServiceProvider = Provider<BackendService>(
  (ref) => BackendService(ref.read(apiServiceProvider)),
);

final trayServiceProvider = Provider<TrayService>(
  (ref) => TrayService(ref.read(apiServiceProvider)),
);

// ── Selected state ─────────────────────────────────────────────────────────

final selectedAgentTypeProvider = StateProvider<String>((ref) => 'claude_code');

final selectedConfigIdProvider = StateProvider<int?>((ref) => null);

// ── Agents ─────────────────────────────────────────────────────────────────

final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  return ref.read(apiServiceProvider).listAgents();
});

// ── Configs ────────────────────────────────────────────────────────────────

class ConfigsNotifier extends AsyncNotifier<List<TokenConfig>> {
  @override
  Future<List<TokenConfig>> build() async {
    final agentType = ref.watch(selectedAgentTypeProvider);
    return ref.read(apiServiceProvider).listConfigs(agentType);
  }

  Future<void> reload() async {
    final agentType = ref.read(selectedAgentTypeProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(apiServiceProvider).listConfigs(agentType),
    );
  }

  Future<void> activate(int id) async {
    await ref.read(apiServiceProvider).activateConfig(id);
    await reload();
  }

  Future<void> deactivate(int id) async {
    await ref.read(apiServiceProvider).deactivateConfig(id);
    await reload();
  }

  Future<void> delete(int id) async {
    await ref.read(apiServiceProvider).deleteConfig(id);
    ref.read(selectedConfigIdProvider.notifier).state = null;
    await reload();
  }
}

final configsProvider =
    AsyncNotifierProvider<ConfigsNotifier, List<TokenConfig>>(
        ConfigsNotifier.new);

// ── Usage stats ─────────────────────────────────────────────────────────────

final usageStatsProvider =
    FutureProvider.family<UsageStats, int>((ref, configId) async {
  return ref.read(apiServiceProvider).getUsageStats(configId);
});

// ── Usage entries (chart data) ──────────────────────────────────────────────

final usagesProvider =
    FutureProvider.family<List<UsageEntry>, int>((ref, configId) async {
  return ref.read(apiServiceProvider).getUsages(configId: configId);
});

// ── Latency ─────────────────────────────────────────────────────────────────

final latencyProvider =
    FutureProvider.family<List<LatencyEntry>, int>((ref, configId) async {
  return ref.read(apiServiceProvider).getLatestLatency();
});

// ── Companies ────────────────────────────────────────────────────────────────

final companiesProvider = FutureProvider<List<Company>>((ref) async {
  return ref.read(apiServiceProvider).listCompanies();
});
