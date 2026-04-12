# ElFaheem — Student Feature

## Folder Structure

```
features/
│
├── models.dart                                  ← All student data models (single source)
│
├── courses/
│   ├── details/
│   │   ├── course_detail_provider.dart          ← Detail state: fetch, favorite, enroll
│   │   ├── course_detail_screen.dart            ← 3-tab detail screen
│   │   └── components/
│   │       └── stat_chip.dart                   ← Stat chip widget
│   ├── list/
│   │   ├── courses_provider.dart                ← Paginated course list
│   │   └── courses_list_screen.dart             ← Explore screen with search
│   └── my_courses/
│       ├── my_courses_provider.dart             ← Enrolled courses + filters
│       ├── my_courses_screen.dart               ← My courses (الكل/مستمر/مكتمله)
│       └── components/
│           └── course_progress_bar.dart         ← Progress bar widget
│
├── sessions/
│   ├── sessions_provider.dart                   ← Fetch, join live, track progress, check-in/out
│   └── sessions_screen.dart                     ← Session list with design-matching cards
│
├── enrollment/
│   ├── enrollment_provider.dart                 ← Free/paid enrollment flow
│   └── enrollment_screen.dart                   ← 3-step enrollment screen
│
└── attendance/
    ├── attendance_provider.dart                 ← Student self-attendance state
    └── attendance_screen.dart                   ← Check-in / check-out widget
```

---

## API Map

| Feature          | Method | Endpoint                                    | Provider                              |
|-----------------|--------|---------------------------------------------|---------------------------------------|
| List courses     | GET    | `/api/v1/courses`                           | `CoursesProvider.fetchCourses()`      |
| Course detail    | GET    | `/api/v1/courses/{id}`                      | `CourseDetailProvider._fetchFull()`   |
| Favorite         | POST   | `/api/v1/courses/{id}/favorite`             | `CourseDetailProvider.toggleFavorite()` |
| Unfavorite       | DELETE | `/api/v1/courses/{id}/favorite`             | same                                  |
| My enrollments   | GET    | `/api/v1/my-enrollments`                    | `MyCoursesProvider.fetchMyEnrollments()` |
| Enroll (free)    | POST   | `/api/v1/courses/{id}/enroll`               | `EnrollmentProvider._enrollFree()`   |
| Payment (card)   | POST   | `/api/v1/payments`                          | `EnrollmentProvider._initCardPayment()` |
| Bank transfer    | POST   | `/api/v1/payments/bank-transfer`            | `EnrollmentProvider._initBankTransfer()` |
| Sessions list    | GET    | `/api/v1/courses/{id}/sessions`             | `StudentSessionsProvider.fetchSessions()` |
| Join live        | GET    | `/api/v1/live-sessions/{id}/join`           | `StudentSessionsProvider.joinLive()` |
| Get recording    | GET    | `/api/v1/live-sessions/{id}/recording`      | `StudentSessionsProvider.fetchRecordingUrl()` |
| Track view       | POST   | `/api/v1/views`                             | `StudentSessionsProvider.trackView()` |
| Mark complete    | POST   | `/api/v1/views/{id}/complete`               | `StudentSessionsProvider.markComplete()` |
| Check-in         | POST   | `/api/v1/attendance/check-in`               | `StudentSessionsProvider.checkIn()` |
| Check-out        | POST   | `/api/v1/attendance/check-out`              | `StudentSessionsProvider.checkOut()` |
| Rate session     | POST   | `/api/v1/rates`                             | `StudentSessionsProvider.rateSession()` |

---

## Navigation Flow

```
DashboardScreen (BottomNav)
│
├── Tab 0: HomeScreen
│         └── CoursesRow → CourseDetailScreen (push)
│                           └── [الدروس tab] → session tiles (join/watch/complete)
│                           └── [Enroll btn] → EnrollmentScreen (push)
│                           └── [Sessions btn] → StudentSessionsScreen (push)
│                                                  └── session card tap → join/watch
│                                                  └── attendance check-in/out
│
├── Tab 1: MyCoursesScreen
│         └── card tap → CourseDetailScreen (same as above)
│
├── Tab 2: CoursesListScreen
│         └── card tap → CourseDetailScreen
│
└── ...
```

---

## Provider Setup

```dart
// Global providers (in MultiProvider at app root):
ChangeNotifierProvider<CoursesProvider>(create: (_) => CoursesProvider()),
ChangeNotifierProvider<MyCoursesProvider>(create: (_) => MyCoursesProvider()),

// Scoped providers (created when pushing screen):

// Course detail:
ChangeNotifierProvider(
  create: (_) => CourseDetailProvider(course),
  child: const CourseDetailScreen(),
)

// Enrollment:
ChangeNotifierProvider(
  create: (_) => EnrollmentProvider(course),
  child: const EnrollmentScreen(),
)

// Sessions (standalone screen):
ChangeNotifierProvider(
  create: (_) => StudentSessionsProvider(),
  child: StudentSessionsScreen(courseId: id, courseTitle: title),
)

// Attendance (widget inside session screen):
ChangeNotifierProvider(
  create: (_) => StudentAttendanceProvider(),
  child: StudentAttendanceWidget(session: session),
)
```

---

## Session Card Design

The session card matches the uploaded design images:

```
┌─────────────────────────────────────────────┐
│ [Thumbnail]    مقدمه هل المجال مهم وليه مستقبل ؟  │
│  [  01  ]     ──────────────────────────────  │
│               🕐 20 دقيقه                     │
│               📅 5/4  10:00  (if scheduled)    │
│               [▶ مسجّل]  [مكتمل]               │
│                                               │
│  (for live): [تسجيل الحضور] / [تسجيل المغادرة]  │
└─────────────────────────────────────────────┘
```

- Numbered circular badge: top-right of thumbnail
- Completed: green checkmark badge + green border
- Live + checked-in: red border + "● مباشر" badge
- Tap: join URL (live) or mark-complete prompt (recorded)

---

## Scenarios Covered

### Courses
- Paginated list with search (CoursesListScreen)
- Favorite / unfavorite with optimistic update + rollback
- My enrollments with progress (all / in-progress / completed)
- Client-side search filter on my-courses

### Sessions
- All sessions ordered by `order` field
- Tab strip: الكل / مسجّلة / مباشرة
- Live session → fetch join URL → launch in browser
- Recorded session → trackView + mark complete prompt
- Recording available badge + open recording
- Check-in / check-out per session

### Enrollment
- Free course: single POST enroll
- Paid: mada / visa / bank transfer flow
- Bank transfer: show IBAN + copy button
- Success animation screen

### Attendance
- Check-in sets timestamp, shown in record
- Check-out sets timestamp, shown in record
- Toggle button: حضور → مغادرة
