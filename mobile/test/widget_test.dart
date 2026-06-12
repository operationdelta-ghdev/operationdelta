import 'package:flutter_test/flutter_test.dart';
import 'package:ingress_event_tracker/main.dart';
import 'package:ingress_event_tracker/screens/dashboard_screen.dart';

void main() {
  testWidgets('App loads and shows dashboard', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IngressEventApp());

    // Verify that the DashboardScreen is shown
    expect(find.byType(DashboardScreen), findsOneWidget);
    
    // Verify specific UI elements from DashboardScreen
    expect(find.text('OPERATION_DELTA'), findsOneWidget);
  });
}
