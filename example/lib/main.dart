import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:quds_db_sqlite/quds_db_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;

// --- Database Models and Providers ---

class TaskModel extends StandardDbModel {
  final title = StringField(columnName: 'title', notNull: true);
  final isCompleted = BoolField(columnName: 'isCompleted', defaultValue: false);
  final priority = IntField(
    columnName: 'priority',
    defaultValue: 0,
  ); // 0: Low, 1: High
  final dueDate = DateTimeField(columnName: 'dueDate');

  @override
  List<FieldDefinition>? getFields() => [title, isCompleted, priority, dueDate];
}

class TaskProvider extends SqliteStandardTableProvider<TaskModel> {
  TaskProvider(super.connection, super.modelFactory, super.tableName);
}

// --- App Initialization ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for Desktop/Windows
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 1. Initialize the Settings and Adapter
  final adapter = SqliteDatabaseAdapter();
  await adapter.initialize(
    SqliteDatabaseSettings(dbName: 'tasks_demo.db', version: 1),
  );

  final connection = await adapter.getConnection() as SqliteDatabaseConnection;

  // 2. Initialize Provider (Automatically Migrates and Indexes)
  final taskProvider = TaskProvider(connection, () => TaskModel(), 'Tasks');
  await taskProvider.initialize();

  runApp(TaskFlowApp(provider: taskProvider, adapter: adapter));
}

// --- App UI ---

class TaskFlowApp extends StatelessWidget {
  final TaskProvider provider;
  final SqliteDatabaseAdapter adapter;

  const TaskFlowApp({super.key, required this.provider, required this.adapter});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quds DB Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF3B82F6),
          secondary: const Color(0xFF8B5CF6),
        ),
      ),
      home: TasksScreen(provider: provider, adapter: adapter),
    );
  }
}

class TasksScreen extends StatefulWidget {
  final TaskProvider provider;
  final SqliteDatabaseAdapter adapter;

  const TasksScreen({super.key, required this.provider, required this.adapter});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<TaskModel> _tasks = [];
  int _totalTasks = 0;
  int _pendingTasks = 0;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen to changes automatically emitted by the provider!
    widget.provider.addEntryChangeListener((type, entry) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    // 3. Complex Queries (Aggregations and Selecting)
    final total = await widget.provider.count();
    final pending = await widget.provider.countWhere(
      (t) => t.isCompleted.equals(false),
    );

    List<TaskModel> tasks;
    if (_filter == 'All') {
      tasks = await widget.provider.select(
        orderBy: (t) => [t.priority.descOrder], // Sort by Priority
      );
    } else {
      tasks = await widget.provider.select(
        where: (t) => t.isCompleted.equals(false) & t.id.moreThan(0),
        orderBy: (t) => [t.priority.descOrder],
      );
    }

    setState(() {
      _totalTasks = total;
      _pendingTasks = pending;
      _tasks = tasks;
    });
  }

  void _addTask() {
    final titleController = TextEditingController();
    bool isHighPriority = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('New Task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    hintText: 'What needs to be done?',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('High Priority'),
                  value: isHighPriority,
                  activeThumbColor: Theme.of(context).colorScheme.secondary,
                  onChanged: (v) => setState(() => isHighPriority = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) return;

                  // 4. Insert Entry
                  final task = TaskModel()
                    ..title.value = titleController.text.trim()
                    ..priority.value = isHighPriority ? 1 : 0
                    ..dueDate.value = DateTime.now().add(
                      const Duration(days: 1),
                    );

                  await widget.provider.insertEntry(task);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Add Task'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _clearCompleted() async {
    // 5. Bulk Deletion
    final sw = Stopwatch()..start();
    await widget.provider.deleteWhere((t) => t.isCompleted.equals(true));
    sw.stop();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cleared completed tasks! (${sw.elapsedMilliseconds} ms)')));
    }
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Clear All Tasks?'),
        content: const Text('Are you sure you want to delete all tasks? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final sw = Stopwatch()..start();
              await widget.provider.clear();
              sw.stop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('All tasks cleared! (${sw.elapsedMilliseconds} ms)')),
                );
              }
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _runTransaction() async {
    // Advanced: Automated Bulk Insertion (Transactions)
    try {
      final list = List.generate(1000, (i) => TaskModel()
        ..title.value = 'Bulk Txn Task ${i + 1}'
        ..priority.value = 1);

      final sw = Stopwatch()..start();
      await widget.provider.insertCollection(list);
      sw.stop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk Insert successfully committed! (${sw.elapsedMilliseconds} ms)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bulk Insert Failed & Rolled Back!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _vacuum() async {
    // 6. DB Optimization
    final sw = Stopwatch()..start();
    await widget.adapter.vacuumDb();
    sw.stop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database Optimized (VACUUM)! (${sw.elapsedMilliseconds} ms)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Liquid Tasks',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical),
            onSelected: (val) {
              if (val == 'clear') _clearCompleted();
              if (val == 'clear_all') _clearAll();
              if (val == 'txn') _runTransaction();
              if (val == 'vacuum') _vacuum();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear Completed'),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Text('Clear All Tasks', style: TextStyle(color: Colors.redAccent)),
              ),
              const PopupMenuItem(
                value: 'txn',
                child: Text('Test Transaction'),
              ),
              const PopupMenuItem(
                value: 'vacuum',
                child: Text('Optimize DB (Vacuum)'),
              ),
            ],
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(
                  context,
                ).colorScheme.secondary.withValues(alpha: 0.3),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.transparent),
          ),

          SafeArea(
            child: Column(
              children: [
                // Stats Header
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(label: 'Total Tasks', value: '$_totalTasks'),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        _StatItem(
                          label: 'Pending',
                          value: '$_pendingTasks',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),

                // Filter Tabs
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FilterTab(
                      title: 'All',
                      isSelected: _filter == 'All',
                      onTap: () => setState(() {
                        _filter = 'All';
                        _loadData();
                      }),
                    ),
                    const SizedBox(width: 16),
                    _FilterTab(
                      title: 'Pending',
                      isSelected: _filter == 'Pending',
                      onTap: () => setState(() {
                        _filter = 'Pending';
                        _loadData();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tasks List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return _TaskCard(
                        task: task,
                        onToggle: () async {
                          task.isCompleted.value =
                              !(task.isCompleted.value ?? false);
                          // 7. Update Entry
                          await widget.provider.updateEntry(task);
                        },
                        onDelete: () async {
                          // 8. Delete by ID
                          if (task.id.value != null) {
                            await widget.provider.deleteById(task.id.value!);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterTab({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted.value ?? false;
    final isHigh = task.priority.value == 1;

    return Dismissible(
      key: ValueKey(task.id.value),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: isDone
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: isDone
                  ? const Icon(LucideIcons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          title: Text(
            task.title.value ?? '',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: isDone
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.white,
            ),
          ),
          trailing: isHigh
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.flame,
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
