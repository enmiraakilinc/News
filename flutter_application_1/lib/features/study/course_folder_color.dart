import 'package:flutter/material.dart';
import '../../core/utils/user_errors.dart';
import 'course_repository.dart';

const courseFolderColors = <String, Color>{
  'Mavi': Color(0xFF4285F4),
  'Kırmızı': Color(0xFFE85D5D),
  'Sarı': Color(0xFFF2C94C),
  'Yeşil': Color(0xFF45B77A),
  'Mor': Color(0xFFAF7AE8),
  'Turuncu': Color(0xFFF2994A),
};

class CourseFolderColorButton extends StatelessWidget {
  final CourseRepository repository;
  final LessonFolder folder;
  final VoidCallback onChanged;
  final bool enabled;
  const CourseFolderColorButton({
    super.key,
    required this.repository,
    required this.folder,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Klasör rengini değiştir',
    icon: Icon(Icons.palette_outlined, color: courseFolderColors[folder.color]),
    onPressed: !enabled
        ? null
        : () async {
            final choice = await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Klasör rengi'),
                children: [
                  for (final entry in courseFolderColors.entries)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, entry.key),
                      child: Row(
                        children: [
                          Icon(Icons.folder, color: entry.value),
                          const SizedBox(width: 12),
                          Text(entry.key),
                          if (folder.color == entry.key)
                            const Padding(
                              padding: EdgeInsets.only(left: 12),
                              child: Icon(Icons.check),
                            ),
                        ],
                      ),
                    ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: const Text('Tema rengi'),
                  ),
                ],
              ),
            );
            if (choice == null) return;
            try {
              await repository.colorFolder(
                folder.id,
                choice.isEmpty ? null : choice,
              );
              if (context.mounted) onChanged();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(userError(error))));
              }
            }
          },
  );
}
