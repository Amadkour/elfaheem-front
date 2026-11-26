# What the redesign needs from the backend (`../back`)

The backend lives next to this repository at `../back` (see the root CLAUDE.md). Check each item against what already exists before building anything: many of these may already be there under another name. Work on a branch with the same name as the front branch.

For every new or changed route:
- regenerate the contract snapshots (root CLAUDE.md, "Test harnesses");
- add a user-facing feature to `../back/data/app_features_guide.json`;
- add a kill-switch key to `../back/services/feature_catalog.py`.

## 1. Parent creates the child's account; the child signs in with a code

Design: `Pa2Gate.dc.html?screen=done&kid=new`, `Stu1Auth.dc.html?screen=login` (the link "عندك كود من ولي أمرك؟"), and `Stu1Auth.dc.html?screen=kidcode` with `state=found` and `state=pass`.

Flow:
1. During the parent's sign-up, the parent adds a child (name, grade, mode). The server creates the student account and links it to the parent.
2. The server returns a one-time login code: 6 digits, shown as "٤٨٢ ٩١٧". It is valid for 48 hours, single use, and the parent can regenerate it. Also return a share text for WhatsApp.
3. The child opens the app and enters the code. The server answers with only the child's first name, last name, grade and the parent's name, for the "هذا حسابك؟" check. Rate-limit the code entry and lock after a few wrong tries.
4. The child confirms, then sets a password. The server consumes the code and returns tokens like a normal login.

Check first whether the existing "link child by code" feature (Pa2Gate `screen=contact`, code like `K7Q29XM`) can be extended rather than duplicated. Both directions should work: a parent links an existing student, and a parent creates a new student.

## 2. Teacher demand numbers on the landing page

Design: `LandingW.dc.html`. Pick "أنا معلم", then a subject, then "شوف الطلب على مادتك".

Add a public, cached endpoint per subject (and per country or curriculum) that returns:
- students on the waiting list for the subject;
- classes booked in the last 30 days;
- new groups waiting for a teacher.

Recompute once a day. These are aggregates only, with no personal data. If a number is below a small threshold, return a rounded or hidden value. The landing shows "الأرقام من حجوزات المنصة الفعلية، وتتحدّث كل يوم." If the data cannot be produced, remove the card; never show invented numbers.

## 3. Privacy: students never learn who else is in a class

This must hold on the server, not only in the UI.

- Student-facing endpoints (live room, prejoin, group or course pages, attendance, schedule, chat, notifications, home) must not return other students' names, avatars, counts or attendance. Teacher endpoints still return them.
- Live room (LiveKit): a student's token can subscribe only to the teacher's tracks, plus any track the teacher explicitly shares, such as a student the teacher brings on stage. Mark students' participant identities as hidden from other students, for example with hidden participants or per-participant subscribe permissions. Typing indicators, hand-raise lists and chat must not reveal other students.
- Course "group chat" becomes a one-way teacher announcements thread. A student's reply goes privately to the teacher.
- Leaderboards show nicknames, platform-wide or grade-wide only, never per class.

## 4. Booking, groups and teachers

- A group has 5 to 10 students and a gender (boys or girls). A teacher has a gender. A girls' group requires a female teacher.
- A class is 50 minutes.
- Mode is عن بعد or حضوري. حضوري needs city and district lists from the server (§5).
- Booking types: group or فردي. Slots are stored in UTC.
- Never return or display a count of classes per week or month as a selling point.

## 5. International support (RULES.md §3)

Add or confirm:
- country of residence on the user;
- a country list;
- per-country curriculum, grade and subject lists;
- phone numbers in E.164 for any country (OTP and WhatsApp included);
- a time zone on the profile;
- payment methods filtered by country, with the charge in the gateway currency;
- teacher verification documents (passport, iqama or national ID);
- payout details for any country (IBAN of any country);
- city and district lists for in-person centres.

## 6. Other features that are new in the design

Before building, check each one against the existing features (PARITY.md). Some are probably already in the app under another name. Build the server part only for those that are really missing:
- games and rewards (points, coins, stickers, nickname leaderboards);
- Quran and Nahw areas;
- store;
- the subject's AI helper (Bot);
- the student's personal دفتر notes (typed and pen);
- student-hosted private meetings with friends the student invites himself;
- teacher certificates;
- super admin pricing, ads, releases and site pages.
