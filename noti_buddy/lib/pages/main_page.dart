import 'package:flutter/material.dart';
import 'package:noti_buddy/managers/app_manager.dart';
import 'package:noti_buddy/managers/notification_manager.dart';
import 'package:noti_buddy/widgets/notification_list.dart';

import 'create_notification_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    super.initState();

    NotificationManager.instance.requestAndroid13Permissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Noti Buddy'),
        actions: [
          IconButton(
            onPressed: () async {
              AppManager.instance.printItems();
              setState(() {});
              AppManager.instance.printItems();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () async {
              NotificationManager.instance
                  .scheduleNotification(AppManager.instance.itemAt(0));
            },
            icon: const Icon(Icons.notifications),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: AppManager.instance.notifier,
        builder: (context, value, child) {
          return NotificationList(
            items: value,
            onRefresh: () => setState(() {}),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => const CreateNotificationPage(),
                ),
              )
              .then((value) => setState(() {})); // Refresh the list
        },
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
    );
  }
}
