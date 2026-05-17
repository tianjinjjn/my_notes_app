import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:archive/archive.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyNotesApp());
}

class MyNotesApp extends StatefulWidget {
  @override
  _MyNotesAppState createState() => _MyNotesAppState();
}

class _MyNotesAppState extends State<MyNotesApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDark') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = _themeMode == ThemeMode.dark;
    await prefs.setBool('isDark', !isDark);
    setState(() {
      _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '华章日新',
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      themeMode: _themeMode,
      home: NotesListPage(toggleTheme: _toggleTheme, isDark: _themeMode == ThemeMode.dark),
    );
  }
}

class Note {
  String id;
  String title;
  String content;
  DateTime updatedAt;
  List<String> tags;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.tags = const [],
  });
}

// ------------------------------------------------
// 主列表页
// ------------------------------------------------
class NotesListPage extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDark;

  const NotesListPage({Key? key, required this.toggleTheme, required this.isDark}) : super(key: key);

  @override
  _NotesListPageState createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  List<Note> _notes = [];
  List<Note> _filteredNotes = [];
  String? _storagePath;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initStorage();
    _searchController.addListener(_filterNotes);
  }

  Future<void> _initStorage() async {
    final dir = await getApplicationDocumentsDirectory();
    final notesDir = Directory('${dir.path}/MetaslipNotes');
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }
    _storagePath = notesDir.path;
    await _loadNotes();
  }

  Future<void> _loadNotes() async {
    if (_storagePath == null) return;
    final dir = Directory(_storagePath!);
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'));
    List<Note> loaded = [];
    for (var file in files) {
      final content = await file.readAsString();
      final title = file.uri.pathSegments.last.replaceAll('.md', '');
      loaded.add(Note(
        id: file.path,
        title: title,
        content: content,
        updatedAt: await file.lastModified(),
        tags: _extractTags(content),
      ));
    }
    loaded.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() {
      _notes = loaded;
      _filteredNotes = loaded;
    });
  }

  List<String> _extractTags(String content) {
    final regex = RegExp(r'(?<=\s|^)#([^\s#]+)');
    return regex.allMatches(content).map((m) => m.group(1)!).toList();
  }

  void _filterNotes() {
    final rawQuery = _searchController.text.toLowerCase();
    setState(() {
      _searchQuery = rawQuery;
      if (rawQuery.isEmpty) {
        _filteredNotes = _notes;
      } else {
        final keywords = rawQuery.split(' ').where((k) => k.isNotEmpty).toList();
        _filteredNotes = _notes.where((n) {
          final lowerTitle = n.title.toLowerCase();
          final lowerContent = n.content.toLowerCase();
          return keywords.any((k) => lowerTitle.contains(k) || lowerContent.contains(k));
        }).toList();
      }
    });
  }

  String _getMatchingParagraph(String content, String query) {
    if (query.isEmpty) return '';
    final keywords = query.split(' ').where((k) => k.isNotEmpty).toList();
    final paragraphs = content.split('\n');
    for (final p in paragraphs) {
      final lower = p.toLowerCase();
      if (keywords.any((k) => lower.contains(k))) {
        return p.length > 150 ? p.substring(0, 150) + '...' : p;
      }
    }
    return '';
  }

  Widget _buildHighlightedSelectableText(String text, String query) {
    if (query.isEmpty) {
      return SelectableText(text, maxLines: 2, style: TextStyle(fontSize: 14));
    }
    final lowerText = text.toLowerCase();
    final keywords = query.split(' ').where((k) => k.isNotEmpty).toList();
    final spans = <TextSpan>[];
    int currentIndex = 0;

    while (currentIndex < text.length) {
      int? earliestIndex;
      String? earliestKeyword;
      for (final k in keywords) {
        final idx = lowerText.indexOf(k, currentIndex);
        if (idx != -1) {
          if (earliestIndex == null || idx < earliestIndex) {
            earliestIndex = idx;
            earliestKeyword = k;
          }
        }
      }
      if (earliestIndex == null) {
        spans.add(TextSpan(text: text.substring(currentIndex)));
        break;
      }
      if (earliestIndex > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, earliestIndex)));
      }
      spans.add(TextSpan(
        text: text.substring(earliestIndex, earliestIndex + earliestKeyword!.length),
        style: TextStyle(backgroundColor: Colors.yellowAccent, color: Colors.black, fontSize: 14),
      ));
      currentIndex = earliestIndex + earliestKeyword.length;
    }

    return SelectableText.rich(
      TextSpan(style: TextStyle(fontSize: 14), children: spans),
      maxLines: 2,
    );
  }

  Future<void> _addNote() async {
    if (_storagePath == null) return;
    final title = '新笔记 ${_notes.length + 1}';
    final file = File('$_storagePath/$title.md');
    await file.writeAsString('');
    final note = Note(
      id: file.path,
      title: title,
      content: '',
      updatedAt: DateTime.now(),
    );

    setState(() {
      _notes.add(note);
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _filteredNotes = List.from(_notes);
    });

    final editedNote = await Navigator.push<Note>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditPage(
          note: note,
          allNotes: _notes,
          initialPreview: false,
        ),
      ),
    );

    if (editedNote != null) {
      _updateNoteAfterEdit(editedNote);
    }
  }

  Future<void> _updateNoteAfterEdit(Note updatedNote) async {
    final file = File(updatedNote.id);
    if (await file.exists()) {
      setState(() {
        final index = _notes.indexWhere((n) => n.id == updatedNote.id);
        if (index != -1) {
          _notes[index].title = updatedNote.title;
          _notes[index].content = updatedNote.content;
          _notes[index].updatedAt = updatedNote.updatedAt;
          _notes[index].tags = updatedNote.tags;
          _notes[index].id = updatedNote.id;
        }
        _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _filterNotes();
      });
    }
  }

  Future<void> _deleteNote(Note note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除笔记'),
        content: Text('确定要删除“${note.title}”吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final file = File(note.id);
    if (await file.exists()) {
      await file.delete();
    }

    setState(() {
      _notes.removeWhere((n) => n.id == note.id);
      _filterNotes();
    });
  }

  Future<void> _exportNotes() async {
    if (_notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('没有笔记可导出')));
      return;
    }
    final exportDir = _storagePath;
    if (exportDir == null) return;

    final selectedDir = await getDirectoryPath();
    if (selectedDir == null) return;

    final encoder = ZipEncoder();
    final archive = Archive();
    final dir = Directory(exportDir);
    for (var file in dir.listSync().whereType<File>()) {
      final bytes = file.readAsBytesSync();
      archive.addFile(ArchiveFile(file.uri.pathSegments.last, bytes.length, bytes));
    }
    final zipData = encoder.encode(archive);
    if (zipData == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打包失败')));
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = '$selectedDir/华章日新备份_$timestamp.zip';
    await File(zipPath).writeAsBytes(zipData);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出成功：$zipPath')));
  }

  Future<void> _importNotes() async {
    if (_storagePath == null) return;

    final typeGroup = XTypeGroup(label: 'ZIP 压缩文件', extensions: ['zip']);
    final fileSelected = await openFile(acceptedTypeGroups: [typeGroup]);
    if (fileSelected == null) return;
    final zipPath = fileSelected.path;

    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final destDir = Directory(_storagePath!);
    for (var file in archive) {
      if (file.isFile && file.name.endsWith('.md')) {
        String fileName = file.name;
        String destPath = '${destDir.path}/$fileName';

        if (File(destPath).existsSync()) {
          int counter = 1;
          final baseName = fileName.replaceAll('.md', '');
          while (true) {
            final newName = '$baseName($counter).md';
            destPath = '${destDir.path}/$newName';
            if (!File(destPath).existsSync()) break;
            counter++;
          }
        }
        await File(destPath).writeAsBytes(file.content as List<int>);
      }
    }
    await _loadNotes();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入成功')));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('华章日新'),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: '切换主题',
            onPressed: widget.toggleTheme,
          ),
          IconButton(
            icon: Icon(Icons.hub),
            tooltip: '知识图谱',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SimpleGraphPage(notes: _notes)));
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') _exportNotes();
              if (value == 'import') _importNotes();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'export', child: Text('导出备份')),
              PopupMenuItem(value: 'import', child: Text('导入笔记')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索笔记标题或内容...',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterNotes();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
            ),
          ),
          Expanded(
            child: _filteredNotes.isEmpty
                ? Center(child: Text('还没有笔记，点击右下角加号创建'))
                : ListView.builder(
                    itemCount: _filteredNotes.length,
                    itemBuilder: (context, index) {
                      final note = _filteredNotes[index];
                      final showSnippet = _searchQuery.isNotEmpty;
                      final snippet = showSnippet ? _getMatchingParagraph(note.content, _searchQuery) : '';
                      return GestureDetector(
                        onSecondaryTapUp: (details) => _deleteNote(note),
                        child: ListTile(
                          title: showSnippet
                              ? _buildHighlightedSelectableText(note.title, _searchQuery)
                              : Text(note.title, style: TextStyle(fontSize: 14)),
                          subtitle: showSnippet && snippet.isNotEmpty
                              ? _buildHighlightedSelectableText(snippet, _searchQuery)
                              : Text(note.updatedAt.toString().substring(0, 16), style: TextStyle(fontSize: 12)),
                          onTap: () async {
                            final editedNote = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NoteEditPage(note: note, allNotes: _notes),
                              ),
                            );
                            if (editedNote != null) {
                              _updateNoteAfterEdit(editedNote as Note);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNote,
        child: Icon(Icons.add),
      ),
    );
  }
}

// ------------------------------------------------
// 笔记详情页（预览/编辑）增强版
// ------------------------------------------------
class NoteEditPage extends StatefulWidget {
  final Note note;
  final List<Note> allNotes;
  final bool initialPreview;

  const NoteEditPage({
    Key? key,
    required this.note,
    required this.allNotes,
    this.initialPreview = true,
  }) : super(key: key);

  @override
  _NoteEditPageState createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagsController;
  bool _hasChanged = false;
  bool _showLinkSearch = false;
  List<Note> _searchResults = [];
  final FocusNode _contentFocus = FocusNode();
  late bool _showPreview;
  bool _isSaving = false;

  double _backlinkPanelWidth = 200;
  bool _showBacklinks = true;

  final FocusNode _titleFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = TextEditingController(text: widget.note.content);
    _tagsController = TextEditingController(text: widget.note.tags.join(' '));
    _showPreview = widget.initialPreview;
    _titleController.addListener(_onChanged);
    _contentController.addListener(_onContentChanged);   // 修复：恢复双向链接监听
    _tagsController.addListener(_onChanged);

    _titleFocusNode.addListener(() {
      if (_titleFocusNode.hasFocus) {
        final current = _titleController.text;
        if (RegExp(r'^々\d+$').hasMatch(current)) {
          _titleController.clear();
          setState(() => _hasChanged = true);
        }
      }
    });
  }

  void _onChanged() {
    if (!_hasChanged) setState(() => _hasChanged = true);
  }

  void _onContentChanged() {
    _onChanged();
    final text = _contentController.text;
    final selection = _contentController.selection;
    if (selection.isValid && selection.start >= 2) {
      final cursorPos = selection.start;
      final beforeCursor = text.substring(0, cursorPos);
      if (beforeCursor.endsWith('[[')) {
        setState(() {
          _showLinkSearch = true;
          _searchResults = [];
        });
        _updateSearchResults('');
        return;
      }
    }
    if (_showLinkSearch) {
      final cursorPos = selection.start;
      final lastIndex = text.lastIndexOf('[[', cursorPos);
      if (lastIndex != -1) {
        final query = text.substring(lastIndex + 2, cursorPos);
        _updateSearchResults(query);
      }
    }
  }

  void _updateSearchResults(String query) {
    final filtered = widget.allNotes
        .where((n) => n.title.toLowerCase().contains(query.toLowerCase()) && n.id != widget.note.id)
        .toList();
    setState(() => _searchResults = filtered);
  }

  void _insertLink(Note target) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    if (!selection.isValid) return;
    final cursorPos = selection.start;
    final lastIndex = text.lastIndexOf('[[', cursorPos);
    if (lastIndex == -1) return;
    final before = text.substring(0, lastIndex);
    final after = text.substring(cursorPos);
    final linkText = '[${target.title}](${target.title}.md)';
    final newText = '$before$linkText$after';
    _contentController.text = newText;
    final newCursorPos = lastIndex + linkText.length;
    _contentController.selection = TextSelection.fromPosition(TextPosition(offset: newCursorPos));
    setState(() {
      _showLinkSearch = false;
      _searchResults = [];
      _hasChanged = true;
    });
  }

  List<Note> _getBacklinks() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return [];
    final linkPattern = '$title.md';
    return widget.allNotes.where((n) => n.id != widget.note.id && n.content.contains(linkPattern)).toList();
  }

  List<Note> _getOutgoingLinks() {
    final regex = RegExp(r'\[([^\]]+)\]\(([^)]+\.md)\)');
    final linkedNames = <String>{};
    for (var match in regex.allMatches(_contentController.text)) {
      linkedNames.add(match.group(2)!.replaceAll('.md', ''));
    }
    return widget.allNotes.where((n) => linkedNames.contains(n.title)).toList();
  }

  Future<bool> _save() async {
    if (_isSaving) return false;
    _isSaving = true;
    try {
      final newTitle = _titleController.text.trim();
      String newContent = _contentController.text;
      if (newTitle.isEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('提示'),
            content: Text('笔记标题不能为空'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('确定'))],
          ),
        );
        return false;
      }
      if (newTitle != widget.note.title) {
        final oldFile = File(widget.note.id);
        final parentDir = oldFile.parent;
        final newFile = File('${parentDir.path}/$newTitle.md');
        if (await newFile.exists() && newFile.path != oldFile.path) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('提示'),
              content: Text('同名笔记已存在，请换一个标题'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('确定'))],
            ),
          );
          return false;
        }
        await oldFile.rename(newFile.path);
        widget.note.id = newFile.path;
      }

      final newTagsStr = _tagsController.text.trim();
      final newTags = newTagsStr.isEmpty
          ? <String>[]
          : newTagsStr.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      // 移除旧标签，追加新标签
      newContent = newContent.replaceAll(RegExp(r'\s?#[^\s#]+', multiLine: true), '');
      if (newTags.isNotEmpty) {
        final tagLine = newTags.map((t) => '#$t').join(' ');
        newContent = '$newContent\n$tagLine';
      }

      final file = File(widget.note.id);
      await file.writeAsString(newContent);
      widget.note.title = newTitle;
      widget.note.content = newContent;
      widget.note.tags = newTags;
      widget.note.updatedAt = DateTime.now();
      _hasChanged = false;
      return true;
    } finally {
      _isSaving = false;
    }
  }

  List<String> _extractTags(String content) {
    final regex = RegExp(r'(?<=\s|^)#([^\s#]+)');
    return regex.allMatches(content).map((m) => m.group(1)!).toList();
  }

  void _onLinkTap(String? href) {
    if (href == null) return;

    String fileName = href.trim();
    if (fileName.contains('/')) fileName = fileName.split('/').last;
    if (fileName.contains('\\')) fileName = fileName.split('\\').last;
    fileName = Uri.decodeComponent(fileName);
    if (!fileName.endsWith('.md')) return;

    Note? targetNote = widget.allNotes.cast<Note?>().firstWhere(
          (n) => n!.id.endsWith(fileName) || n.id.endsWith('/$fileName'),
          orElse: () => null,
        );

    if (targetNote == null) {
      final possibleTitle = fileName.replaceAll('.md', '');
      targetNote = widget.allNotes.cast<Note?>().firstWhere(
            (n) => n!.title == possibleTitle,
            orElse: () => null,
          );
    }

    if (targetNote == null) {
      final parentDir = File(widget.note.id).parent.path;
      final possiblePath = '$parentDir\\$fileName';
      final file = File(possiblePath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final title = fileName.replaceAll('.md', '');
        targetNote = Note(id: possiblePath, title: title, content: content, updatedAt: file.lastModifiedSync());
      }
    }

    if (targetNote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('笔记 "${fileName.replaceAll('.md', '')}" 不存在')),
      );
      return;
    }

    _save().then((saved) {
      if (saved) {
        Navigator.pop(context, widget.note);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NoteEditPage(note: targetNote!, allNotes: widget.allNotes)),
        );
      }
    });
  }

  void _openSearch() async {
    final selectedNote = await showSearch<Note?>(
      context: context,
      delegate: _NoteSearchDelegate(allNotes: widget.allNotes),
    );
    if (selectedNote != null) {
      final ok = await _save();
      if (!ok) return;
      if (!mounted) return;
      Navigator.pop(context, widget.note);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteEditPage(note: selectedNote, allNotes: widget.allNotes)),
      );
    }
  }

  void _showNoteInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.note.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('路径：${widget.note.id}'),
            SizedBox(height: 8),
            Text('修改时间：${widget.note.updatedAt.toString().substring(0, 19)}'),
            SizedBox(height: 8),
            Text('标签：${widget.note.tags.isEmpty ? "无" : widget.note.tags.join(", ")}'),
            SizedBox(height: 8),
            Text('内容长度：${widget.note.content.length} 字符'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('关闭'))],
      ),
    );
  }

  void _copyTitle() {
    Clipboard.setData(ClipboardData(text: widget.note.title));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('标题已复制')));
  }

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: widget.note.content));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('内容已复制')));
  }

  void _copyLink() {
    final link = '[${widget.note.title}](${widget.note.title}.md)';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('链接已复制')));
  }

  void _copyWholeNote() {
    final full = '# ${widget.note.title}\n\n${widget.note.content}';
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('整篇笔记已复制')));
  }

  Future<void> _deleteNote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除笔记'),
        content: Text('确定要删除“${widget.note.title}”吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final file = File(widget.note.id);
    if (await file.exists()) await file.delete();

    if (!mounted) return;
    Navigator.pop(context, widget.note);
  }

  Future<void> _addSubNote() async {
    final parentDir = File(widget.note.id).parent;
    final now = DateTime.now();
    final defaultTitle = '々${now.millisecondsSinceEpoch}';
    final fileName = '$defaultTitle.md';
    final newFilePath = '${parentDir.path}/$fileName';

    if (await File(newFilePath).exists()) {
      await _addSubNote();
      return;
    }

    await File(newFilePath).writeAsString('');
    final newNote = Note(id: newFilePath, title: defaultTitle, content: '', updatedAt: now);

    final editedChild = await Navigator.push<Note>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditPage(
          note: newNote,
          allNotes: widget.allNotes,
          initialPreview: false,
        ),
      ),
    );

    if (editedChild != null) {
      final child = editedChild as Note;
      widget.allNotes.add(child);
      final link = '\n[${child.title}](${child.title}.md)';
      _contentController.text += link;
      _hasChanged = true;
      await _save();
    }
  }

  void _showSubNotes() {
    final outLinks = _getOutgoingLinks();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('子笔记（本文链接到的笔记）', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            if (outLinks.isEmpty)
              Text('暂无子笔记')
            else
              ...outLinks.map((n) => ListTile(
                    title: Text(n.title),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await _save();
                      if (ok) {
                        Navigator.pop(context, widget.note);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => NoteEditPage(note: n, allNotes: widget.allNotes)),
                        );
                      }
                    },
                  )),
          ],
        ),
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _viewTagNotes(String tag) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TagNotesPage(tag: tag, allNotes: widget.allNotes)),
    );
  }

  Widget _buildMetaInfo() {
    final timeStr = widget.note.updatedAt.toString().substring(0, 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagsController,
                decoration: InputDecoration(
                  hintText: '标签（空格分隔）',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                style: TextStyle(fontSize: 13, color: Colors.blueGrey),
              ),
            ),
            IconButton(
              icon: Icon(Icons.search, size: 18),
              tooltip: '查看该标签下的笔记',
              onPressed: () {
                final tags = _tagsController.text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
                if (tags.isNotEmpty) {
                  _viewTagNotes(tags.first);
                }
              },
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(timeStr, style: TextStyle(fontSize: 13, color: Colors.grey)),
        Divider(height: 16),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    _contentFocus.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backlinks = _getBacklinks();
    final showBacklinks = backlinks.isNotEmpty && _showBacklinks;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note.title),
        actions: [
          IconButton(icon: Icon(Icons.home), tooltip: '主页', onPressed: _goHome),
          IconButton(icon: Icon(Icons.subdirectory_arrow_right), tooltip: '子笔记', onPressed: _showSubNotes),
          IconButton(icon: Icon(Icons.note_add), tooltip: '新增子笔记', onPressed: _addSubNote),
          IconButton(icon: Icon(Icons.search), tooltip: '搜索', onPressed: _openSearch),
          IconButton(
            icon: Icon(_showPreview ? Icons.edit : Icons.visibility),
            tooltip: _showPreview ? '编辑' : '预览',
            onPressed: () => setState(() => _showPreview = !_showPreview),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'info': _showNoteInfo(); break;
                case 'copyTitle': _copyTitle(); break;
                case 'copyContent': _copyContent(); break;
                case 'copyLink': _copyLink(); break;
                case 'copyAll': _copyWholeNote(); break;
                case 'delete': _deleteNote(); break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'info', child: Text('笔记信息')),
              PopupMenuItem(value: 'copyTitle', child: Text('复制标题')),
              PopupMenuItem(value: 'copyContent', child: Text('复制内容')),
              PopupMenuItem(value: 'copyLink', child: Text('复制链接')),
              PopupMenuItem(value: 'copyAll', child: Text('复制整篇笔记')),
              PopupMenuItem(value: 'delete', child: Text('删除笔记', style: TextStyle(color: Colors.red))),
            ],
          ),
          if (!_showPreview)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton.icon(
                icon: Icon(Icons.save, size: 18),
                label: Text('保存'),
                onPressed: _hasChanged
                    ? () async {
                        final ok = await _save();
                        if (ok) Navigator.pop(context, widget.note);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blueGrey,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_showPreview) ...[
                        Text(widget.note.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: widget.note.tags.map((tag) => GestureDetector(
                            onTap: () => _viewTagNotes(tag),
                            child: Chip(label: Text('#$tag', style: TextStyle(fontSize: 12))),
                          )).toList(),
                        ),
                        if (widget.note.tags.isEmpty) Text('无标签', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        SizedBox(height: 4),
                        Text(widget.note.updatedAt.toString().substring(0, 16), style: TextStyle(fontSize: 13, color: Colors.grey)),
                        Divider(height: 24),
                      ] else ...[
                        TextField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          decoration: InputDecoration(labelText: '标题', border: OutlineInputBorder()),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        _buildMetaInfo(),
                        SizedBox(height: 8),
                      ],
                      Expanded(
                        child: _showPreview
                            ? SingleChildScrollView(
                                child: MarkdownBody(
                                  data: _contentController.text,
                                  selectable: true,
                                  onTapLink: (text, href, title) => _onLinkTap(href),
                                ),
                              )
                            : TextField(
                                controller: _contentController,
                                focusNode: _contentFocus,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                  hintText: '在此输入 Markdown 内容... 输入 [[ 可创建链接，使用 #标签',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showBacklinks)
                _BacklinkPanel(
                  backlinks: backlinks,
                  width: _backlinkPanelWidth,
                  onWidthChanged: (newWidth) {
                    setState(() => _backlinkPanelWidth = newWidth.clamp(100.0, 400.0));
                  },
                  onClose: () => setState(() => _showBacklinks = false),
                  onNoteTap: (note) async {
                    final ok = await _save();
                    if (ok) {
                      Navigator.pop(context, widget.note);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NoteEditPage(note: note, allNotes: widget.allNotes)),
                      );
                    }
                  },
                ),
            ],
          ),
          if (_showLinkSearch)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                constraints: BoxConstraints(maxHeight: 200),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      title: TextField(
                        autofocus: true,
                        decoration: InputDecoration(hintText: '搜索并选择笔记...', border: InputBorder.none),
                        onChanged: (value) => _updateSearchResults(value),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => setState(() => _showLinkSearch = false),
                      ),
                    ),
                    Divider(height: 1),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final note = _searchResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(note.title),
                            onTap: () => _insertLink(note),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: backlinks.isNotEmpty && !_showBacklinks
          ? FloatingActionButton.small(
              onPressed: () => setState(() => _showBacklinks = true),
              tooltip: '显示反向链接',
              child: Icon(Icons.link),
            )
          : null,
    );
  }
}

// 标签笔记列表页
class TagNotesPage extends StatelessWidget {
  final String tag;
  final List<Note> allNotes;

  const TagNotesPage({Key? key, required this.tag, required this.allNotes}) : super(key: key);

  List<Note> get filteredNotes => allNotes.where((n) => n.tags.contains(tag)).toList();

  @override
  Widget build(BuildContext context) {
    final notes = filteredNotes;
    return Scaffold(
      appBar: AppBar(title: Text('#$tag 笔记')),
      body: notes.isEmpty
          ? Center(child: Text('没有包含此标签的笔记'))
          : ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return ListTile(
                  title: Text(note.title),
                  subtitle: Text(note.updatedAt.toString().substring(0, 16)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoteEditPage(note: note, allNotes: allNotes),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// 自定义全屏搜索
class _NoteSearchDelegate extends SearchDelegate<Note?> {
  final List<Note> allNotes;

  _NoteSearchDelegate({required this.allNotes});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: Icon(Icons.clear), onPressed: () => query = ''),
      TextButton(
        onPressed: () => close(context, null),
        child: Text('返回', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(icon: Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  String _getMatchingParagraph(String content, String query) {
    if (query.isEmpty) return content.length > 150 ? content.substring(0, 150) + '...' : content;
    final keywords = query.split(' ').where((k) => k.isNotEmpty).toList();
    final paragraphs = content.split('\n');
    for (final p in paragraphs) {
      final lower = p.toLowerCase();
      if (keywords.any((k) => lower.contains(k))) {
        return p.length > 150 ? p.substring(0, 150) + '...' : p;
      }
    }
    return '';
  }

  Widget _buildHighlightedSelectableText(String text, String query) {
    if (query.isEmpty) {
      return SelectableText(text, maxLines: 2, style: TextStyle(fontSize: 14));
    }
    final lowerText = text.toLowerCase();
    final keywords = query.split(' ').where((k) => k.isNotEmpty).toList();
    final spans = <TextSpan>[];
    int currentIndex = 0;

    while (currentIndex < text.length) {
      int? earliestIndex;
      String? earliestKeyword;
      for (final k in keywords) {
        final idx = lowerText.indexOf(k, currentIndex);
        if (idx != -1) {
          if (earliestIndex == null || idx < earliestIndex) {
            earliestIndex = idx;
            earliestKeyword = k;
          }
        }
      }
      if (earliestIndex == null) {
        spans.add(TextSpan(text: text.substring(currentIndex)));
        break;
      }
      if (earliestIndex > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, earliestIndex)));
      }
      spans.add(TextSpan(
        text: text.substring(earliestIndex, earliestIndex + earliestKeyword!.length),
        style: TextStyle(backgroundColor: Colors.yellowAccent, color: Colors.black, fontSize: 14),
      ));
      currentIndex = earliestIndex + earliestKeyword.length;
    }

    return SelectableText.rich(
      TextSpan(style: TextStyle(fontSize: 14), children: spans),
      maxLines: 2,
    );
  }

  Widget _buildList(BuildContext context) {
    final results = query.isEmpty
        ? allNotes
        : (() {
            final keywords = query.toLowerCase().split(' ').where((k) => k.isNotEmpty).toList();
            if (keywords.isEmpty) return allNotes;
            return allNotes.where((n) {
              final lowerTitle = n.title.toLowerCase();
              final lowerContent = n.content.toLowerCase();
              return keywords.any((k) => lowerTitle.contains(k) || lowerContent.contains(k));
            }).toList();
          })();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final note = results[index];
        final snippet = _getMatchingParagraph(note.content, query);
        return ListTile(
          title: _buildHighlightedSelectableText(note.title, query),
          subtitle: snippet.isNotEmpty ? _buildHighlightedSelectableText(snippet, query) : null,
          onTap: () => close(context, note),
        );
      },
    );
  }
}

// 可拖动宽度的反向链接面板
class _BacklinkPanel extends StatefulWidget {
  final List<Note> backlinks;
  final double width;
  final ValueChanged<double> onWidthChanged;
  final VoidCallback onClose;
  final ValueChanged<Note> onNoteTap;

  const _BacklinkPanel({
    required this.backlinks,
    required this.width,
    required this.onWidthChanged,
    required this.onClose,
    required this.onNoteTap,
  });

  @override
  __BacklinkPanelState createState() => __BacklinkPanelState();
}

class __BacklinkPanelState extends State<_BacklinkPanel> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      child: Row(
        children: [
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              widget.onWidthChanged(widget.width - details.delta.dx);
            },
            child: Container(
              width: 6,
              color: Theme.of(context).dividerColor,
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          Expanded(
            child: Container(
              color: Theme.of(context).cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('反向链接', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      IconButton(icon: Icon(Icons.close, size: 18), onPressed: widget.onClose),
                    ],
                  ),
                  Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.backlinks.length,
                      itemBuilder: (context, index) {
                        final note = widget.backlinks[index];
                        return ListTile(
                          dense: true,
                          title: Text(note.title, style: TextStyle(fontSize: 14)),
                          onTap: () => widget.onNoteTap(note),
                        );
                      },
                    ),
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

// ------------------------------------------------
// 知识图谱页面
// ------------------------------------------------
class SimpleGraphPage extends StatefulWidget {
  final List<Note> notes;
  const SimpleGraphPage({Key? key, required this.notes}) : super(key: key);
  @override
  _SimpleGraphPageState createState() => _SimpleGraphPageState();
}

class _SimpleGraphPageState extends State<SimpleGraphPage> {
  String? _selectedTag;

  Map<String, List<String>> _buildLinks(List<Note> notes) {
    final links = <String, List<String>>{};
    final linkRegExp = RegExp(r'\[([^\]]+)\]\(([^)]+\.md)\)');
    for (var note in notes) {
      final matches = linkRegExp.allMatches(note.content);
      for (var match in matches) {
        final linkedTitle = match.group(2)!.replaceAll('.md', '');
        final targetNote = notes.cast<Note?>().firstWhere(
              (n) => n!.title == linkedTitle,
              orElse: () => null,
            );
        if (targetNote != null && targetNote.id != note.id) {
          links.putIfAbsent(note.id, () => []).add(targetNote.id);
        }
      }
    }
    return links;
  }

  List<Offset> _calculatePositions(Size size, int count) {
    if (count == 0) return [];
    if (count == 1) return [Offset(size.width / 2, size.height / 2)];
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.4;
    final positions = <Offset>[];
    for (int i = 0; i < count; i++) {
      final angle = (2 * pi * i / count) - pi / 2;
      positions.add(Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle)));
    }
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _selectedTag == null
        ? widget.notes
        : widget.notes.where((n) => n.tags.contains(_selectedTag)).toList();
    final links = _buildLinks(filteredNotes);
    final allTags = widget.notes.expand((n) => n.tags).toSet().toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('知识图谱'),
        actions: [
          if (_selectedTag != null)
            TextButton(
              onPressed: () => setState(() => _selectedTag = null),
              child: Text('清除筛选', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (allTags.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '在笔记内容中输入 #标签名 即可创建标签，点击下面标签可筛选节点',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                textAlign: TextAlign.center,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.all(8),
              child: Row(
                children: allTags.map((tag) {
                  final isSelected = tag == _selectedTag;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text('#$tag'),
                      selected: isSelected,
                      onSelected: (selected) => setState(() => _selectedTag = selected ? tag : null),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final positions = _calculatePositions(size, filteredNotes.length);
                final nodeIdToPosition = <String, Offset>{};
                for (int i = 0; i < filteredNotes.length; i++) {
                  nodeIdToPosition[filteredNotes[i].id] = positions[i];
                }
                return InteractiveViewer(
                  constrained: false,
                  boundaryMargin: EdgeInsets.all(200),
                  minScale: 0.2,
                  maxScale: 4.0,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: GraphEdgePainter(links: links, nodeIdToPosition: nodeIdToPosition),
                          ),
                        ),
                        ...filteredNotes.map((note) {
                          final pos = nodeIdToPosition[note.id] ?? Offset.zero;
                          return Positioned(
                            left: pos.dx - 50,
                            top: pos.dy - 20,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NoteEditPage(note: note, allNotes: widget.notes),
                                  ),
                                );
                              },
                              child: Container(
                                width: 100,
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blueGrey),
                                ),
                                child: Text(
                                  note.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class GraphEdgePainter extends CustomPainter {
  final Map<String, List<String>> links;
  final Map<String, Offset> nodeIdToPosition;

  GraphEdgePainter({required this.links, required this.nodeIdToPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey.withOpacity(0.6)
      ..strokeWidth = 1.5;
    links.forEach((sourceId, targets) {
      final sourcePos = nodeIdToPosition[sourceId];
      if (sourcePos == null) return;
      for (var targetId in targets) {
        final targetPos = nodeIdToPosition[targetId];
        if (targetPos == null) continue;
        canvas.drawLine(sourcePos, targetPos, paint);
      }
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}