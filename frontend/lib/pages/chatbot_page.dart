import 'package:flutter/material.dart';

import '../api/client.dart';
import '../widgets/graph_canvas.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = false;

  static const _presets = [
    ('Find cycles', 'find_cycles'),
    ('Shell clusters', 'find_shells'),
    ('Top risk accounts', 'top_risk'),
    ('Dormant activations', 'dormant_activations'),
    ('Trace path', 'trace_path'),
  ];

  final List<_ChatMessage> _messages = [];

  Future<void> _send(String question, {String? preset}) async {
    if (question.trim().isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(question: question, loading: true));
      _loading = true;
    });
    _ctrl.clear();
    _scrollDown();

    try {
      final result = await ApiClient.instance.sendChat(question, preset: preset);
      setState(() {
        _messages.last = _ChatMessage(
          question: question,
          loading: false,
          data: result,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.last = _ChatMessage(
          question: question,
          loading: false,
          error: e.toString(),
        );
        _loading = false;
      });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Graph Chatbot',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Ask questions about the transaction network',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Preset chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            children: _presets
                .map((p) => ActionChip(
                      label: Text(p.$1),
                      onPressed: _loading
                          ? null
                          : () => _send(p.$1, preset: p.$2),
                      avatar: const Icon(Icons.bolt, size: 14),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(24),
            itemCount: _messages.length,
            itemBuilder: (ctx, i) => _MessageCard(msg: _messages[i]),
          ),
        ),

        // Input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything about the network…',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (v) => _send(v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _loading ? null : () => _send(_ctrl.text),
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessage {
  final String question;
  final bool loading;
  final Map<String, dynamic>? data;
  final String? error;

  const _ChatMessage({
    required this.question,
    required this.loading,
    this.data,
    this.error,
  });
}

class _MessageCard extends StatelessWidget {
  final _ChatMessage msg;
  const _MessageCard({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User question
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(msg.question,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (msg.loading)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),

          if (msg.error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(msg.error!,
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ),

          if (msg.data != null) _ResponseBody(data: msg.data!),
        ],
      ),
    );
  }
}

class _ResponseBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ResponseBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = data['records'] as List<dynamic>? ?? [];
    final summary = data['summary'] as String? ?? '';
    final cypher = data['cypher'] as String? ?? '';

    // Check if records look like graph data
    final hasNodes = records.isNotEmpty &&
        (records.first as Map<String, dynamic>?)?.containsKey('id') == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Records: graph or table
        if (records.isNotEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: hasNodes
                  ? SizedBox(
                      height: 260,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0D1A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: GraphCanvas(
                            nodes: records
                                .map((e) => GraphNode.fromJson(
                                    e as Map<String, dynamic>))
                                .toList(),
                            edges: const [],
                          ),
                        ),
                      ),
                    )
                  : _RecordTable(records: records),
            ),
          ),

        if (summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(summary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic)),
            ),
          ),
        ],

        if (cypher.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(cypher,
                style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ],
    );
  }
}

class _RecordTable extends StatelessWidget {
  final List<dynamic> records;
  const _RecordTable({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final keys = (records.first as Map<String, dynamic>).keys.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 36,
        columnSpacing: 16,
        columns: keys
            .map((k) => DataColumn(
                label: Text(k,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 11))))
            .toList(),
        rows: records
            .take(20)
            .map((r) {
              final row = r as Map<String, dynamic>;
              return DataRow(
                  cells: keys
                      .map((k) => DataCell(Text(
                            '${row[k] ?? ''}',
                            style: const TextStyle(fontSize: 12),
                          )))
                      .toList());
            })
            .toList(),
      ),
    );
  }
}