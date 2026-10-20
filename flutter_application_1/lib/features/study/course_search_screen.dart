import 'package:flutter/material.dart';
import 'course_repository.dart';
import 'course_screen.dart';

class CourseSearchScreen extends StatefulWidget {
  final CourseRepository repository;
  final LessonFolder? root;
  const CourseSearchScreen({super.key, required this.repository, this.root});
  @override
  State<CourseSearchScreen> createState() => _CourseSearchScreenState();
}

class _CourseSearchScreenState extends State<CourseSearchScreen> {
  final _query = TextEditingController();
  Future<List<CourseSearchHit>>? _results;
  String _searchedQuery = '';
  void _find() {
    if (_query.text.trim().isEmpty) return;
    _searchedQuery = _query.text;
    setState(
      () => _results = widget.repository.search(_query.text, root: widget.root),
    );
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ders notlarında ara')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _query,
            autofocus: true,
            maxLength: 100,
            decoration: InputDecoration(
              hintText: 'Klasör adı, not veya kod ara',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Ara',
                onPressed: _find,
                icon: const Icon(Icons.search),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
          ),
        ),
        Expanded(
          child: _results == null
              ? const Center(child: Text('Aramak için bir kelime yaz.'))
              : FutureBuilder<List<CourseSearchHit>>(
                  future: _results,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Arama tamamlanamadı. Tekrar dene.'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final results = snapshot.data!;
                    if (results.isEmpty) {
                      return const Center(child: Text('Sonuç bulunamadı.'));
                    }
                    return ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final hit = results[index];
                        return ListTile(
                          leading: Icon(
                            hit.note == null
                                ? Icons.folder_outlined
                                : Icons.description_outlined,
                          ),
                          title: Text(hit.folder.title),
                          subtitle: hit.note == null
                              ? const Text('Klasör')
                              : Text(
                                  hit.note!.text,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CourseNotesScreen(
                                repository: widget.repository,
                                folder: hit.folder,
                                initialQuery: hit.note == null
                                    ? ''
                                    : _searchedQuery,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
