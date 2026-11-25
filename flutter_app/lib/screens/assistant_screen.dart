import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage(this.text, this.isUser);
}

class _AssistantScreenState extends State<AssistantScreen> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final messages = <_ChatMessage>[
    const _ChatMessage(
      "Hi! I'm Spendly Assistant. I can analyse the transactions saved in your app and help you understand your spending, cash flow and purchase affordability. What would you like to know?",
      false,
    ),
  ];
  bool sending = false;
  bool useOllama = false;

  final prompts = const [
    'Where am I spending the most?',
    'How much did I spend this month?',
    'How much can I save?',
    'Can I afford ₹20,000?',
  ];

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> send([String? preset]) async {
    final text = (preset ?? controller.text).trim();
    if (text.isEmpty || sending) return;
    controller.clear();
    setState(() {
      messages.add(_ChatMessage(text, true));
      sending = true;
    });
    _scrollToBottom();
    try {
      final answer = useOllama ? await ApiService.askOllama(text) : await ApiService.askAssistant(text);
      if (!mounted) return;
      setState(() => messages.add(_ChatMessage(answer, false)));
    } catch (e) {
      if (!mounted) return;
      setState(() => messages.add(_ChatMessage(
        'I could not reach the Spendly server. Check that FastAPI is running, then try again.\n\n$e',
        false,
      )));
    } finally {
      if (mounted) {
        setState(() => sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Spendly Assistant', style: TextStyle(fontWeight: FontWeight.w700)), Text(useOllama ? 'Ollama local model' : 'Rules-based financial assistant', style: const TextStyle(fontSize: 11, color: Colors.grey))]),
        actions: [
          Row(
            children: [
              const Text('Ollama', style: TextStyle(fontSize: 12)),
              Switch(
                value: useOllama,
                onChanged: sending ? null : (v) => setState(() => useOllama = v),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 9),
                Expanded(child: Text(
                  useOllama ? 'Ollama mode sends a financial summary and your question to the local Ollama server configured on the backend.' : 'Rule-based mode answers from saved Spendly transactions without using an LLM. Neither mode is regulated financial advice.',
                  style: const TextStyle(fontSize: 12),
                )),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              itemCount: messages.length + (sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (sending && index == messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                }
                final message = messages[index];
                return Align(
                  alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      color: message.isUser ? colors.primary : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.isUser ? colors.onPrimary : colors.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (messages.length == 1)
            SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                children: prompts.map((prompt) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(label: Text(prompt), onPressed: sending ? null : () => send(prompt)),
                )).toList(),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                      decoration: InputDecoration(
                        hintText: 'Ask about your money...',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : () => send(),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: 'Send message',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
