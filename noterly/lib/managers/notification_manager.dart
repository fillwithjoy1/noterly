import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:noterly/managers/app_manager.dart';
import 'package:noterly/managers/isolate_manager.dart';
import 'package:noterly/managers/log.dart';
import 'package:noterly/models/notification_item.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  static NotificationManager get instance => _instance;
  NotificationManager._internal() {
    init();
  }

  final _plugin = FlutterLocalNotificationsPlugin();

  void init() async {
    Log.logger.d('Initialising notification manager...');

    tz.initializeTimeZones();

    const initializationSettingsAndroid = AndroidInitializationSettings('notification_icon_48');
    const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
    );
  }

  static Future handleResponse(NotificationResponse response, {bool isBackground = false}) async {
    Log.logger.d('Handling notification response. ${isBackground ? 'Background' : 'Foreground'} mode. Action: "${response.actionId}". Payload: "${response.payload}"');

    var itemId = response.payload;
    if (itemId == null) {
      Log.logger.d('No payload, ignoring');
      return;
    }

    if (isBackground) {
      await AppManager.instance.ensureInitialised();
    }

    var item = AppManager.instance.getItem(itemId);
    if (item == null) {
      Log.logger.d('No item found for payload, requesting a full update and retrying...');
      await AppManager.instance.fullUpdate();
      item = AppManager.instance.getItem(itemId);
      if (item == null) {
        Log.logger.d('Still no item found for payload, ignoring');
        return;
      }
    }

    if (response.actionId == 'done') {
      if (item.repeatDuration != null) {
        Log.logger.d('Snoozing notification "${item.title}"');
        await NotificationManager.instance.updateRepeatingNotification(item);
      } else {
        Log.logger.d('Archiving notification "${item.title}"');
        await AppManager.instance.archiveItem(item.id, deferNotificationManagerCall: true);
      }

      // If we're in the background, we need to send a message to the main isolate to update the UI
      if (isBackground) {
        var sendPort = IsolateNameServer.lookupPortByName(IsolateManager.mainPortName);
        sendPort?.send('update');
        if (sendPort == null) {
          Log.logger.e('Failed to send message to main isolate (port not found).');
        }
      }

      return;
    }

    if (!isBackground) {
      // TODO: Open the item
      Log.logger.d('Opening notification "${item.title}"');
    }
  }

  static Future onResponse(NotificationResponse response) async => handleResponse(response, isBackground: false);

  @pragma('vm:entry-point')
  static Future onBackgroundResponse(NotificationResponse response) async => handleResponse(response, isBackground: true);

  Future requestAndroid13Permissions() async {
    try {
      var android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (android != null) {
        var result = await android.requestPermission();
        Log.logger.d('Got A13 permission result: $result');
      }
    } catch (e) {
      Log.logger.e('Failed to request A13 notification permission, $e');
    }
  }

  Future _cancelAllNotifications() async => await _plugin.cancelAll();

  Future cancelNotification(String itemId) async => await _plugin.cancel(itemId.hashCode);

  Future<bool> _notificationIsShown(NotificationItem item) async {
    var notifications = await _plugin.getActiveNotifications();
    return notifications.any((n) => n.id == item.id.hashCode);
  }

  Future updateAllNotifications() async {
    for (var item in AppManager.instance.notifier.value) {
      if (item.archived) continue;

      if (item.repeatDuration != null) {
        await updateRepeatingNotification(item);
      } else {
        await updateNotification(item);
      }
    }
  }

  Future forceUpdateAllNotifications() async {
    await _cancelAllNotifications(); // Cancel all existing notifications; faster than checking each one

    for (var item in AppManager.instance.notifier.value) {
      if (item.archived) continue;

      // TODO: also update repeating notifications
      if (item.repeatDuration != null) continue;

      await _showOrScheduleNotification(item);
    }
  }

  Future updateNotification(NotificationItem item) async {
    if (await _notificationIsShown(item)) {
      return; // Notification is already shown, no need to show another
    }

    if (item.archived) return;
    await _showOrScheduleNotification(item);
  }

  Future forceUpdateNotification(NotificationItem item) async {
    // Cancel the existing notification, if any
    await _plugin.cancel(item.id.hashCode);

    if (item.archived) return;
    await _showOrScheduleNotification(item);
  }

  Future updateAllRepeatingNotifications() async {
    for (var item in AppManager.instance.notifier.value) {
      if (item.archived) continue;
      if (item.repeatDuration != null) continue;

      await updateRepeatingNotification(item);
    }
  }

  Future updateRepeatingNotification(NotificationItem item) async {
    if (item.archived) return;
    if (item.repeatDuration == null) return;

    var isShown = await _notificationIsShown(item);

    if (item.dateTime != null) {
      // Scheduled: check if repeat duration has passed
      var now = DateTime.now();
      var diff = now.difference(item.dateTime!);
      if (diff.inSeconds < item.repeatDuration!.inSeconds) {
        // Repeat duration has not passed, no need to update
        if (isShown) return;
      }

      // Repeat duration has passed, update the dateTime and schedule the notification
      item.dateTime = item.dateTime!.add(item.repeatDuration!);
      await AppManager.instance.editItem(item, deferNotificationManagerCall: true);
      await _scheduleNotification(item);

      print('Updated notification "${item.title}", new dateTime: ${item.dateTime}');
    } else {
      // TODO: come up with a way to handle this case, or force all repeating notifications to have a dateTime
      Log.logger.e('Item has a repeat duration but no dateTime, ignoring!');
    }
  }

  Future _showOrScheduleNotification(NotificationItem item) async {
    if (item.dateTime == null) {
      await _showNotification(item);
    } else {
      await _scheduleNotification(item);
    }
  }

  Future _showNotification(NotificationItem item, {bool ignoreDateTime = false}) async {
    if (!ignoreDateTime) {
      assert(
        item.dateTime == null,
        'Notification must not have a dateTime in order to be shown immediately.',
      );
    }

    var androidDetails = _getNotificationDetails(item);
    var details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      item.id.hashCode,
      item.title,
      item.body,
      details,
      payload: item.id,
    );
  }

  Future _scheduleNotification(NotificationItem item) async {
    assert(
      item.dateTime != null,
      'Notification must have a dateTime in order to be scheduled.',
    );

    if (item.dateTime!.isBefore(DateTime.now())) {
      // Show notification immediately if it's in the past
      await _showNotification(item, ignoreDateTime: true);
      return;
    }

    var androidDetails = _getNotificationDetails(item);
    var details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      item.id.hashCode,
      item.title,
      item.body,
      tz.TZDateTime.from(item.dateTime!, tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: item.id,
    );
  }

  AndroidNotificationDetails _getNotificationDetails(NotificationItem item) => AndroidNotificationDetails(
        item.dateTime == null ? 'immediate_notifications' : 'scheduled_notifications',
        item.dateTime == null ? 'Immediate notifications' : 'Scheduled notifications',
        channelDescription: item.dateTime == null ? 'Notifications that are shown immediately' : 'Notifications that are scheduled for a future time',
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'done',
            'Mark as done',
          ),
        ],
        category: AndroidNotificationCategory.reminder,
        importance: Importance.max,
        priority: Priority.max,
        groupKey: 'uk.co.tdsstudios.noterly.ALL_NOTIFICATIONS_GROUP',
        color: item.colour,
        ongoing: true,
        when: item.dateTime == null ? null : item.dateTime!.millisecondsSinceEpoch,
      );
}
