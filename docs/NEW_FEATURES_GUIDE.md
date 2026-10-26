# NextBrain: new features, a quick guide

For teachers, organization admins and staff, students and super admins. Reading time: about 15 minutes.

The app opens in Arabic. Button names below are the English labels, with the Arabic label in parentheses where it helps you find it.
Any of these features can be hidden by a platform admin (a "feature switch"). If you can't find a button, ask your admin.

## At a glance

| I want to… | Who | Go to |
|---|---|---|
| Create an exam that marks itself | Teacher | Analysis (التحليلات) → your course → Exams (الاختبارات) → New-engine exams (الاختبارات الجديدة) → + New exam |
| Add questions to the bank | Teacher | The same section → Question bank (بنك الأسئلة) icon |
| Check the grader's marks | Teacher | Tap a published exam → Review marking (مراجعة التصحيح) |
| Mark a paper exam from scans | Teacher | Review marking → Scanned pages (الأوراق الممسوحة) icon |
| Answer an appeal | Teacher | Review marking → Appeals (التظلمات) icon |
| See question statistics | Teacher | Review marking → Analytics (التحليلات) icon |
| Take an exam | Student | Course → Exams tab → Course exams → Start exam |
| Ask for a regrade | Student | Exam result → the question → Request a regrade (طلب إعادة تصحيح) |
| Ask the documents assistant | Member, student | Organization screen or course profile → book icon, Documents assistant (مساعد المستندات) |
| Upload regulations for the assistant | Library manager | Documents assistant → Documents library (مكتبة المستندات) → Upload |
| Set a library's size limit | Super admin | Admin dashboard → People & messages → Organizations → the organization → Assistant library quota |
| Turn on two-step verification | Admins, org admins and staff | Profile → Security → Two-step verification (التحقق بخطوتين); admins also: Support & security |
| Unlock someone who lost their phone | Super admin | Admin user list (e.g. Teachers, Admins) → the person → Reset two-step verification |
| Download all my data | Everyone | Profile → Download my data (تنزيل بياناتي) |
| Refund a payment | Admin, super admin | Admin dashboard → Finance & requests → Payments → the payment → Refund |

## 1. Exams that mark themselves (the Exam Engine)

### 1.1 What is new

- The **server** keeps the clock and saves every answer. If the app closes, nothing is lost.
- Questions live in a **question bank** with versions. Editing a question never changes an exam that is already running.
- Objective questions are marked the moment the student submits.
- Open answers (short answer, essay) get a **proposed mark** from the automatic grader. **A teacher decides.**
- Paper exams: print answer sheets with a QR code, scan them, and the app reads them.
- Students can appeal a mark. Every decision is recorded.

<!-- figure: exam_lifecycle.png (drawn in the Word copy, documents/07_New_Features_Quick_Guide.docx) -->

### 1.2 Question types

| Type | How it is marked |
|---|---|
| Multiple choice, one or several answers | At once. For several answers: "Proportional (right minus wrong)" or "All or nothing" |
| True / false | At once |
| Fill in the blank | At once. You list the accepted answers for each blank; small typos are accepted |
| Matching, Ordering | At once. Students see the items in a different order. Partial credit per pair or per item |
| Numeric | At once. Optional tolerance (± or %) and units |
| Short answer, Essay | The grader proposes a mark from your **marking key**, then the teacher decides |
| File upload | By hand, with your criteria |

### 1.3 Write questions (the question bank)

1. Open your course's Exams page. In **New-engine exams (الاختبارات الجديدة)** tap the **Question bank (بنك الأسئلة)** icon.
2. Tap **Write a new question**. Pick the **Question type**, write the **Question text**, and set **Points**, **Difficulty** and **Tags**.
3. For open answers, fill in the **Marking key (مفتاح التصحيح)**: a **Model answer**, or **Rubric criteria**, or both.
   - Each criterion has a description, points, an optional reference wording and **Keywords** (one per line; write `term = synonym, synonym` for synonyms).
   - The grader marks each criterion separately, so clear criteria give better proposals.
4. Tap **Save to the bank**. Later edits use **Save a new version**: running exams keep their version, and the exam editor shows "Newer version" so you can switch.

Tip: a course teacher who has no exam rights in the organization sees only the questions they wrote.

### 1.4 Build and publish the exam

1. Tap **+ New exam**. The editor has four tabs: **Settings · Sections & questions · Proctoring · Publish**.
2. **Settings**: title, **Opens / Closes**, **Duration (minutes)**, **Attempts allowed**, an optional **Passcode**, **Allowed platforms** (Web, Mobile app), and:
   - **Results visibility**: Hidden from students · Shown after submitting · Shown when you publish them (the default).
   - **High-stakes exam (اختبار مصيري)**: the teacher approves every open mark; results wait for the review.
   - **Anonymous grading**: markers see a code, not the student's name.
   - **Pass mark %**, and **Appeals**: on/off, the window in days (default 14) and the most appeals per attempt (default 5).
3. **Sections & questions**: add a section and pick its **Mode**: **Online**, **Paper** or **Hybrid**. Optional: one-way navigation (no going back), a time box, a weight, shuffling, and a random pool ("draw 10 of 30").
4. **Proctoring**: choose what is monitored and the **Rules**: how many times each signal is allowed, then what happens (Warn the student · Flag for review · Lock the attempt · Submit automatically · Reject the attempt). Defaults: 3 times looking away, once for switching tabs or opening another app. Add **Accommodations** (extra time, large text, screen reader, relaxed proctoring) for specific students.
5. **Publish**: the checklist under **Before publishing** must be clear. Then **Publish the exam**. You can **Unpublish** only until a student starts; after that, **Close the exam**.

Watch out: after publishing, the questions and the section structure are fixed. Once students start, the duration and attempts are fixed too.

### 1.5 What the student sees

1. Course → **Exams** tab → **Course exams**. Each exam shows its duration and "Attempts used/allowed".
2. Tap **Start exam** (enter the passcode if asked).
3. **Before the exam**: the consent text says exactly what is monitored. If no camera or microphone is used, the screen says so. Tap **I have read and I agree**, then **Accepted — start**.
4. During the exam: the minutes left, "Question 3 of 20", and a save indicator (**All answers saved** / **Saving 2 answers**). A warning appears when a proctoring rule is hit ("Warning: … was recorded").
5. Leaving is safe: "Your answers are saved and you can continue later." Use **Resume attempt** on the same device.
6. At the deadline the server submits on its own: "Time is up — your saved answers were submitted".
7. The result screen shows the score, **Passed / Not passed**, per-question marks, or "The result is not available yet — it appears when the teacher publishes it."

### 1.6 Automatic marking and the review queue

<!-- figure: grading_decision.png (drawn in the Word copy, documents/07_New_Features_Quick_Guide.docx) -->

1. Tap a published exam → **Review marking (مراجعة التصحيح)**. The lowest confidence comes first.
2. Each card shows the student's answer, the **Proposed** mark, a **Confidence** % and warning tags such as "Negation against the model answer", "Roles swapped between concepts" or "Handwriting reading uncertain — check the text".
3. Tap **Accept**, or **Edit score** to mark criterion by criterion and add a **Comment for the student (optional)**.
4. When many proposals are confident, a banner offers to **Approve** them all at once (recorded under your name).
5. **Grading policy** (the tune icon): "Accept confident proposals automatically", the confidence bar, **Double marking** (two markers, a moderator when they disagree), "Show per-criterion feedback to students", and whether the sheets are handwritten or printed.

The real rules:

- The grader **never** accepts on its own on a high-stakes exam, with double marking, when it is unsure of a scanned handwriting reading, or when it sees roles swapped between concepts.
- With the default bar ("Default threshold (from the benchmark)") the bar is set so high that today **every open answer comes to you as a proposal**. If you pick a lower bar (90 %, 95 % or 98 %), proposals above it are accepted automatically on normal exams. You can still change them.
- Results cannot be published while attempts wait for review: "Attempts wait for marking review before results can be published".

### 1.7 Paper exams with scanned answer sheets

<!-- figure: paper_flow.png (drawn in the Word copy, documents/07_New_Features_Quick_Guide.docx) -->

1. Give the exam a **Paper** or **Hybrid** section.
2. **Review marking → Scanned pages** → **Answer sheets**: download QR-coded sheets for each student, or blank ones, as a PDF.
3. After the exam, **Upload scans**: images or PDFs (PNG, JPEG, WebP, PDF). Up to 50 files at a time; one upload may hold up to 25 MB and 300 pages. Pages are matched to students by the QR code.
4. A page whose code could not be read shows "Unmatched — choose the student". Pick the student and tap **Assign**. Or use a **Mapping file** (CSV or Excel with `student_id` and `file_name`).
5. Open a page: the original image sits next to the text that was read. Correct the text and tap **Save text**: it is marked again.
6. Fully offline exam? **Import marks** from a file with `student_id`, `question_id` and `score` (up to 5000 rows).

Tips: take sharp, well-lit photos. The app warns "The photo is blurred", "too dark" or "Low contrast". Handwritten Arabic is hard for the reader, so always check the text before you accept a mark.

### 1.8 Results, appeals and analytics

- **Publish results**: Publish tab → **Publish results to students**. Students see them according to the results policy.
- **Student**: on the result screen, tap a question → **Request a regrade** → write the reason (at least 10 characters) → **Send the request**. The appeal shows as Open → In review → Accepted / Rejected, with the teacher's note.
- **Teacher**: Review marking → **Appeals** → **Start review** → **Decide**: **Accept, change the score** or **Reject**. The reason is required, and the student sees it. If "Independent reviewer" is on, someone other than the original marker must decide.
- **Analytics**: Review marking → **Analytics** → **Compute now**. You get the score distribution, reliability, each question's difficulty and discrimination ("Too hard", "Too easy", "Negative discrimination — check the key"), and **Signals worth a look** (very similar answers, very fast high scores, proctoring risk). Signals are for human review only. Nothing is penalised automatically.

### 1.9 Messages you may see

| Message | What it means / what to do |
|---|---|
| Continue the exam on the device you started it on | The attempt is tied to the first device. Go back to it |
| The exam session expired — reopening | Normal after a long pause. The app renews it by itself |
| Not all your answers are saved yet — check the connection and submit again | You are offline. Reconnect, then submit |
| The attempt is locked — contact the invigilator | A proctoring rule locked the attempt |
| You can appeal once the result is visible / The appeal period has ended | Appeals open after results show, for the set number of days |
| The grading queue is full — try again shortly | Many scans are being read. Upload again in a few minutes |
| The exam service is not available on the server yet | The new exam engine is not installed on this server |

## 2. The documents assistant (RAG)

Members ask questions in plain language. The assistant answers **only from your organization's or course's documents**, quotes them and shows where each part came from. If the answer is not in the documents, it says so instead of guessing.

<!-- figure: rag_flow.png (drawn in the Word copy, documents/07_New_Features_Quick_Guide.docx) -->

### 2.1 Ask a question (every member)

1. In the organization screen tap the book icon, **Documents assistant (مساعد المستندات)**. For a course: course profile → **Ask the course documents**.
2. Type in **Your question** (up to 1000 characters) and tap **Send**. You see "Searching the documents…" for a few seconds.
3. The answer carries numbered marks like [1]. Under **Sources** each source names the document, the section and the page.
4. "Not found" answers have a search-off icon: the documents do not cover your question. Ask differently, or ask a staff member.
5. Rate the answer: **Helpful** or **Not helpful**. Library managers see unhelpful questions (without your name) so they can fix the documents.

Limits: 10 questions a minute per person. You only get answers from documents you are allowed to see.

### 2.2 Build the library (library managers)

Library managers are organization admins, staff with the right to manage materials, and a course's teachers for that course's documents. Only they see the **Documents library (مكتبة المستندات)** button.

1. Documents assistant → **Documents library** → **Upload**.
2. Give a **Title**, choose who may read it (**Every member** · **Staff only** · **This course only**) and pick the file: PDF, DOCX, TXT, MD, HTML or an image. Up to 30 MB per file.
3. Status goes **Queued → Processing → Ready**. Only Ready documents are used for answers. **Failed** usually means a damaged or password-protected file.
4. Per document: **Download**, **New version** (replaces the old one), **Reindex**, **Archive** (removed from search at once).
5. **Unhelpful answers** lists questions that did not help. Add or fix a document.
6. **Answer settings**: by default the assistant **quotes the documents directly**. "Written by a language model" can be chosen only when the server has one; "Allow an external provider" is a separate choice for the organization admin. A change applies to new questions only.

Tips: documents with clear headings ("Article 5", numbered sections) give the best answers. Scanned PDFs are read by text recognition, so a text PDF is better.

### 2.3 Library quota (super admin)

1. Admin dashboard → People & messages → **Organizations** → open the organization → **Assistant library quota (حصة مكتبة المساعد)**.
2. For documents and for storage (MB) choose **Platform default**, **Unlimited** or **A limit of its own**, then **Save**.
3. The library shows its usage, for example "12 / 50 documents". When it is full, uploads stop with "The library is full — archive documents to make room".

### 2.4 Messages

| Message | Meaning |
|---|---|
| Too many questions — wait a minute | More than 10 questions in a minute |
| The assistant is busy — try again shortly | Many people are asking at once |
| The assistant is still working on your answer — refresh in a moment | Tap Refresh |
| The file is larger than 30 MB / Unsupported type | Pick a smaller file or a supported type |
| The assistant is unavailable: this organization is deactivated | See section 5 |

## 3. Security you will meet

### 3.1 Two-step verification (MFA)

**Who:** super admins, admins, developers, organization admins and organization staff can turn it on. The platform can make it **required** for some roles: then the app opens the setup by itself after you sign in, and nothing else works until you finish it.

<!-- figure: mfa_setup.png (drawn in the Word copy, documents/07_New_Features_Quick_Guide.docx) -->

To turn it on:

1. Install an authenticator app on your phone (for example Google Authenticator or Microsoft Authenticator).
2. Profile → **Security (الأمان)** → **Two-step verification (التحقق بخطوتين)**. In an organization: Settings ("More" on phones) → Security. Platform admins: Admin dashboard → Support & security.
3. Tap **Turn on two-step verification** and confirm your password.
4. **Scan the code with an authenticator app**, or **Copy the key** and type it in by hand.
5. Type the 6-digit code from the app → **Confirm and turn on**.
6. You get **10 recovery codes**. Copy them and keep them somewhere safe, then tap **I saved them, done**. You are signed out on your other devices.

Signing in afterwards: password (or Google) → "Type the 6-digit code" → **Verify**. After 5 wrong codes you must **Sign in again**.

**Lost your phone?** Tap **No access to the app? Use a recovery code** and type one (16 letters and digits; each works once). Then make new codes with **Make new recovery codes**.

**Lost the phone and the codes?** A super admin opens the person in an admin user list (for example Teachers or Admins) → **Reset two-step verification**. The person is signed out everywhere and sets it up again.

### 3.2 "The server is busy right now — try again in a moment"

This is not an error in your work. When too many heavy requests (exams, assistant) arrive at once, the server asks you to wait a few seconds. Your exam answers are kept and saving retries automatically.

## 4. Download my data

1. Profile → **Download my data (تنزيل بياناتي)** → **Request a copy of my data**.
2. The status shows **Being prepared**. The page updates by itself; a small account is ready in seconds, a large one may take a few minutes.
3. When it says **Ready to download**, download the file.

What is inside: a ZIP with one JSON file per part of your data (account, courses, payments, attendance, exams, questions, notifications, complaints, devices, organizations, consents) and a file that explains each one in Arabic and English. Exam scores are included only once they are released to you. Other people's names are replaced by their role.

Limits: one copy every 24 hours. The file is deleted after 3 days. A super admin in "view as" mode cannot download someone else's data.

## 5. Short items

**Organization status.** When the platform suspends an organization, or it is still under review, its exams and its documents library close for everyone in it. When a university is **deactivated**, its faculties and departments close for students too, while staff can still manage. Students see messages such as "The organization is not active right now (suspended or under review)" or "This organization is deactivated". Changes take effect within a few seconds.

**Private links to sensitive files.** Teacher ID and qualification scans, complaint attachments and payment proofs can be stored privately (the platform owner switches this on). Their links then **expire after 10 minutes**. If an image no longer opens, close the screen and open it again to get a fresh link. Links inside an export file expire too.

**Refunds (admins).** Admin dashboard → Finance & requests → **Payments** → open a completed payment → **Refund**. You can refund all of it or part of it; the screen shows what is "Left to refund". If the gateway has not confirmed yet, the refund stays **Pending** and is reconciled automatically. Use "Resolve a pending refund" in the top bar to check it now. Manual refunds are for the super admin only, with a reason.

| Refund message | Meaning |
|---|---|
| The amount is more than what is left to refund | Part of it was already refunded |
| A refund is already in progress for this payment | Wait for the first one to finish |
| A refund made in the gateway dashboard was just recorded — check what is left, then try again | Someone refunded in the gateway directly |
| The gateway cannot refund by API — use a manual refund | Super admin: record a manual refund |
