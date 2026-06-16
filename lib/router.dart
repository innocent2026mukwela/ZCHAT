import 'package:go_router/go_router.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/chats/chat_list_screen.dart';
import 'screens/chats/chat_screen.dart';
import 'screens/chats/new_chat_screen.dart';
import 'screens/chats/new_group_screen.dart';
import 'screens/chats/starred_messages_screen.dart';
import 'screens/status/status_screen.dart';
import 'screens/calls/calls_screen.dart';
import 'screens/courses/course_list_screen.dart';
import 'screens/courses/paper_list_screen.dart';
import 'screens/courses/pdf_viewer_screen.dart';
import 'screens/courses/exam_simulator_screen.dart';
import 'screens/classroom/classroom_screen.dart';
import 'screens/classroom/live_session_screen.dart';
import 'screens/classroom/assignment_list_screen.dart';
import 'screens/classroom/submission_screen.dart';
import 'screens/classroom/grade_view_screen.dart';
import 'screens/ai_assistant/ai_home_screen.dart';
import 'screens/ai_assistant/ai_chat_screen.dart';
import 'screens/ai_assistant/quiz_screen.dart';
import 'screens/ai_assistant/summary_screen.dart';
import 'screens/ai_assistant/group_summarizer_screen.dart';
import 'screens/ai_assistant/study_insights_screen.dart';
import 'screens/planner/planner_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/lecturer/lecturer_screens.dart';
import 'screens/threads/threads_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',              builder: (c, s) => const SplashScreen()),
    GoRoute(path: '/login',         builder: (c, s) => const LoginScreen()),
    GoRoute(
      path: '/otp',
      builder: (c, s) => OtpScreen(phoneNumber: s.extra as String),
    ),
    GoRoute(path: '/profile-setup', builder: (c, s) => const ProfileSetupScreen()),
    GoRoute(path: '/home',          builder: (c, s) => const HomeScreen()),
    GoRoute(path: '/threads',       builder: (c, s) => const ThreadsScreen()),
    GoRoute(
      path: '/threads/:postId',
      builder: (c, s) => ThreadDetailScreen(postId: s.pathParameters['postId']!),
    ),

    // Chats
    GoRoute(path: '/chats',      builder: (c, s) => const ChatListScreen()),
    GoRoute(path: '/new-chat',   builder: (c, s) => const NewChatScreen()),
    GoRoute(path: '/new-group',  builder: (c, s) => const NewGroupScreen()),
    GoRoute(path: '/starred',    builder: (c, s) => const StarredMessagesScreen()),
    GoRoute(
      path: '/chats/:chatId',
      builder: (c, s) => ChatScreen(
        chatId:   s.pathParameters['chatId']!,
        chatName: s.uri.queryParameters['name'] ?? 'Chat',
      ),
    ),

    // Status & Calls
    GoRoute(path: '/status', builder: (c, s) => const StatusScreen()),
    GoRoute(path: '/calls',  builder: (c, s) => const CallsScreen()),

    // Courses & Papers
    GoRoute(path: '/courses', builder: (c, s) => const CourseListScreen()),
    GoRoute(
      path: '/courses/:courseId/papers',
      builder: (c, s) => PaperListScreen(courseId: s.pathParameters['courseId']!),
    ),
    GoRoute(
      path: '/pdf-viewer',
      builder: (c, s) => PdfViewerScreen(
        url:   s.uri.queryParameters['url'] ?? '',
        title: s.uri.queryParameters['title'] ?? 'Document',
      ),
    ),
    GoRoute(
      path: '/exam-simulator/:courseId',
      builder: (c, s) => ExamSimulatorScreen(
        courseId: s.pathParameters['courseId']!,
        paperTitle: s.uri.queryParameters['paper'] ?? 'Past Paper',
      ),
    ),
    GoRoute(
      path: '/adaptive-plan/:courseId',
      builder: (c, s) => AdaptiveLearningPathScreen(courseId: s.pathParameters['courseId']!),
    ),

    // Classroom
    GoRoute(
      path: '/classroom/:courseId',
      builder: (c, s) => ClassroomScreen(courseId: s.pathParameters['courseId']!),
    ),
    GoRoute(
      path: '/classroom/:courseId/live/:roomId',
      builder: (c, s) => LiveSessionScreen(
        courseId: s.pathParameters['courseId']!,
        roomId:   s.pathParameters['roomId']!,
      ),
    ),
    GoRoute(
      path: '/classroom/:courseId/assignments',
      builder: (c, s) => AssignmentListScreen(courseId: s.pathParameters['courseId']!),
    ),
    GoRoute(
      path: '/classroom/submit/:assignmentId',
      builder: (c, s) => SubmissionScreen(assignmentId: s.pathParameters['assignmentId']!),
    ),
    GoRoute(
      path: '/classroom/grades/:assignmentId',
      builder: (c, s) => GradeViewScreen(assignmentId: s.pathParameters['assignmentId']!),
    ),

    // AI
    GoRoute(path: '/ai',                       builder: (c, s) => const AiHomeScreen()),
    GoRoute(path: '/ai/chat',                   builder: (c, s) => AiChatScreen(conversationId: s.extra as String?)),
    GoRoute(path: '/ai/quiz/:courseId',         builder: (c, s) => QuizScreen(courseId: s.pathParameters['courseId']!)),
    GoRoute(path: '/ai/summaries/:courseId',    builder: (c, s) => SummaryScreen(courseId: s.pathParameters['courseId']!)),
    GoRoute(path: '/ai/group-summarizer',       builder: (c, s) => const GroupSummarizerScreen()),
    GoRoute(path: '/ai/insights',               builder: (c, s) => const StudyInsightsScreen()),

    // Planner & Profile
    GoRoute(path: '/planner', builder: (c, s) => const PlannerScreen()),
    GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),

    // Lecturer stream
    GoRoute(path: '/lecturer/home', builder: (c, s) => const LecturerHomeScreen()),
    GoRoute(path: '/lecturer/courses', builder: (c, s) => const LecturerCoursesScreen()),
    GoRoute(path: '/lecturer/classroom', builder: (c, s) => const LecturerClassroomScreen()),
    GoRoute(path: '/lecturer/ai', builder: (c, s) => const LecturerAiScreen()),
    GoRoute(path: '/lecturer/planner', builder: (c, s) => const LecturerPlannerScreen()),
  ],
);
