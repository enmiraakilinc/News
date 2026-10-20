"""One-time path-checked source reorganization, run from workspace root."""
import json,os,re,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[2]
lib=root/'flutter_application_1/lib'
main=lib/'main.dart';source=main.read_text(encoding='utf-8')
if 'class CounterScreen' not in source:raise SystemExit('Already migrated; no changes made.')
snapshot=root/'archive/refactor/before-feature-folders'
if snapshot.exists():raise SystemExit('Backup already exists; inspect before retrying.')
for folder in ['lib','test']:
    for file in (root/'flutter_application_1'/folder).rglob('*'):
        if file.is_file():
            target=snapshot/folder/file.relative_to(root/'flutter_application_1'/folder)
            if not target.resolve().is_relative_to(root):raise RuntimeError('Backup path escaped workspace.')
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,target)
backup=root/'archive/refactor/main-before-feature-folders.dart.txt'
backup.parent.mkdir(parents=True,exist_ok=True)
if not backup.exists():backup.write_text(source,encoding='utf-8')
header=source[:source.index('final appNavigatorKey')]
runtime=source[source.index('final appNavigatorKey'):source.index('class SystemGalleryApp')]
a=runtime.index('void main() {');b=runtime.index('/// Firebase,',a);runtime=runtime[:a]+runtime[b:]
runtime=runtime.replace('_initLocalNotifications','initializeLocalNotifications').replace('_initBackground()','initializeBackground(void Function() dispatcher)').replace('Workmanager().initialize(callbackDispatcher)','Workmanager().initialize(dispatcher)').replace('void callbackDispatcher()','void runBackgroundDispatcher()')
pieces={
'app_runtime.dart':runtime,
'app_shell.dart':source[source.index('class SystemGalleryApp'):source.index('class FakeGalleryPage')],
'entry_screen.dart':source[source.index('class FakeGalleryPage'):source.index('class CounterScreen')],
'private_home.dart':source[source.index('class CounterScreen'):source.index('class DecoyHomeScreen')],
'tools_screen.dart':source[source.index('class DecoyHomeScreen'):source.index('class FullImageScreen')],
'full_image_screen.dart':source[source.index('class FullImageScreen'):],
}
extras={'app_runtime.dart':[],'app_shell.dart':['app_runtime.dart','entry_screen.dart'],'entry_screen.dart':['app_runtime.dart','private_home.dart'],'private_home.dart':['app_runtime.dart','tools_screen.dart','full_image_screen.dart'],'tools_screen.dart':['app_runtime.dart'],'full_image_screen.dart':['app_runtime.dart']}
for name,body in pieces.items():
    (lib/name).write_text(header+''.join(f"import '{i}';\n" for i in extras[name])+body.replace('_initLocalNotifications','initializeLocalNotifications'),encoding='utf-8')
main.write_text("""import 'dart:async';
import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'app_runtime.dart';
export 'app_shell.dart';
export 'app_runtime.dart';
export 'entry_screen.dart';
export 'private_home.dart';
export 'tools_screen.dart';
export 'full_image_screen.dart';
// Keep this library/name stable for existing WorkManager callback handles.
@pragma('vm:entry-point')
void callbackDispatcher() => runBackgroundDispatcher();
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SystemGalleryApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {unawaited(initializeBackground(callbackDispatcher));});
}
""",encoding='utf-8')
groups={
'app':['app_shell','app_runtime'],
'core/theme':['app_theme','chat_theme'],
'core/security':['secure_screen','feature_access'],
'core/notifications':['notif_prefs','notification_permission','incoming_call_settings'],
'core/utils':['user_errors','sync_state','refresh_stream'],
'core/widgets':['emoji_picker','date_input'],
'features/account':['chat_account','chat_account_screen'],
'features/pair':['couple_service','paired_gate','badge_service'],
'features/chat':['chat_service','chat_widgets','chat_unread','chat_downloads','letters_screen'],
'features/contacts':['contacts_screen','contact_names','contact_details_screen','shared_contact_label','profile_avatar'],
'features/media':['chat_media','message_content','media_viewer','media_names_screen','chat_audio_player','video_parts','camera_capture_screen','image_util','full_image_screen'],
'features/calls':['call_background','voice_call'],
'features/news':['news_screen','news_notes'],
'features/questions':['question_screen'],
'features/timeline':['timeline_screen'],
'features/voice_notes':['voice_notes_screen'],
'features/wishes':['wishes_screen'],
'features/counter':['counter_page'],
'features/location':['location_share','offline_location_map'],
'features/settings':['app_settings_screen'],
'features/updates':['update_service','update_dialog'],
'features/storage':['storage_monitor'],
'features/games':['sudoku_screen'],
'features/tools':['recipe_screen','tools_screen'],
'features/starred':['starred_messages'],
'features/home':['entry_screen','private_home'],
'features/startup':['startup_gate'],
'features/wakeup':['wakeup_service'],
'features/reminders':['reminder_service'],
'features/study':['course_repository','course_screen'],
}
mapping={lib/f'{name}.dart':lib/group/f'{name}.dart' for group,names in groups.items() for name in names}
pattern=re.compile(r"((?:import|export|part)\s+['\"])([^'\"]+)(['\"])")
for path in list(lib.rglob('*.dart'))+list((root/'flutter_application_1/test').rglob('*.dart')):
    destination=mapping.get(path,path)
    def replace(m):
        uri=m.group(2)
        if uri.startswith('package:flutter_application_1/'):
            original=lib/uri.split('/',1)[1];uri='package:flutter_application_1/'+mapping.get(original,original).relative_to(lib).as_posix()
        elif ':' not in uri:
            original=(path.parent/uri).resolve();target=mapping.get(original,original);uri=os.path.relpath(target,destination.parent).replace('\\','/')
        return m.group(1)+uri+m.group(3)
    path.write_text(pattern.sub(replace,path.read_text(encoding='utf-8')),encoding='utf-8')
for old,new in mapping.items():
    if not old.resolve().is_relative_to(root) or not new.resolve().is_relative_to(root):raise RuntimeError('Path escaped workspace.')
    if new.exists():raise RuntimeError('Refusing overwrite.')
    new.parent.mkdir(parents=True,exist_ok=True);old.rename(new)
(root/'tools/refactor/dart-path-migration.json').write_text(json.dumps({str(k.relative_to(root)):str(v.relative_to(root)) for k,v in mapping.items()},indent=2),encoding='utf-8')
print(f'Organized {len(mapping)} Dart files; imports and background entry point preserved.')
