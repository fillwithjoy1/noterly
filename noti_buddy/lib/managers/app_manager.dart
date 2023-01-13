import 'package:flutter/material.dart';
import 'package:noti_buddy/managers/file_manager.dart';
import 'package:noti_buddy/managers/lifecycle_event_handler.dart';
import 'package:noti_buddy/models/app_data.dart';
import 'package:noti_buddy/models/notification_item.dart';

class AppManager {
  static final AppManager _instance = AppManager._internal();
  static AppManager get instance => _instance;
  AppManager._internal() {
    WidgetsBinding.instance.addObserver(
      LifecycleEventHandler(
        resumeCallback: () async {
          // If we're resuming, we need to reload the data from file in case an item has been deleted from a notification
          // action. In this case, a separate instance of the app will have been launched to handle the action, and the
          // data will have been saved to file. We need to reload the data from file to ensure the UI is up to date.
          print('Resuming app, reloading data from file...');
          await _load();
          printItems();
        },
      ),
    );

    _load();
  }

  final notifier = ValueNotifier<List<NotificationItem>>([]);

  var isInitialised = false;
  Future? _loadingFuture;

  Future ensureInitialised() async {
    if (isInitialised) {
      return;
    }

    return _loadingFuture;
  }

  Future _load() async {
    _loadingFuture = FileManager.load();
    var data = await _loadingFuture;

    isInitialised = true;
    _loadingFuture = null;

    if (data == null) {
      return;
    }

    notifier.value = data.notificationItems;
  }

  Future<void> _save() async {
    var data = AppData(notificationItems: notifier.value);

    await FileManager.save(data);
  }

  NotificationItem? getItem(String id) {
    var found = notifier.value.where((element) => element.id == id);
    return found.isEmpty ? null : found.first;
  }

  void addItem(NotificationItem item) {
    notifier.value.add(item);
    _save();
    _updateNotifier();
  }

  void editItem(NotificationItem item) {
    var found = notifier.value.where((element) => element.id == item.id);
    if (found.isEmpty) {
      return;
    }

    var index = notifier.value.indexOf(found.first);
    notifier.value[index] = item;
    _save();
    _updateNotifier();
  }

  void deleteItem(String id) {
    notifier.value.removeWhere((element) => element.id == id);
    _save();
    _updateNotifier();
  }

  NotificationItem itemAt(int i) => notifier.value[i];

  void fullUpdate() async {
    print('Full update requested, reloading data from file...');
    await _load();
    print('Updaing notifier...');
    _updateNotifier();
    printItems();
  }

  void _updateNotifier() {
    notifier.value = List.from(notifier.value); // Update value notifier
  }

  void printItems() {
    var output = '';
    for (var element in notifier.value) {
      output += '$element, ';
    }
    print('${notifier.value.length} item(s): [$output]');
  }
}
