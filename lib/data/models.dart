/// pdf = imported document, note = handwritten note, audio = recording.
enum ItemType { pdf, note, audio }

class Module {
  final int id;
  final String name;
  final int color;
  final DateTime created;
  final int itemCount;

  const Module({
    required this.id,
    required this.name,
    required this.color,
    required this.created,
    this.itemCount = 0,
  });

  factory Module.fromMap(Map<String, Object?> m) => Module(
        id: m['id'] as int,
        name: m['name'] as String,
        color: m['color'] as int,
        created: DateTime.fromMillisecondsSinceEpoch(m['created'] as int),
        itemCount: (m['item_count'] as int?) ?? 0,
      );
}

class StudyItem {
  final int id;
  final int moduleId;
  final ItemType type;
  final String title;

  /// PDFs: file name in docs/. Recordings: file name in recordings/.
  final String? fileName;

  /// Notes: number of pages. Recordings: length in seconds.
  final int pageCount;
  final DateTime updated;

  const StudyItem({
    required this.id,
    required this.moduleId,
    required this.type,
    required this.title,
    required this.fileName,
    required this.pageCount,
    required this.updated,
  });

  factory StudyItem.fromMap(Map<String, Object?> m) => StudyItem(
        id: m['id'] as int,
        moduleId: m['module_id'] as int,
        type: ItemType.values.byName(m['type'] as String),
        title: m['title'] as String,
        fileName: m['file_path'] as String?,
        pageCount: m['page_count'] as int,
        updated: DateTime.fromMillisecondsSinceEpoch(m['updated'] as int),
      );
}

/// A document/note/recording plus the module it belongs to (for pickers).
class ItemWithModule {
  final StudyItem item;
  final String moduleName;
  final int moduleColor;
  const ItemWithModule(this.item, this.moduleName, this.moduleColor);
}
