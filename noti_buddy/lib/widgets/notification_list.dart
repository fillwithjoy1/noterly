import 'package:flutter/material.dart';
import 'package:noti_buddy/models/notification_item.dart';

class NotificationList extends StatelessWidget {
  final List<NotificationItem> items;

  const NotificationList({
    required this.items,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return ListTile(
          title: Text(item.title),
          subtitle: item.body != null ? Text(item.body!) : null,
          trailing: item.dateTime != null ? Text('${item.dateTime}') : null,
          leading: SizedBox(
            width: 8,
            child: CircleAvatar(
              backgroundColor: item.colour,
            ),
          ),
        );
      },
    );
  }
}
