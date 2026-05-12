import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token_config.dart';
import '../providers/providers.dart';

class ConfigList extends ConsumerWidget {
  final VoidCallback onCreateTap;

  const ConfigList({super.key, required this.onCreateTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(configsProvider);
    final selectedId = ref.watch(selectedConfigIdProvider);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F8),
        border: Border(
          right: BorderSide(color: Colors.black.withAlpha(20)),
        ),
      ),
      child: configsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(fontSize: 12)),
        ),
        data: (configs) {
          if (configs.isEmpty) {
            return _EmptyState(onCreateTap: onCreateTap);
          }

          // active configs first, then sorted by id descending
          final sorted = [...configs]..sort((a, b) {
              if (a.isActive && !b.isActive) return -1;
              if (!a.isActive && b.isActive) return 1;
              return b.id.compareTo(a.id);
            });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sorted.length,
            itemBuilder: (context, i) => _ConfigCard(
              config: sorted[i],
              isSelected: sorted[i].id == selectedId,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.key_off, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            '暂无配置',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('创建配置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigCard extends ConsumerWidget {
  final TokenConfig config;
  final bool isSelected;

  const _ConfigCard({required this.config, required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider).valueOrNull ?? [];

    String vendorLabel;
    try {
      vendorLabel = companies
          .firstWhere((c) => c.url == config.url,
              orElse: () => throw StateError(''))
          .name;
    } catch (_) {
      vendorLabel = _shortUrl(config.url);
    }

    return GestureDetector(
      onTap: () => ref.read(selectedConfigIdProvider.notifier).state = config.id,
      onDoubleTap: () => _handleDoubleTap(ref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : config.isActive
                    ? const Color(0xFF6366F1).withAlpha(100)
                    : Colors.transparent,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (config.isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '生效中',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              vendorLabel,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              config.model,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _handleDoubleTap(WidgetRef ref) {
    if (config.isActive) {
      ref.read(configsProvider.notifier).deactivate(config.id);
    } else {
      ref.read(configsProvider.notifier).activate(config.id);
    }
  }

  String _shortUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url;
    }
  }
}
