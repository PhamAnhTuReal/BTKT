import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bai_kt/main.dart';

void main() {
  testWidgets('Loads the published exam and displays uploaded questions', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(ToeicReadingApp(httpClient: _examClient()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('available-test')), findsOneWidget);
    expect(find.text('RC TEST 02'), findsNothing);
    expect(find.text('RC TEST 03'), findsNothing);
    expect(find.text('RC TEST 04'), findsNothing);
    expect(find.text('RC TEST 05 - Coming soon'), findsNothing);
    expect(find.text('100 questions | 75 minutes'), findsOneWidget);
    expect(find.text('Total Tests Completed: 12'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('available-test')));
    await tester.tap(find.byKey(const ValueKey('available-test')));
    await tester.pumpAndSettle();

    expect(find.text('QUESTION 101'), findsOneWidget);
    expect(find.text('Question 101 imported content'), findsOneWidget);
    expect(find.text('Uploaded option A'), findsOneWidget);
    expect(find.text('0 of 100 answered'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-question-map')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('147'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('147'));
    await tester.pumpAndSettle();

    expect(find.text('Question 147 imported content'), findsOneWidget);
    expect(
      find.text('Uploaded passage text for the current group.'),
      findsOneWidget,
    );
  });

  testWidgets('Keeps the app home available when no exam is published', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(
      ToeicReadingApp(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {'message': 'No exam has been published.'},
            }),
            404,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello, Guest!'), findsOneWidget);
    expect(find.text('Chưa kết nối được đề thi'), findsOneWidget);
    expect(
      find.text('Đề thi do admin tải lên sẽ xuất hiện tại đây.'),
      findsOneWidget,
    );
    expect(find.text('RC TEST 02'), findsNothing);
    expect(find.text('RC TEST 03'), findsNothing);
    expect(find.text('RC TEST 04'), findsNothing);
    expect(find.text('Thử kết nối lại'), findsOneWidget);
    expect(find.byKey(const ValueKey('resume-test')), findsNothing);
  });

  testWidgets('Keeps the app home available when the API is offline', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(
      ToeicReadingApp(
        httpClient: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello, Guest!'), findsOneWidget);
    expect(find.text('Chưa kết nối được đề thi'), findsOneWidget);
    expect(find.text('Thử kết nối lại'), findsOneWidget);
    expect(find.byKey(const ValueKey('resume-test')), findsNothing);
  });

  testWidgets('Does not preselect answers and records learner selections', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(ToeicReadingApp(httpClient: _examClient()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('available-test')));
    await tester.tap(find.byKey(const ValueKey('available-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uploaded option A'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 100 answered'), findsOneWidget);
  });
}

http.Client _examClient() =>
    MockClient(
      (_) async => http.Response(
        jsonEncode({
          'result': _publishedExam(),
          'success': true,
          'targetUrl': null,
          'error': null,
          'unAuthorizedRequest': false,
          '__abp': true,
        }),
        200,
      ),
    );

Map<String, Object?> _publishedExam() {
  final parts = <Map<String, Object?>>[
    _part(5, 101, 130),
    _part(6, 131, 146),
    _part(
      7,
      147,
      200,
      groups: [
        {
          'fromNumber': 147,
          'toNumber': 200,
          'title': 'Uploaded passage group',
          'passages': [
            {
              'type': 'article',
              'content': 'Uploaded passage text for the current group.',
            },
          ],
        },
      ],
    ),
  ];
  return {
    'name': 'RC Test 01',
    'durationMinutes': 75,
    'totalQuestions': 100,
    'instructions': 'Select one answer for each question.',
    'parts': parts,
  };
}

Map<String, Object?> _part(
  int partNumber,
  int from,
  int to, {
  List<Map<String, Object?>> groups = const [],
}) => {
  'partNumber': partNumber,
  'directions': '',
  'groups': groups,
  'questions': [
    for (var number = from; number <= to; number++)
      {
        'number': number,
        'content': 'Question $number imported content',
        'options': [
          for (final label in ['A', 'B', 'C', 'D'])
            {
              'label': label,
              'content': label == 'A'
                  ? 'Uploaded option A'
                  : 'Option $label for $number',
            },
        ],
      },
  ],
};

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
