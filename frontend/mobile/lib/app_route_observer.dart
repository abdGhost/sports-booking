import 'package:flutter/material.dart';

/// Used so screens like [EventScheduleScreen] can refresh when popped back to.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
