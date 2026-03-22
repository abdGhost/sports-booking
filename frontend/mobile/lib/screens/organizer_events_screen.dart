import 'package:flutter/material.dart';

/// Placeholder organizer events page used from profile menu.
class OrganizerEventsScreen extends StatelessWidget {
  const OrganizerEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My events')),
      body: const Center(
        child: Text('Organizer events'),
      ),
    );
  }
}
