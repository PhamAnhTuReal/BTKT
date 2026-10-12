import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:5000',
);
const _primary = Color(0xFF3E50D5);
const _ink = Color(0xFF202938);
const _muted = Color(0xFF697386);
const _border = Color(0xFFE5E8EE);
const _surface = Color(0xFFF8F9FA);
const _tint = Color(0xFFEEF0FF);
const _green = Color(0xFF208253);
const _orange = Color(0xFFC87925);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ToeicReadingApp());
}

enum _AppScreen { home, test, result }

class ToeicReadingApp extends StatefulWidget {
  const ToeicReadingApp({super.key, this.httpClient});

  final http.Client? httpClient;

  @override
  State<ToeicReadingApp> createState() => _ToeicReadingAppState();
}

class _ToeicReadingAppState extends State<ToeicReadingApp> {
  _AppScreen _screen = _AppScreen.home;
  int _questionNumber = 101;
  int _secondsRemaining = 0;
  Timer? _timer;
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  final Set<int> _markedQuestions = {};
  final Map<int, String> _answers = {};
  _ReadingExam? _exam;
  String? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPublishedExam());
  }

  Future<void> _loadPublishedExam() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final response = await _httpClient
          .get(
            Uri.parse(
              '${_apiBaseUrl.replaceFirst(RegExp(r'/$'), '')}/api/exams/published',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        String? serverMessage;
        if (response.body.isNotEmpty) {
          try {
            final errorBody = jsonDecode(response.body);
            if (errorBody is Map<String, dynamic>) {
              final directMessage = errorBody['message'];
              final error = errorBody['error'];
              final nestedMessage = error is Map<String, dynamic>
                  ? error['message']
                  : null;
              if (directMessage is String) {
                serverMessage = directMessage;
              } else if (nestedMessage is String) {
                serverMessage = nestedMessage;
              }
            }
          } on FormatException {
            serverMessage = null;
          }
        }
        final details =
            serverMessage ??
            (response.body.isEmpty
                ? 'HTTP ${response.statusCode}'
                : 'HTTP ${response.statusCode}: ${response.body}');
        throw FormatException('Không tải được đề thi: $details');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Dữ liệu đề thi từ máy chủ không hợp lệ.');
      }

      final examPayload = decoded.containsKey('result')
          ? decoded['result']
          : decoded;
      if (examPayload is! Map<String, dynamic>) {
        throw const FormatException('Dữ liệu đề thi từ máy chủ không hợp lệ.');
      }

      final exam = _ReadingExam.fromJson(examPayload);
      if (exam.questions.length != exam.totalQuestions ||
          exam.questions.isEmpty) {
        throw const FormatException('Đề thi từ máy chủ bị thiếu câu hỏi.');
      }
      if (!mounted) return;

      setState(() {
        _exam = exam;
        _questionNumber = exam.questions.first.number;
        _secondsRemaining = exam.durationMinutes * 60;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _exam = null;
        _loadError = error.toString();
        _screen = _AppScreen.home;
        _isLoading = false;
      });
    }
  }

  void _openTest() {
    if (_exam == null || _exam!.questions.isEmpty) return;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining <= 0) {
        _finishTest();
        return;
      }
      if (mounted) {
        setState(() => _secondsRemaining--);
      }
    });
    setState(() => _screen = _AppScreen.test);
  }

  void _returnHome() {
    _timer?.cancel();
    _timer = null;
    setState(() => _screen = _AppScreen.home);
  }

  bool _isSavingAttempt = false;
  String? _saveAttemptStatus;

  Future<void> _finishTest() async {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    setState(() {
      _screen = _AppScreen.result;
      _isSavingAttempt = true;
      _saveAttemptStatus = 'Đang lưu kết quả vào database...';
    });

    try {
      final exam = _exam;
      final payload = jsonEncode({
        'examId': exam?.id,
        'secondsTaken': (exam != null)
            ? (exam.durationMinutes * 60) - _secondsRemaining
            : 0,
        'answers': _answers.map((k, v) => MapEntry(k.toString(), v)),
      });

      final response = await _httpClient
          .post(
            Uri.parse(
              '${_apiBaseUrl.replaceFirst(RegExp(r'/$'), '')}/api/exams/submit',
            ),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _saveAttemptStatus = 'Đã lưu kết quả vào database thành công';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _saveAttemptStatus =
                'Lưu kết quả thất bại (HTTP ${response.statusCode})';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveAttemptStatus = 'Không thể kết nối máy chủ để lưu kết quả';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingAttempt = false);
      }
    }
  }

  void _showQuestionMap(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuestionMapSheet(
        currentQuestion: _questionNumber,
        answeredQuestions: _answers.keys.toSet(),
        markedQuestions: _markedQuestions,
        onJumpTo: (number) => setState(() => _questionNumber = number),
        onSubmit: _finishTest,
      ),
    );
  }

  void _selectQuestion(int number) {
    final exam = _exam!;
    final first = exam.questions.first.number;
    final last = exam.questions.last.number;
    setState(() => _questionNumber = number.clamp(first, last));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOEIC Reading',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primary,
          primary: _primary,
          surface: Colors.white,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: _primary,
          selectionColor: _tint,
          selectionHandleColor: _primary,
        ),
      ),
      home: _isLoading
          ? const _ExamLoadingScreen()
          : switch (_screen) {
              _AppScreen.home => _HomeScreen(
                exam: _exam,
                answeredCount: _answers.length,
                loadError: _loadError,
                onRetry: _loadPublishedExam,
                onOpenTest: _openTest,
              ),
              _AppScreen.test => _ReadingTestScreen(
                exam: _exam!,
                question: _exam!.questionByNumber(_questionNumber)!,
                part: _exam!.partForNumber(_questionNumber)!,
                group: _exam!.groupForNumber(_questionNumber),
                questionNumber: _questionNumber,
                secondsRemaining: _secondsRemaining,
                selectedAnswer: _answers[_questionNumber],
                isMarked: _markedQuestions.contains(_questionNumber),
                answeredCount: _answers.length,
                onBack: _returnHome,
                onOpenQuestionMap: _showQuestionMap,
                onChooseAnswer: (answer) {
                  setState(() => _answers[_questionNumber] = answer);
                },
                onToggleMark: () {
                  setState(() {
                    if (!_markedQuestions.add(_questionNumber)) {
                      _markedQuestions.remove(_questionNumber);
                    }
                  });
                },
                onPrevious: () => _selectQuestion(_questionNumber - 1),
                onNext: () {
                  if (_questionNumber == _exam!.questions.last.number) {
                    _finishTest();
                  } else {
                    _selectQuestion(_questionNumber + 1);
                  }
                },
              ),
              _AppScreen.result => _TestResultScreen(
                exam: _exam!,
                answers: _answers,
                secondsRemaining: _secondsRemaining,
                isSaving: _isSavingAttempt,
                saveStatus: _saveAttemptStatus,
                onReviewAnswers: _openTest,
                onGoHome: _returnHome,
              ),
            },
    );
  }
}

class _ReadingExam {
  const _ReadingExam({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.totalQuestions,
    required this.parts,
    required this.questions,
  });

  final int id;
  final String name;
  final int durationMinutes;
  final int totalQuestions;
  final List<_ReadingPart> parts;
  final List<_ReadingQuestion> questions;

  factory _ReadingExam.fromJson(Map<String, dynamic> json) {
    final parts = (json['parts'] as List<dynamic>)
        .map((part) => _ReadingPart.fromJson(part as Map<String, dynamic>))
        .toList();
    final questions = parts.expand((part) => part.questions).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return _ReadingExam(
      id: (json['id'] as int?) ?? 0,
      name: json['name'] as String,
      durationMinutes: json['durationMinutes'] as int,
      totalQuestions: json['totalQuestions'] as int,
      parts: parts,
      questions: questions,
    );
  }

  _ReadingQuestion? questionByNumber(int number) {
    for (final question in questions) {
      if (question.number == number) return question;
    }
    return null;
  }

  _ReadingPart? partForNumber(int number) {
    for (final part in parts) {
      if (part.questions.any((question) => question.number == number)) {
        return part;
      }
    }
    return null;
  }

  _ReadingGroup? groupForNumber(int number) {
    for (final part in parts) {
      for (final group in part.groups) {
        if (number >= group.fromNumber && number <= group.toNumber) {
          return group;
        }
      }
    }
    return null;
  }
}

class _ReadingPart {
  const _ReadingPart({
    required this.partNumber,
    required this.directions,
    required this.groups,
    required this.questions,
  });

  final int partNumber;
  final String? directions;
  final List<_ReadingGroup> groups;
  final List<_ReadingQuestion> questions;

  factory _ReadingPart.fromJson(Map<String, dynamic> json) => _ReadingPart(
    partNumber: json['partNumber'] as int,
    directions: json['directions'] as String?,
    groups: (json['groups'] as List<dynamic>)
        .map((group) => _ReadingGroup.fromJson(group as Map<String, dynamic>))
        .toList(),
    questions: (json['questions'] as List<dynamic>)
        .map(
          (question) =>
              _ReadingQuestion.fromJson(question as Map<String, dynamic>),
        )
        .toList(),
  );
}

class _ReadingGroup {
  const _ReadingGroup({
    required this.fromNumber,
    required this.toNumber,
    required this.title,
    required this.passages,
  });

  final int fromNumber;
  final int toNumber;
  final String? title;
  final List<_ReadingPassage> passages;

  factory _ReadingGroup.fromJson(Map<String, dynamic> json) => _ReadingGroup(
    fromNumber: json['fromNumber'] as int,
    toNumber: json['toNumber'] as int,
    title: json['title'] as String?,
    passages: (json['passages'] as List<dynamic>)
        .map(
          (passage) =>
              _ReadingPassage.fromJson(passage as Map<String, dynamic>),
        )
        .toList(),
  );
}

class _ReadingPassage {
  const _ReadingPassage({required this.type, required this.content});

  final String? type;
  final String? content;

  factory _ReadingPassage.fromJson(Map<String, dynamic> json) =>
      _ReadingPassage(
        type: json['type'] as String?,
        content: json['content'] as String?,
      );
}

class _ReadingQuestion {
  const _ReadingQuestion({
    required this.id,
    required this.number,
    required this.content,
    required this.options,
    this.correctAnswer,
  });

  final int id;
  final int number;
  final String content;
  final Map<String, String> options;
  final String? correctAnswer;

  factory _ReadingQuestion.fromJson(Map<String, dynamic> json) =>
      _ReadingQuestion(
        id: (json['id'] as int?) ?? 0,
        number: json['number'] as int,
        content: json['content'] as String,
        correctAnswer: json['correctAnswer'] as String?,
        options: {
          for (final option in json['options'] as List<dynamic>)
            (option as Map<String, dynamic>)['label'] as String:
                option['content'] as String,
        },
      );
}

class _ExamLoadingScreen extends StatelessWidget {
  const _ExamLoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _SvgAsset extends StatelessWidget {
  const _SvgAsset(this.name, {this.size = 20});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/figma/$name.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

TextStyle _style(
  double size, {
  Color color = _ink,
  FontWeight weight = FontWeight.normal,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: height,
  );
}

BoxDecoration _cardDecoration({
  Color color = Colors.white,
  Color borderColor = _border,
  double radius = 12,
}) {
  return BoxDecoration(
    color: color,
    border: Border.all(color: borderColor),
    borderRadius: BorderRadius.circular(radius),
  );
}

Widget _primaryButton({
  required String label,
  required VoidCallback onPressed,
  Key? key,
  double height = 48,
  double fontSize = 15,
}) {
  return SizedBox(
    height: height,
    child: ElevatedButton(
      key: key,
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: _style(
          fontSize,
          color: Colors.white,
          weight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    ),
  );
}

Widget _outlinedButton({
  required String label,
  required VoidCallback onPressed,
  double height = 48,
}) {
  return SizedBox(
    height: height,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        side: const BorderSide(color: _primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: _style(15, color: _primary, weight: FontWeight.w600),
      ),
      child: Text(label),
    ),
  );
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.exam,
    required this.answeredCount,
    required this.loadError,
    required this.onRetry,
    required this.onOpenTest,
  });

  final _ReadingExam? exam;
  final int answeredCount;
  final String? loadError;
  final VoidCallback onRetry;
  final VoidCallback onOpenTest;

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: _tint,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const _SvgAsset(
                              'home_imgUserRound',
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hello, Guest!',
                                  style: _style(24, weight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'A little practice. A lot of progress.',
                                  style: _style(13, color: _muted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Notifications',
                            onPressed: () =>
                                _showMessage(context, 'No new notifications.'),
                            icon: const _SvgAsset('home_imgBell', size: 24),
                          ),
                        ],
                      ),
                    ),
                    if (loadError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: _cardDecoration(
                            color: const Color(0xFFFFF8E8),
                            borderColor: const Color(0xFFF0D9A8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chưa kết nối được đề thi',
                                style: _style(15, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Bạn vẫn có thể sử dụng giao diện. Khởi động API và tải đề lên từ trang quản trị để bắt đầu làm bài.',
                                style: _style(13, color: _muted, height: 1.4),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                loadError!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _style(11, color: _muted),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: onRetry,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Thử kết nối lại'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: _cardDecoration(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "You're building momentum",
                              style: _style(16, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total Tests Completed: 12',
                              style: _style(14, weight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Average Score: 750/990',
                              style: _style(
                                14,
                                color: _primary,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: const _SvgAsset(
                                      'home_imgScoreTrend',
                                      size: 42,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '+60 points',
                                      style: _style(
                                        13,
                                        color: _primary,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Last 5 tests',
                                      style: _style(12, color: _muted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Continue where you left off',
                        style: _style(16, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _tint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const _SvgAsset('home_imgBookOpen', size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    exam != null
                                        ? (exam!.name.toLowerCase().contains(
                                                'reading',
                                              )
                                              ? exam!.name
                                              : '${exam!.name} - Reading')
                                        : 'Chưa có đề thi',
                                    style: _style(15, weight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Progress: $answeredCount/${exam?.totalQuestions ?? 0}',
                                        style: _style(13, color: _muted),
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
                                        child: LinearProgressIndicator(
                                          value:
                                              (exam != null &&
                                                  exam!.totalQuestions > 0)
                                              ? (answeredCount /
                                                        exam!.totalQuestions)
                                                    .clamp(0.0, 1.0)
                                              : 0.0,
                                          minHeight: 6,
                                          backgroundColor: Colors.white,
                                          color: _primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 18),
                                ElevatedButton(
                                  onPressed: exam != null ? onOpenTest : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        answeredCount > 0 ? 'Resume' : 'Start',
                                        style: _style(
                                          14,
                                          color: Colors.white,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const _SvgAsset(
                                        'home_imgArrowRight',
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 18,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFFC7CBD5),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Available Tests',
                            style: _style(16, weight: FontWeight.w700),
                          ),
                          Text(
                            exam == null ? '0 tests' : '1 test',
                            style: _style(13, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: exam == null
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: _cardDecoration(color: Colors.white),
                              child: Text(
                                'Chưa có đề thi được phát hành từ Admin.',
                                style: _style(14, color: _muted),
                              ),
                            )
                          : _TestLibraryCard(
                              title: exam!.name,
                              statusBadge: 'Available',
                              isScoreBadge: false,
                              totalQuestions: exam!.totalQuestions,
                              durationMinutes: exam!.durationMinutes,
                              onTap: onOpenTest,
                            ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _HomeNavigation(
              onHistory: () => _showMessage(
                context,
                'Your completed test history is coming soon.',
              ),
              onSettings: () =>
                  _showMessage(context, 'Settings are coming soon.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestLibraryCard extends StatelessWidget {
  const _TestLibraryCard({
    required this.title,
    required this.statusBadge,
    this.isScoreBadge = false,
    required this.totalQuestions,
    required this.durationMinutes,
    required this.onTap,
  });

  final String title;
  final String statusBadge;
  final bool isScoreBadge;
  final int totalQuestions;
  final int durationMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const _SvgAsset('home_imgFileText', size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: _style(15, weight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isScoreBadge ? _tint : _surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusBadge,
                      style: _style(
                        12,
                        color: isScoreBadge ? _primary : _muted,
                        weight: isScoreBadge
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const _SvgAsset('home_imgChevronRight', size: 16),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _tag('Reading', colored: true),
                  _tag('$totalQuestions Questions'),
                  _tag('$durationMinutes Minutes'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, {bool colored = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colored ? _tint : const Color(0xFFF1F3F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: _style(
          12,
          color: colored ? _primary : _muted,
          weight: colored ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _HomeNavigation extends StatelessWidget {
  const _HomeNavigation({required this.onHistory, required this.onSettings});

  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _NavigationItem(
            label: 'Home',
            asset: 'home_imgHouse',
            selected: true,
            onTap: () {},
          ),
          _NavigationItem(
            label: 'History',
            asset: 'home_imgHistory',
            onTap: onHistory,
          ),
          _NavigationItem(
            label: 'Settings',
            asset: 'home_imgSettings',
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.asset,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? _tint : Colors.white,
                borderRadius: BorderRadius.circular(100),
              ),
              alignment: Alignment.center,
              child: _SvgAsset(asset, size: 22),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: _style(
                12,
                color: selected ? _primary : _muted,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingTestScreen extends StatelessWidget {
  const _ReadingTestScreen({
    required this.exam,
    required this.question,
    required this.part,
    required this.group,
    required this.questionNumber,
    required this.secondsRemaining,
    required this.selectedAnswer,
    required this.isMarked,
    required this.answeredCount,
    required this.onBack,
    required this.onOpenQuestionMap,
    required this.onChooseAnswer,
    required this.onToggleMark,
    required this.onPrevious,
    required this.onNext,
  });

  final _ReadingExam exam;
  final _ReadingQuestion question;
  final _ReadingPart part;
  final _ReadingGroup? group;
  final int questionNumber;
  final int secondsRemaining;
  final String? selectedAnswer;
  final bool isMarked;
  final int answeredCount;
  final VoidCallback onBack;
  final ValueChanged<BuildContext> onOpenQuestionMap;
  final ValueChanged<String> onChooseAnswer;
  final VoidCallback onToggleMark;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final questionIndex =
        part.questions.indexWhere((item) => item.number == questionNumber) + 1;
    final sectionQuestionCount = part.questions.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TestHeader(
              title: '${exam.name} - Reading',
              time: _formatTime(secondsRemaining),
              progress: answeredCount / exam.totalQuestions,
              onBack: onBack,
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      width: double.infinity,
                      color: _surface,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group == null
                                  ? 'Question $questionNumber • Part ${part.partNumber}'
                                  : 'Questions ${group!.fromNumber}-${group!.toNumber} • Part ${part.partNumber}',
                              style: _style(
                                13,
                                color: _muted,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (part.directions?.isNotEmpty == true) ...[
                              Text(
                                part.directions!,
                                style: _style(14, color: _muted, height: 1.5),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (group?.title?.isNotEmpty == true) ...[
                              Text(
                                group!.title!,
                                style: _style(16, weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                            ],
                            for (final passage
                                in group?.passages ?? const <_ReadingPassage>[])
                              if (passage.content?.isNotEmpty == true) ...[
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(20),
                                  decoration: _cardDecoration(),
                                  child: Text(
                                    passage.content!,
                                    style: _style(16, height: 1.56),
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        Container(
                          height: 20,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: _border)),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCDD2DC),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'QUESTION $questionNumber',
                                    style: _style(
                                      13,
                                      color: _primary,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const _SvgAsset('test_imgSeparator', size: 3),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$questionIndex of $sectionQuestionCount',
                                    style: _style(12, color: _muted),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: onToggleMark,
                                    child: Row(
                                      children: [
                                        const _SvgAsset(
                                          'test_imgBookmark',
                                          size: 16,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          isMarked ? 'Marked' : 'Mark',
                                          style: _style(12, color: _muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                question.content,
                                style: _style(
                                  20,
                                  weight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (final entry in question.options.entries) ...[
                                _AnswerOption(
                                  label: entry.key,
                                  text: entry.value,
                                  selected: selectedAnswer == entry.key,
                                  onTap: () => onChooseAnswer(entry.key),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: _border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$answeredCount of ${exam.totalQuestions} answered',
                          style: _style(12, color: _muted),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('open-question-map'),
                        onPressed: () => onOpenQuestionMap(context),
                        icon: const _SvgAsset('test_imgLayoutGrid', size: 14),
                        label: Text(
                          'Question map',
                          style: _style(
                            12,
                            color: _primary,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              questionNumber > exam.questions.first.number
                              ? onPrevious
                              : null,
                          icon: const _SvgAsset(
                            'test_imgChevronLeft1',
                            size: 18,
                          ),
                          label: const Text('Previous'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _ink,
                            side: const BorderSide(color: _border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: _style(15, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onNext,
                          iconAlignment: IconAlignment.end,
                          icon: const _SvgAsset(
                            'test_imgChevronRight',
                            size: 18,
                          ),
                          label: Text(
                            questionNumber == exam.questions.last.number
                                ? 'Finish'
                                : 'Next',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: _style(
                              15,
                              color: Colors.white,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestHeader extends StatelessWidget {
  const _TestHeader({
    required this.title,
    required this.time,
    required this.progress,
    required this.onBack,
  });

  final String title;
  final String time;
  final double progress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: InkWell(
                    onTap: onBack,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: _SvgAsset('test_imgChevronLeft', size: 24),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: _style(16, weight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _tint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const _SvgAsset('test_imgClock', size: 15),
                      const SizedBox(width: 5),
                      Text(
                        time,
                        style: _style(
                          14,
                          color: _primary,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        LinearProgressIndicator(
          value: progress,
          minHeight: 3,
          backgroundColor: const Color(0xFFEDEFF4),
          color: _primary,
        ),
      ],
    );
  }
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _tint : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _tint : Colors.white,
            border: Border.all(
              color: selected ? _primary : _border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _primary : Colors.white,
                  border: Border.all(color: selected ? _primary : _border),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  label,
                  style: _style(
                    13,
                    color: selected ? Colors.white : _muted,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: _style(
                    15,
                    color: selected ? _primary : _ink,
                    weight: selected ? FontWeight.w500 : FontWeight.normal,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionMapSheet extends StatelessWidget {
  const _QuestionMapSheet({
    required this.currentQuestion,
    required this.answeredQuestions,
    required this.markedQuestions,
    required this.onJumpTo,
    required this.onSubmit,
  });

  final int currentQuestion;
  final Set<int> answeredQuestions;
  final Set<int> markedQuestions;
  final ValueChanged<int> onJumpTo;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(
                height: 24,
                child: Center(
                  child: SizedBox(
                    width: 36,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFCDD2DC),
                        borderRadius: BorderRadius.all(Radius.circular(100)),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Question Map',
                            style: _style(24, weight: FontWeight.w700),
                          ),
                        ),
                        Material(
                          color: _surface,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.pop(context),
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Center(
                                child: _SvgAsset('map_imgX', size: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap a question to jump to it.',
                      style: _style(13, color: _muted),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          '${answeredQuestions.length} of 100 answered',
                          style: _style(
                            13,
                            color: _primary,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Viewing Question $currentQuestion',
                          style: _style(12, color: _muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _MapLegend(
                          asset: 'map_imgStatusSymbol',
                          label: 'Answered',
                        ),
                        _MapLegend(
                          asset: 'map_imgStatusSymbol1',
                          label: 'Unanswered',
                        ),
                        _MapLegend(
                          asset: 'map_imgStatusSymbol2',
                          label: 'Marked for review',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: _surface,
                    border: Border(top: BorderSide(color: _border)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const _MapPartTitle(
                        title: 'Part 5: Incomplete Sentences (101-130)',
                      ),
                      const SizedBox(height: 12),
                      _MapQuestionGrid(
                        from: 101,
                        to: 130,
                        currentQuestion: currentQuestion,
                        answeredQuestions: answeredQuestions,
                        markedQuestions: markedQuestions,
                        onJumpTo: onJumpTo,
                      ),
                      const SizedBox(height: 20),
                      const _MapPartTitle(
                        title: 'Part 6: Text Completion (131-146)',
                      ),
                      const SizedBox(height: 12),
                      _MapQuestionGrid(
                        from: 131,
                        to: 146,
                        currentQuestion: currentQuestion,
                        answeredQuestions: answeredQuestions,
                        markedQuestions: markedQuestions,
                        onJumpTo: onJumpTo,
                      ),
                      const SizedBox(height: 20),
                      const _MapPartTitle(
                        title: 'Part 7: Reading Comprehension (147-200)',
                      ),
                      const SizedBox(height: 12),
                      _MapQuestionGrid(
                        from: 147,
                        to: 200,
                        currentQuestion: currentQuestion,
                        answeredQuestions: answeredQuestions,
                        markedQuestions: markedQuestions,
                        onJumpTo: onJumpTo,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: _border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: _style(15, weight: FontWeight.w600),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Return to Test'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _primaryButton(
                        label: 'Submit Test',
                        onPressed: () {
                          Navigator.pop(context);
                          onSubmit();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SvgAsset(asset, size: 14),
        const SizedBox(width: 6),
        Text(label, style: _style(12, color: _muted)),
      ],
    );
  }
}

class _MapPartTitle extends StatelessWidget {
  const _MapPartTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: _style(14, weight: FontWeight.w600, height: 1.4));
  }
}

class _MapQuestionGrid extends StatelessWidget {
  const _MapQuestionGrid({
    required this.from,
    required this.to,
    required this.currentQuestion,
    required this.answeredQuestions,
    required this.markedQuestions,
    required this.onJumpTo,
  });

  final int from;
  final int to;
  final int currentQuestion;
  final Set<int> answeredQuestions;
  final Set<int> markedQuestions;
  final ValueChanged<int> onJumpTo;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: to - from + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 8,
        childAspectRatio: 55 / 40,
      ),
      itemBuilder: (context, index) {
        final number = from + index;
        final isAnswered = answeredQuestions.contains(number);
        final isMarked = markedQuestions.contains(number);
        final isCurrent = currentQuestion == number;
        final background = isAnswered ? _primary : Colors.white;
        final foreground = isAnswered
            ? Colors.white
            : isMarked
            ? _orange
            : _muted;
        final borderColor = isAnswered
            ? _primary
            : isMarked
            ? _orange
            : const Color(0xFFCDD2DC);

        return InkWell(
          onTap: () {
            Navigator.pop(context);
            onJumpTo(number);
          },
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: background,
                  border: Border.all(
                    color: borderColor,
                    width: isMarked || isCurrent ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: _style(14, color: foreground, weight: FontWeight.w600),
                ),
              ),
              if (isMarked)
                Positioned(
                  right: -4,
                  top: -5,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const _SvgAsset('map_imgFlag', size: 10),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

int _calculateReadingScore(int correctCount, int totalCount) {
  if (totalCount == 0 || correctCount <= 0) return 5;
  if (correctCount >= totalCount) return 495;

  const rawThresholds = [
    0,
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
    60,
    65,
    70,
    75,
    80,
    85,
    90,
    95,
    100,
  ];
  const scaledScores = [
    5,
    5,
    35,
    60,
    95,
    125,
    160,
    195,
    225,
    255,
    280,
    305,
    325,
    350,
    375,
    410,
    445,
    475,
    495,
  ];

  final normalizedRaw = (correctCount * 100 / totalCount).round().clamp(0, 100);

  for (var i = 0; i < rawThresholds.length - 1; i++) {
    final r0 = rawThresholds[i];
    final r1 = rawThresholds[i + 1];
    if (normalizedRaw >= r0 && normalizedRaw <= r1) {
      final s0 = scaledScores[i];
      final s1 = scaledScores[i + 1];
      if (r1 == r0) return s0;
      final t = (normalizedRaw - r0) / (r1 - r0);
      final val = (s0 + t * (s1 - s0)).round();
      return ((val + 2) ~/ 5) * 5;
    }
  }
  return 495;
}

int _calculateSectionAccuracy({
  required List<_ReadingQuestion> questions,
  required Map<int, String> answers,
  required int from,
  required int to,
}) {
  final sectionQuestions = questions
      .where((q) => q.number >= from && q.number <= to)
      .toList();
  if (sectionQuestions.isEmpty) return 0;

  final correctCount = sectionQuestions.where((q) {
    final userChoice = answers[q.number]?.trim().toUpperCase();
    final correctChoice = q.correctAnswer?.trim().toUpperCase();
    return userChoice != null &&
        userChoice.isNotEmpty &&
        correctChoice != null &&
        correctChoice.isNotEmpty &&
        userChoice == correctChoice;
  }).length;

  return (correctCount * 100) ~/ sectionQuestions.length;
}

class _TestResultScreen extends StatelessWidget {
  const _TestResultScreen({
    required this.exam,
    required this.answers,
    required this.secondsRemaining,
    required this.isSaving,
    required this.saveStatus,
    required this.onReviewAnswers,
    required this.onGoHome,
  });

  final _ReadingExam exam;
  final Map<int, String> answers;
  final int secondsRemaining;
  final bool isSaving;
  final String? saveStatus;
  final VoidCallback onReviewAnswers;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    int correctCount = 0;
    int incorrectCount = 0;
    int skippedCount = 0;

    for (final question in exam.questions) {
      final userChoice = answers[question.number]?.trim().toUpperCase();
      final correctChoice = question.correctAnswer?.trim().toUpperCase();

      if (userChoice == null || userChoice.isEmpty) {
        skippedCount++;
      } else if (correctChoice != null &&
          correctChoice.isNotEmpty &&
          userChoice == correctChoice) {
        correctCount++;
      } else {
        incorrectCount++;
      }
    }

    final totalQuestions = exam.totalQuestions > 0
        ? exam.totalQuestions
        : exam.questions.length;
    final score = _calculateReadingScore(correctCount, totalQuestions);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: onGoHome,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _SvgAsset('result_imgBackIcon', size: 24),
                            Text('Home', style: _style(15, color: _primary)),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      'Test Result',
                      style: _style(16, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: _border),
            Expanded(
              child: Container(
                color: _surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (saveStatus != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSaving
                                ? const Color(0xFFEFF6FF)
                                : (saveStatus!.contains('thành công')
                                      ? const Color(0xFFF0FDF4)
                                      : const Color(0xFFFEF2F2)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSaving
                                  ? const Color(0xFFBFDBFE)
                                  : (saveStatus!.contains('thành công')
                                        ? const Color(0xFFBBF7D0)
                                        : const Color(0xFFFECACA)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSaving
                                    ? Icons.sync
                                    : (saveStatus!.contains('thành công')
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline),
                                size: 18,
                                color: isSaving
                                    ? const Color(0xFF2563EB)
                                    : (saveStatus!.contains('thành công')
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFDC2626)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  saveStatus!,
                                  style: _style(
                                    13,
                                    color: isSaving
                                        ? const Color(0xFF1E40AF)
                                        : (saveStatus!.contains('thành công')
                                              ? const Color(0xFF15803D)
                                              : const Color(0xFF991B1B)),
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _ScoreSummaryCard(
                        examName: exam.name,
                        totalQuestions: totalQuestions,
                        durationMinutes: exam.durationMinutes,
                        secondsRemaining: secondsRemaining,
                        correctCount: correctCount,
                        incorrectCount: incorrectCount,
                        skippedCount: skippedCount,
                        score: score,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Breakdown by Section',
                        style: _style(18, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your accuracy across the three Reading sections.',
                        style: _style(13, color: _muted),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: _cardDecoration(),
                        child: Column(
                          children: [
                            _SectionAccuracy(
                              label: 'Part 5: Incomplete Sentences',
                              percent: _calculateSectionAccuracy(
                                questions: exam.questions,
                                answers: answers,
                                from: 101,
                                to: 130,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _SectionAccuracy(
                              label: 'Part 6: Text Completion',
                              percent: _calculateSectionAccuracy(
                                questions: exam.questions,
                                answers: answers,
                                from: 131,
                                to: 146,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _SectionAccuracy(
                              label: 'Part 7: Reading Comprehension',
                              percent: _calculateSectionAccuracy(
                                questions: exam.questions,
                                answers: answers,
                                from: 147,
                                to: 200,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _outlinedButton(
                      label: 'Review Answers',
                      onPressed: onReviewAnswers,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _primaryButton(
                      label: 'Go to Home',
                      onPressed: onGoHome,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreSummaryCard extends StatelessWidget {
  const _ScoreSummaryCard({
    required this.examName,
    required this.totalQuestions,
    required this.durationMinutes,
    required this.secondsRemaining,
    required this.correctCount,
    required this.incorrectCount,
    required this.skippedCount,
    required this.score,
  });

  final String examName;
  final int totalQuestions;
  final int durationMinutes;
  final int secondsRemaining;
  final int correctCount;
  final int incorrectCount;
  final int skippedCount;
  final int score;

  @override
  Widget build(BuildContext context) {
    final secondsTaken = durationMinutes * 60 - secondsRemaining;
    String formatTime(int seconds) {
      final safeSeconds = seconds < 0 ? 0 : seconds;
      final minutes = safeSeconds ~/ 60;
      final remainingSeconds = safeSeconds % 60;
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }

    final progressRatio = totalQuestions > 0
        ? (correctCount / totalQuestions).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$examName - Reading',
                  style: _style(15, weight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _tint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Completed',
                  style: _style(11, color: _primary, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 210,
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 190,
                  height: 190,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 12,
                    valueColor: const AlwaysStoppedAnimation(_border),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                SizedBox(
                  width: 190,
                  height: 190,
                  child: CircularProgressIndicator(
                    value: progressRatio,
                    strokeWidth: 12,
                    valueColor: const AlwaysStoppedAnimation(_primary),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Score:',
                      style: _style(14, color: _muted, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: _style(42, weight: FontWeight.w700),
                        children: [
                          TextSpan(text: '$score'),
                          TextSpan(
                            text: ' / 495',
                            style: _style(
                              18,
                              color: _muted,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Reading',
                      style: _style(13, color: _muted, weight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OutcomeRow(
            asset: 'result_imgCheck',
            background: const Color(0xFFECF7F0),
            label: 'Correct: $correctCount/$totalQuestions',
            color: _green,
          ),
          const SizedBox(height: 8),
          _OutcomeRow(
            asset: 'result_imgX',
            background: const Color(0xFFFDECEC),
            label: 'Incorrect: $incorrectCount/$totalQuestions',
            color: const Color(0xFFC84444),
          ),
          const SizedBox(height: 8),
          _OutcomeRow(
            asset: 'result_imgMinus',
            background: const Color(0xFFEDEFF4),
            label: 'Skipped: $skippedCount/$totalQuestions',
            color: _muted,
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const _SvgAsset('result_imgClock', size: 17),
              Text('Time Taken: ', style: _style(14, color: _muted)),
              Text(
                '${formatTime(secondsTaken)} / ${formatTime(durationMinutes * 60)}',
                style: _style(14, weight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  const _OutcomeRow({
    required this.asset,
    required this.background,
    required this.label,
    required this.color,
  });

  final String asset;
  final Color background;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: _SvgAsset(asset, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: _style(15, color: color, weight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SectionAccuracy extends StatelessWidget {
  const _SectionAccuracy({required this.label, required this.percent});

  final String label;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: _style(14, weight: FontWeight.w500)),
            ),
            Text(
              '$percent%',
              style: _style(15, color: _primary, weight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            backgroundColor: const Color(0xFFEDEFF4),
            color: _primary,
          ),
        ),
      ],
    );
  }
}
