# Student lifecycle in Egyptian universities — research report

Prepared 2026-11-21 for the design of the student-lifecycle module (statuses, admission routes, progression rules) serving Egyptian public, private, national (ahlia) and Azhar institutions.

**How to read this report.** Every rule is tagged:

- **Confirmed [Sx]**: read in the cited source (law text, Official Gazette scan, or a published university/faculty bylaw). Article numbers are given where the source states them.
- **Unverified / practice**: common practice, news reports, or a source whose text could not be read in full. Treat as a default to make configurable, never as a hard rule.

The legal hierarchy matters for the product. Law 49/1972 art. 167 says the Executive Regulation (اللائحة التنفيذية, Decree 809/1975) sets "the general common bases of the study and enrolment systems and of the examination systems, their chances and grades", and **each faculty's internal bylaw (اللائحة الداخلية) sets the detailed rules** within that frame (art. 167 §2, art. 197) [S1]. So almost every number below is a per-faculty (often per-programme) setting, bounded by a few national rules.

---

## Sources

| ID | Source | URL | What was read |
|---|---|---|---|
| S1 | Law 49/1972 on the Organization of Universities (full text, UNESCO HEPO copy) | https://hepo.iesalc.unesco.org/pc/static/countrydocs/cp/2025/egy/egy_HELawLi.pdf | Full text; arts. 167–173, 196–197 quoted |
| S2 | PM Decree 82/2015 replacing Exec. Reg. art. 74 (Official Gazette no. 3 bis, 17 Jan 2015) | https://manshurat.org/node/3473 (scan: https://manshurat.org/file/6025/download?token=5cfAmpYk) | Full scan read |
| S3 | PM Decree 1474/2015 replacing Exec. Reg. art. 80 (Official Gazette no. 27, 2 Jul 2015) | https://manshurat.org/node/4346 (scan: https://manshurat.org/file/7579/download?token=vLCq85pI) | Full scan read |
| S4 | Supreme Constitutional Court ruling upholding art. 80 §1 | https://www.manshurat.org/node/24526 | Summary page |
| S5 | Damietta University, General Administration of Education & Student Affairs: suspension of enrolment and exam excuses | https://www.du.edu.eg/upFilesCenter/uni/1470581944.pdf | Full |
| S6 | Assiut University, undergraduate admission / enrolment / transfer / suspension rules | https://www.aun.edu.eg/student/sites/default/files/Undergraduates_0.pdf | Full (digits in the PDF are font-garbled, so its article numbers are NOT relied on) |
| S7 | Assiut University, examination system | https://www.aun.edu.eg/student/sites/default/files/Exams.pdf | Full (same digit caveat) |
| S8 | Assiut University, Faculty of Computers: exam rules + student discipline | https://life.aun.edu.eg/fci/sites/default/files/extra%20data%20for%20exam.pdf | Full |
| S9 | Cairo University Faculty of Law, student guide 2024–2025 (LL.B. credit hours, postgraduate bylaw, and the Exec. Reg. discipline articles 123–129) | https://law.cu.edu.eg/storage/articles/kGXi5rvvbuj4kFX5VyYULBlkqeijyTqvnDTS38tS.pdf | Relevant chapters |
| S10 | Ain Shams University Faculty of Engineering, 2023 bylaw brief for international credit-hour programmes | https://eng.asu.edu.eg/public/archive/download/1750457 | Arts. 17–35 |
| S11 | Sohag University Faculty of Engineering, student guide 2025/2026 (credit hours) | https://eng.sohag-univ.edu.eg/main/wp-content/uploads/2026/02/22025-2026-%D8%AF%D9%84%D9%8A%D9%84-%D8%A7%D9%84%D8%B7%D9%84%D8%A7%D8%A8-%D9%87%D9%86%D8%AF%D8%B3%D8%A9-%D8%B3%D9%88%D9%87%D8%A7%D8%AC.pdf | Sections 22–30 |
| S12 | Beni-Suef University Faculty of Arts, internal bylaw (licence stage, level + credit system) | https://arts.bsu.edu.eg/Backend/Uploads/PDF/Arts/%D9%82%D8%B3%D9%85%20%D8%B9%D9%84%D9%88%D9%85%20%D8%A7%D9%84%D9%85%D8%B9%D9%84%D9%88%D9%85%D8%A7%D8%AA/0%D9%84%D8%A7%D8%A6%D8%AD%D8%A9%20%D9%84%D9%8A%D8%B3%D8%A7%D9%86%D8%B3%20l-2-28.pdf | Arts. 20–41 |
| S13 | Mansoura University Faculty of Engineering, postgraduate credit-hour bylaw | https://engfac.mans.edu.eg/images/files/engpdf/highstudy/programs/public.pdf | Arts. 12–16, supervision |
| S14 | Ain Shams University, equivalent (foreign) certificates admission page 2024–2025 | https://www.asu.edu.eg/1166/page | Full |
| S15 | Assiut University, admission of incoming international undergraduates | https://aun.edu.eg/student/node/33927 | Full |
| S16 | Study in Egypt portal, "how to apply" | https://study-in-egypt.gov.eg/ar/how-to-apply | Full (steps only) |
| S17 | Assiut University Faculty of Engineering, announcement of SCU technical-diploma tests 2025/2026 | https://www.aun.edu.eg/engineering/sites/default/files/news/-2025%D8%A7%D8%B9%D9%84%D8%A7%D9%86%20%D8%B1%D9%82%D9%85%202.pdf | Full |
| S18 | Masrawy, 20 Feb 2021, SCU decision citing art. 80 | https://www.masrawy.com/news/news_egypt/details/2021/2/20/1974004 | Full |
| S19 | Al-Mal News, Ministry rules for corresponding / non-corresponding transfers (تقليل الاغتراب) | https://almalnews.com/2135261/ | Search snippet only |
| S20 | Akhbar El-Yom, SCU guide to admission to paid special programmes 2026 | https://m.akhbarelyom.com/news/newdetails/4860652/1/ | Search snippet only |
| S21 | Azhar: Law 103/1961 and its Exec. Reg. 250/1975 (records) | https://manshurat.org/node/46462 ; https://lawyeregypt.net/%D8%A7%D9%84%D9%84%D8%A7%D8%A6%D8%AD%D8%A9-%D8%A7%D9%84%D8%AA%D9%86%D9%81%D9%8A%D8%B0%D9%8A%D8%A9-%D9%84%D9%82%D8%A7%D9%86%D9%88%D9%86-%D8%AA%D9%86%D8%B8%D9%8A%D9%85-%D8%A7%D9%84%D8%A7%D8%B2%D9%87/ | Arts. 1–100 (institutes only) |
| S22 | Law 12/2009 on Private and Ahlia Universities (text copy) | https://alberonsy.com/?p=3301 | Not read in full (search snippet) |
| S23 | MSA University (private) rules page | https://msa.edu.eg/msauniversity/computer-sciences-student-life/computer-science-rules-and-ethics | Search snippet only (page 404 on fetch) |
| S24 | Youm7, 2 Jun 2015, SCU approves art. 80 change | https://www.youm7.com/story/2015/6/2/الأعلى-للجامعات-يقرر-فصل-الطالب-حال-رسوبه-4-سنوات-فى/2207367 | Search snippet only |

---

## 1. Admission routes (طرق القبول)

### 1.1 National framework

- **Confirmed [S2]** — Exec. Reg. art. 74 (as replaced by PM Decree 82/2015): the Supreme Council of Universities (المجلس الأعلى للجامعات, SCU) fixes at the end of each academic year, on the proposal of university councils after hearing faculty councils, the number of Egyptian students admitted to each faculty "from among holders of the Thanaweya Amma or an equivalent certificate". The SCU also fixes the number of non-Egyptians; **their admission is by decision of the Minister of Higher Education, and their transfer and transfer of enrolment (تحويلهم ونقل قيدهم) is by his decision too**.
- **Confirmed [S6]** (quoting the Exec. Reg. conditions of enrolment, article number not readable in that PDF): to be enrolled for a licence/bachelor the student must
  1. hold the Thanaweya Amma or an equivalent, admission being by rank of marks with geographic distribution as set by the SCU; commerce faculties may admit commercial secondary holders, agriculture agricultural, engineering industrial, nursing the general-nursing certificate, and some faculties technical-institute diploma holders, all under SCU rules;
  2. pass a medical examination (الكشف الطبي) proving freedom from infectious disease and fitness for the chosen study;
  3. if employed (government or other), present a permit from the employer to study as a regular student;
  4. be of good conduct (محمود السيرة حسن السمعة).
  A student may not be enrolled in more than one faculty at the same time [S6].
- **Confirmed [S1]** — Law 49/1972 art. 169: education is free for Egyptians at all university stages; non-Egyptians pay tuition set by the Exec. Reg.; all students pay service fees (رسوم الخدمات).

### 1.2 Routes, one by one

| Route | Rule | Status |
|---|---|---|
| **Coordination Office (مكتب التنسيق) — Thanaweya Amma** | Nomination (ترشيح) by the central electronic coordination by total score + preferences + geographic distribution; the faculty then enrols the nominated student. Qualifying subjects per faculty (e.g. Assiut: medicine/pharmacy/vet/dentistry/nursing need chemistry, biology, physics; engineering/computers need chemistry, physics, math 2). | Confirmed [S6] |
| **Equivalent certificates (الشهادات المعادلة)** — IGCSE/British, American diploma, others | Apply through the same Coordination Office; American diploma: ≥ 8 subjects (≤ 3 from G11, ≥ 5 from G12), SAT I ≥ 1050 for government faculties, EST2/ACT2 ≥ 1100 for medical and engineering sectors; IGCSE: 8 subjects at grade C(4)+ across ≤ 5 sittings in the last 3 years, plus A-level/AS requirements per sector (biology for medical, math for engineering); documents authenticated by British Council / AMIDEAST + Foreign Ministry. | Confirmed [S14] |
| Equivalent certificates: quota | Assiut quotes an SCU rule that admitted holders of any foreign equivalent certificate in a faculty may not exceed a percentage of the number set for foreign-certificate holders (figure garbled in the PDF). Holders who fail Arabic and religion at the Egyptian Thanaweya committees must pass a **complementary exam (امتحان تكميلي)** in both during their studies and get no degree until they do. | Confirmed (rule) / number unverified [S6, S7] |
| **Technical diploma holders (الدبلومات الفنية)** | SCU-run equivalency tests (اختبارات الدبلومات والمعاهد). 2025/26 rules: one chance only within two consecutive years from the year of the diploma; 3-year industrial diploma holders need ≥ 70 % total to sit the engineering test; 5-year diploma and 2-year technical institute holders also eligible; passers join the **preparatory year (الفرقة الإعدادية)** of public engineering faculties or **level 1** of computing/AI faculties; failed applicants can petition on the SCU site; fees non-refundable. | Confirmed [S17] |
| Technical diplomas via coordination | Assiut lists coordination-office admission for technical secondary holders as a separate route from the equivalency exam. | Confirmed [S6] |
| **Second-degree holders (حملة المؤهلات العليا)** | Exec. Reg. allows admitting licence/bachelor holders into another faculty, department or branch under the internal bylaw's conditions, approved by the university president; an SCU decision makes them pay tuition. | Confirmed [S6] (fee figure not readable) |
| **Affiliation (الانتساب)** | Exec. Reg. allows affiliation to Law, Arts, Commerce and Social Work for licence/bachelor; conditions: good conduct, Thanaweya Amma (or equivalent) **in the same year**; exceptionally former students of other faculties, Azhar, military colleges or higher institutes; graduates may also affiliate. Affiliated students are exempt from attendance rules in some bylaws (e.g. Cairo Law's 25 % absence bar "does not apply to affiliated students"). | Confirmed [S6, S9] |
| **Directed affiliation (الانتساب الموجه)** | Paid affiliation in Arts, Law, Commerce, Social Work; Thanaweya in the same year; may transfer to a corresponding faculty in another university; may convert to **regular (منتظم)** in any year if the student has at least **"Good" (جيد)**; keeps military deferment. Students **dismissed for exhausting failure chances** may be admitted as directed-affiliation students in non-corresponding faculties (SCU decision). | Confirmed [S6] |
| **Ex-military / police college students** | Students dismissed from military colleges for unfitness (not for discipline or exhausted chances) are admitted as regular students if they had the faculty's minimum in their Thanaweya year; resignees admitted the following year; students dismissed **for discipline** from university faculties are admitted only after re-sitting the Thanaweya. | Confirmed [S6] |
| **Students with disabilities** | Separate admission route (blind, disabled, deaf). | Confirmed [S6] (details not extracted) |
| **Transfers (التحويل / نقل القيد)** | See §1.3. | |
| **International students (الوافدون)** | Apply on the Study in Egypt platform (account → programmes → university education → apply; separate postgraduate service); choose up to 10 faculty preferences; pay service fees after initial nomination; submit original documents to the university (or to the Central Administration for Foreign Students Affairs, الإدارة المركزية لشئون الطلاب الوافدين, for institutes/academies); nomination cancelled without refund if the original file differs; name must match passport or refugee card. Admission is by ministerial decision (art. 74) [S2]. | Confirmed [S15, S16, S2] |
| **Paid special programmes at public universities (البرامج الخاصة بمصروفات / برامج الساعات المعتمدة)** | SCU publishes a yearly guide; each programme's admission conditions come from its approved internal bylaw. Ain Shams Engineering: free-education students in "Specialized Programs" may move to paid "Inter-Disciplinary Programs" fee-free with GPA ≥ 3.85 (and keep it while ≥ 3.85); inter-disciplinary students may move to specialized majors with GPA ≥ 3.7. | Confirmed [S10]; guide existence [S20] snippet only |
| **Private universities (الجامعات الخاصة)** and **national/ahlia universities (الجامعات الأهلية)** | Governed by Law 12/2009 and its executive regulation, not Law 49/1972; a ministerial decree (no. 10 of 2021) set a unified electronic admission system for private and ahlia universities, with each university's own admission tests; minimum scores set yearly by the Council of Private Universities. | Unverified (search snippets of S22 and news; law text not read) |
| **Al-Azhar University** | Law 103/1961 and Exec. Reg. 250/1975; the Supreme Council of Al-Azhar holds, for the university, the powers the SCU holds for other universities (Reg. art. 11). Separate Azhar coordination after Azhari Thanaweya results; some faculties require admission tests (e.g. Da'wa, Qur'an faculties). Azhar faculties are single-sex (boys / girls) in practice. | Art. 11 confirmed [S21]; the rest unverified (news) |
| **Postgraduate** | See §1.4. | |
| **Open education (التعليم المفتوح)** | SCU decided (26 Mar 2011) that suspension, transfer and excuse rules for open-education students follow Law 49/1972. | Confirmed [S5]. That open education was later replaced by "blended learning" (التعليم المدمج) is unverified. |
| **Visiting / non-degree / audit students** | Ain Shams Engineering: degree and non-degree students may register courses as audit (no GPA, no final exam) for a fee; up to 40 % of credits may be studied at a partner university with credit transfer. Law art. 170 lets the university president exempt a student from courses already passed at a recognised institution, **except final-year courses**. | Confirmed [S10, S1] |
| **Listener (مستمع)** | Exec. Reg. art. 123 lists listeners (المستمعون) among students subject to discipline, so the category exists. | Confirmed [S9] |

### 1.3 Transfers (التحويل ونقل القيد)

- **Confirmed [S6]** (Assiut, quoting SCU decisions):
  - Preparatory / first-year students may transfer between **corresponding** faculties only if they reached the faculty's minimum and capacity allows, with both faculty councils' approval; first-year transfers run through the **electronic coordination** ("تقليل الاغتراب"). Non-corresponding transfers need the target faculty's minimum. Transfers to new programmes / language sections go through universities within the sector minimum; transfers for an administrative move of the guardian or for medical reasons go directly through universities.
  - Other years: transfer to the corresponding faculty in the same or another university with both councils' approval; the request is filed **before the start of study** at the target faculty, and the student must have **passed and been promoted**; the faculty council may accept later "in extreme necessity".
  - Transfer to a non-corresponding faculty in the same university is possible; the internal bylaw decides which passed courses are credited.
  - Every transfer / move of enrolment is approved by the **university president** (or deputy).
  - Students of institutions outside Law 49/1972 cannot transfer in, except by the Minister in extreme necessity.
- **Practice [S19, snippet]**: electronic only, one request, within a 10 % share and capacity, a few days in August after nomination.
- **Confirmed [S11]** (Sohag Engineering, credit hours): external transfer in only to **level 1**, not repeating or "from outside"; GPA ≥ 2.0 (credit-hour origin) or "Good" (two-term origin); not disciplinarily dismissed (if discovered later, dismissed from the transfer date); students dismissed for exhausted warnings or chances may not transfer in; course equivalence (مقاصة) only for grades ≥ C / جيد. Internal change of programme: once only, before passing 50 % of graduation requirements; if placed in the same level, the student counts as repeating (باق للإعادة) and the year counts as a failure year.

### 1.4 Postgraduate (الدراسات العليا)

- **Confirmed [S1]**: art. 197 §7 — the internal bylaw sets postgraduate enrolment dates, master/PhD registration procedures and **cancellation of enrolment and registration (إلغاء القيد والتسجيل)**; art. 171 allows exemption from postgraduate courses already passed elsewhere (degree must last > 1 year); art. 168 thesis language and bilingual abstract.
- **Confirmed [S9]** (Cairo Law, credit hours): diploma load 12–15 CH per main term, ≤ 6 in summer; diploma min 2 terms, max 6 terms (two summers = one term); credit transfer ≤ 25 % of courses, passed ≤ 5 years earlier. Master registration: holds a postgraduate academic diploma (or preparatory year); topic from the department's research plan; department council nominates supervisors (professors / associate professors; a lecturer only as co-supervisor); faculty council decision appoints them; registration counts from that decision; registration opens twice a year; supervisor reports to the department every 6 months and the faculty council may **strike the registration (شطب التسجيل)** on that report; registration is struck if fees are not paid within a month of the new year. PhD: holds the master (or two academic diplomas in private/public law), a seminar before at least 3 staff, same supervision rules. Withdrawal (W) weeks 2–4; postponement (التأجيل) up to 2 terms after at least one term; enrolment cancelled if the student withdraws from all courses in the first term, exceeds the maximum terms, or commits a dismissal offence; re-enrolment through admission procedures, record kept.
- **Confirmed [S13]** (Mansoura Engineering, credit hours): durations in main terms (table, read as min / max / extension): basic diploma 1/2/+1, advanced diploma 2/4/+1, master 4/6/+2, PhD 6/10/+2; maxima double for part-time students. Suspension (وقف القيد) one academic year, extendable by the university postgraduate council to **3 years** maximum, for illness, accompanying a spouse abroad, military call-up, child care, work missions, others accepted; fees still due. Cancellation (إلغاء القيد) by the university postgraduate council on: failing a course twice / not reaching the minimum, exam misconduct, repeated supervisor warnings, a jury report that the thesis is unfit, own request, exceeding the maximum duration, non-payment. Re-enrolment after at least one calendar year. Supervision committee ≤ 3 members (master) / ≤ 5 (PhD), no kinship to the fourth degree.

---

## 2. Registration and enrolment (القيد والتسجيل)

- **Confirmed [S6]**: the student is enrolled on an application filed **before the opening of study**; later enrolment needs the faculty council's permission within university-council rules. Enrolment follows completion of documents and payment of fees. The faculty keeps a **file** per student (enrolment papers; study history with dates of enrolment, exams, results, grades; disciplinary penalties; sports, social and military activities) and a **register** in two copies (faculty + university) also recording the date and reason of leaving and post-graduation work.
- **Documents (new student, Thanaweya route) — Confirmed [S6]**: application; the Thanaweya success form; birth certificate or official extract; photographs with the seating number written on each; preference card; **Form 2 Military (استمارة 2 جند) for males only**. Medical examination [S6]. The **military status (الموقف من التجنيد)**: the military service card / status is submitted after nomination; a new student aged 19 presents the military service card at enrolment; one over 22 on 1 September of the entry year must prove his military status; if conscripted, the faculty keeps his place until service ends (on notification with a unit certificate).
- **Equivalent-certificate documents — Confirmed [S14]**: application, original birth certificate, copies of student and guardian national IDs, full schooling sequence, certificates authenticated as above, passport copy and proof of residence abroad where relevant; for these applicants **Form 2 Military and photos are NOT required at the coordination stage**.
- **Annual / per-term registration**: in credit-hour systems the student registers courses each term with the academic advisor; not registering counts as withdrawal from the term unless an excuse is accepted within two weeks (Sohag) [S11]; not registering for more than two main terms without excuse → dismissal (Ain Shams) [S10].
- **Fees (high level)**: free tuition for Egyptians in regular public programmes, service fees for all, tuition for non-Egyptians [S1 art. 169]; paid tracks (directed affiliation, special / credit-hour programmes, second-degree holders) charge tuition [S6, S10]. Amounts: not researched (they change yearly).

---

## 3. Study systems (نظم الدراسة)

### 3.1 Traditional year system (نظام الفرق الدراسية / نظام الفصلين)

- The degree is organised in **years (فرق)**: optional preparatory year (الفرقة الإعدادية, e.g. engineering) then years 1..N (4 to 6+). Promotion happens **only at the end of the academic year**, and a passed course is never re-examined at licence/bachelor level — **Confirmed** (Assiut quoting the Exec. Reg.) [S7].
- Many faculties now run the year in **two terms (نظام الفصلين)** with exams each term but promotion still yearly; a **second round (الدور الثاني)** in Sept–Nov exists in some (Damietta mentions second-round exams) [S5].

### 3.2 Credit-hour system (نظام الساعات المعتمدة)

- **Levels by earned credits — Confirmed [S10]**: Ain Shams Engineering: each 25 % of programme credits moves the student up a level (Freshman 0–<25 %, Sophomore 25–<50 %, Junior 50–<75 %, Senior 75–<100 %). Variant: Cairo Law organises 4 levels / 8 terms but promotes by year with up to 2 failed courses carried (§4.1) [S9].
- **Terms — Confirmed**: two main terms (Fall, Spring), 16 weeks including finals, plus an optional **summer term** of ~8 weeks [S9]; summer often limited to failing students or students who registered below the maximum [S9].
- **Load — Confirmed**:
  - Ain Shams Eng.: main term max 21 CH (CGPA ≥ 3.0), 18 (2.0–3.0), 14 (< 2.0); summer max 9 (≥ 3.0) / 8 (< 3.0); +1 course allowed if it lets the student graduate this term [S10].
  - Sohag Eng.: a student under academic warning may register **max 12 CH** [S11].
  - Cairo Law: up to 6 CH from the next level if prerequisites met and last-level grade ≥ B; summer ≤ 6 CH [S9].
- **Duration — Confirmed**: Ain Shams Eng. min 8 main terms, max 8 academic years (frozen terms excluded), +1 year with a minor, +2 main terms + summer by faculty council if ≥ 75 % of credits passed, then the university council if ≥ 85 % [S10]; Sohag Eng. max 10 academic years [S11]; Cairo Eng. moved fully to credit hours with 154–159 CH (news, unverified).
- **Add / drop / withdraw — Confirmed**: add in week 1 (summer: first 3 days), drop with refund until end of week 2 (summer week 1), withdraw (W) until week 10 (summer week 5) [S10]; Cairo Law: withdraw from at most 2 courses per level by end of week 7 [S9]; Beni-Suef Arts: elective courses only, by end of week 6 [S12].
- **Incomplete (I) — Confirmed**: excused absence from a final → I; exam at the start of the next main term; missing it → F [S10] or **FW (forced withdrawal)** [S9, S12].
- **Attendance**: Cairo Law: 25 % unexcused absence → barred from the final, recorded F; warning at 15 % [S9]; Ain Shams Eng.: ≥ 75 % of tutorial and lab hours required [S10]; Sohag: warnings at 10 % and 20 % [S11]. Exec. Reg. (via Assiut): the faculty council may bar a student from all or part of the exams for unsatisfactory attendance; he is then recorded as failed in those courses [S7].

---

## 4. Passing and progression

### 4.1 Traditional (year) system

- **Grade names — Confirmed (Exec. Reg. via Assiut) [S7]**: pass grades **ممتاز (Excellent), جيد جدا (Very good), جيد (Good), مقبول (Pass)**; fail grades **ضعيف (Weak), ضعيف جدا (Very weak)**. "Applying these grades follows the system set by the faculties' internal bylaws", i.e. the **percentage bands are per faculty**.
- **Percentage bands — Unverified / common practice**: ممتاز ≥ 85 %, جيد جدا 75–<85, جيد 65–<75, مقبول 50–<65, ضعيف 30–<50, ضعيف جدا < 30. No primary bylaw with exactly these bands was retrieved; Beni-Suef Arts uses 85/80/77/74/70/65/60/55/50 (see §4.2), Cairo Law 90/85/80/75/65/50 [S9, S12]. Make it a table per programme.
- **Year grade — Confirmed [S7]**: the overall grade of a year is computed from the course grades, but a course the student **previously failed, or missed without excuse, counts at most مقبول**; with an accepted excuse he gets the grade earned. Degree overall grade = total marks of all years, and **students are ranked by that total** (Exec. Reg. art. 85 as cited by Sohag) [S7, S11].
- **Pass mark**: per course, commonly 50 % (مقبول) — Confirmed for Cairo Law (D from 50 %) and Beni-Suef Arts (D- from 50) [S9, S12]; some bylaws add a minimum in the written final (Ain Shams Eng.: 40 % of the final, otherwise F whatever the total) [S10].
- **Promotion with carried courses (مواد التخلف) — Confirmed [S9, S12]**: Beni-Suef Arts art. 38: promoted if total failed courses (this year + earlier) **do not exceed two**, and not more than two specialised courses of the current level; the result sheet writes "منقول بمقررين"; Cairo Law: a student failing **more than two** courses repeats the level in the failed courses; carried courses are re-examined the next year with the max grade مقبول/D.
- **Repeating (الباقون للإعادة)**: a student who is not promoted stays in the same year/level ("باق للإعادة") and re-sits the failed courses; result written as F + number of remaining courses [S12].
- **Chances (الفرص) and exam from outside (من الخارج) — Confirmed, Exec. Reg. art. 80 as replaced by PM Decree 1474/2015 [S3]** (verbatim):
  > لا يجوز للطالب أن يبقى بالفرقة أكثر من سنتين، ويجوز لمجلس الكلية الترخيص للطلاب الذين قضوا بفرقهم سنتين في التقدم إلى الامتحان من الخارج في السنة التالية في المقررات التي رسبوا فيها، وذلك فيما عدا طلاب الفرقة الإعدادية والفرقة الأولى في الكليات التي ليس بها فرقة إعدادية. ويجوز لمجلس الكلية علاوة على ما تقدم الترخيص لطلاب الفرقة قبل النهائية والفرقة النهائية بفرصتين إضافيتين للتقدم إلى الامتحان من الخارج. وبالنسبة إلى الكليات التي تكون مدة الدراسة بها خمس سنوات على الأقل يعامل طلاب الفرقة الثانية بالكليات التي بها فرقة إعدادية وكذلك طلاب الفرقة الثالثة بالكليات التي ليس بها فرقة إعدادية معاملة طلاب الفرقة قبل النهائية. وإذا تخلف الطالب عن دخول الامتحان بعذر قهري يقبله مجلس الكلية فلا يحسب غيابه رسوباً. ويعتبر الطالب المتغيب عن الامتحان بغير عذر مقبول راسباً بتقدير ضعيف جداً.

  Reading for the product (judgement, derived from the text):
  | Year | Regular years in the year | Outside chances (faculty council) | Max failure years |
  |---|---|---|---|
  | Preparatory, or year 1 where no preparatory | 2 | 0 | 2 |
  | Middle years | 2 | 1 | 3 |
  | Pre-final and final (and, in ≥ 5-year faculties, year 2 with a preparatory / year 3 without) | 2 | 1 + 2 = 3 | 5 |
  After the chances are exhausted the student is **dismissed (مفصول لاستنفاد مرات الرسوب)**; he may still be admitted to directed affiliation in a non-corresponding faculty [S6].
- **What the 2015 text removed — Confirmed [S5, S6, S7]**: the old text let a final-year student who failed no more than half the year's courses sit "until he passes" (unlimited), and limited accepted excuses to 2 (+ a 3rd by the university council). Damietta states the new rule applies to students newly entering a year from **2015/2016**, that there are **no exceptional chances**, and that a pre-final/final student is "exhausted" after all inside and outside chances [S5]. The Supreme Constitutional Court upheld art. 80 §1 [S4]. Some faculties still print the old text (Assiut FCI) [S8] → versioned rule sets needed.
- **Outside students — Confirmed [S5]**: "a student examined from outside is considered dismissed (مفصول) from the faculty and his enrolment cannot be suspended"; he remains subject to discipline (Exec. Reg. art. 123) [S9].
- **Leniency (الرأفة) — Confirmed only as a bylaw concept**: Beni-Suef Arts art. 39 lets the control committee review the result of **one or two courses or the GPA** "in light of the established rules" [S12]. The common "up to N marks / % to pass or lift a grade" rules are **unverified** (no published SCU decision found).

### 4.2 Credit-hour system

- **GPA scales — Confirmed, variants**:
  - **4-point, Cairo Law** [S9]: A 90–100 % = 3.6–4; B+ 85–<90 = 3.4–<3.6; B 80–<85 = 3.2–<3.4 (جيد جدا); C+ 75–<80 = 3–<3.2; C 65–<75 = 2.6–<3 (جيد); D 50–<65 = 2–<2.6 (مقبول); F < 50 (راسب). CGPA equivalents: ممتاز ≥ 3.6, جيد جدا 3.2–<3.6, جيد 2.6–<3.2, مقبول 2–<2.6.
  - **4-point, Ain Shams Eng.** [S10]: F < 60 % of course marks; 40 % minimum in the final assessment.
  - **5-point, Beni-Suef Arts** [S12]: A ≥ 85 = 5; A- 80–84 = 4.5; B+ 77–79 = 4; B 74–76 = 3.5; B- 70–73 = 3; C 65–69 = 2.5; C- 60–64 = 2; D 55–59 = 1.5; D- 50–54 = 1; F 45–49 (ضعيف); plus symbols FW, W, CH (cheating), P (deprived, محروم), I.
  - GPA = Σ(points × CH) / Σ CH; W, I, FW excluded [S9, S12].
- **Minimum CGPA to graduate — Confirmed**: 2.0 (Ain Shams Eng. [S10], Sohag Eng. "2.0 (C)" [S11], Cairo Law "D = 2" [S9]).
- **Academic warning (الإنذار الأكاديمي) — Confirmed, variants**:
  - Ain Shams Eng.: **CGPA** < 2.0 in any main term; counter resets when CGPA > 2.0 [S10].
  - Sohag Eng.: **term GPA** < 2.0 → warning + probation (max 12 CH), lifted at 2.0 [S11].
  - Cairo Law: CGPA below D at the end of any term except the first [S9].
  - Private (MSA): probation at CGPA < 2.0; students who remain on probation are dismissed (snippet) [S23].
- **Dismissal (الفصل) — Confirmed, variants**:
  - Ain Shams Eng. [S10]: GPA < 1.0 in the first three consecutive main terms; (specialised programmes, first level) GPA < 2.0 in four consecutive main terms; term GPA < 2.0 in **six consecutive main terms** (summer excluded); not graduating within the maximum duration; not registering > 2 main terms without excuse. Before dismissal for low GPA, a **final chance** of 2 main terms + summer if ≥ 75 % of credits passed.
  - Sohag Eng. [S11]: exhausting art. 80 chances or a disciplinary decision; new student not reaching CGPA 1.5 after the 4th main term; term GPA < 2.0 in six consecutive main terms; exceeding 10 years; absent 2 consecutive / 3 non-consecutive terms without excuse; one final chance (2 terms + summer) if ≥ 80 % of credits (128 CH) passed. The student is **notified in writing** of every warning and of dismissal.
  - Cairo Law [S9]: by faculty council on the coordinator's proposal when CGPA stays below D despite warning, maximum terms or suspension period exceeded, or a dismissal offence.
- **Course repeat and grade replacement — Confirmed, variants**:
  - Ain Shams Eng. [S10]: improvement repeat of a passed course: **higher grade counts**, max **5** improvement repeats (excluding repeats to leave probation or to graduate), not after completing all credits; failing the repeat cancels the old grade (F). Repeat of a failed course: **grade capped at B+**, the new grade replaces the old in the CGPA, both visible on the transcript; full fees.
  - Sohag Eng.: max 5 improvements [S11].
  - Cairo Law: improvement of max **2 courses** over the whole study; a course failed without excuse and later passed is recorded **D (2.0) regardless of marks** [S9].
  - Beni-Suef Arts: a compulsory course passed at the 2nd attempt or later gets the **minimum D** (unless the absence was excused); a failed elective may be swapped and the new course counts in full [S12].
- **Struggling students (المتعثرون)**: the operative mechanisms are warning → reduced load → final chance → dismissal; the term itself is used informally (not found as a defined status in the bylaws read).

---

## 5. Enrolment changes

| Change | Rules | Source |
|---|---|---|
| **Suspension of enrolment (وقف القيد)** — national rule | "The faculty council may suspend a student's enrolment for **two academic years, consecutive or separate**, during study at the faculty if he presents an acceptable excuse preventing regular study; in case of necessity the **university council** may extend it." Cited as Exec. Reg. **art. 69** by Damietta and Sohag. | Confirmed text [S5, S6, S11]; article number from two university sources, not checked in the Gazette |
| Suspension — practice | Whole academic year, not a term (Assiut); accepted cases: conscripts, seconded workers abroad (yearly proof), accompanying a spouse abroad, prisoners (Assiut); politically detained, chronic psychiatric illness (open-ended), child care, parent care, work abroad (Damietta); request with official papers only. Credit-hour variants: 4 main terms (Ain Shams Eng.), ≤ 2 consecutive terms and ≤ 3 non-consecutive, request by week 7 (Cairo Law), by week 8, not in level 1, not for repeating students or scholarship internationals, not if absent without excuse the year before (Beni-Suef Arts); not during finals or the student fails all registered courses (Sohag). Suspension time does not count toward the maximum duration [S9, S10, S12]; fees may still be due [S12]. Outside (من الخارج) students cannot be suspended [S5]. | Confirmed [S5, S6, S9–S12] |
| **Exam excuse (العذر)** | Absence with a compelling excuse accepted by the **faculty council** is not counted as a failure; unexcused absence = fail with ضعيف جدا [S3]. No limit on the number of accepted excuses since the SCC ruling of 7 Oct 1999 and the 2015 text [S5]; Damietta still sends a **third excuse** to the education & student affairs council. Medical excuses go to the university medical administration (government hospitals only); requests before, during, or within **2 days** after the exam; excused absence in both terms of a year = one year's excuse. With an accepted excuse the student keeps his full grade when he sits the exam [S8]. 2021 COVID: a student could ask before exams to be excused from all of the term's exams, treated as an accepted art. 80 excuse [S18]. | Confirmed |
| **Postponement / deferral (التأجيل)** | Credit hours: up to 4 main terms (Sohag), not for new/transferred students in their first year; compulsory during military service [S11]; postgraduate up to 2 terms [S9]. In the traditional system "deferral" is mostly handled as suspension or excuse. | Confirmed [S9, S11] |
| **Withdrawal from the faculty (الانسحاب / سحب الملف)** | Student settles all financial and material obligations, applies in person or by certified proxy (Beni-Suef Arts) [S12]; cancellation at the student's request with guardian approval (Sohag) [S11]. | Confirmed |
| **Re-enrolment (إعادة القيد)** | Beni-Suef: after suspension at own request, at least one year after the request, passed courses kept [S12]; Cairo Law: after interruption ≤ 2 years and CGPA ≥ D, faculty council approval, record kept [S9]; Sohag: within one year of cancellation, 4 weeks before term, faculty council + university councils; treated like a new student of that level and **the year counts as an unexcused failure** [S11]. Not returning after suspension = unexcused absence [S12]. | Confirmed |
| **Dismissal (الفصل)** | Academic: exhausted chances (art. 80), GPA rules, maximum duration, unexcused absence terms (§4). Disciplinary: see below. | Confirmed |
| **Discipline (التأديب) — Exec. Reg. arts. 123–129** | Applies to enrolled, affiliated, outside and listener students (art. 123). Offences (art. 124): disrupting order, organised boycott of classes, dishonourable acts, exam misconduct/cheating, damaging property, unauthorised associations, leaflets/wall papers/signatures, sit-ins or demonstrations against public order. Cheating caught in the act (art. 125): removed from the exam, barred from the rest of the session, **failed in all courses of that session**, referred to the disciplinary board; a degree already granted is void if cheating is later proven. Penalties (art. 126, 13 steps): oral/written notice; warning; deprivation of some student services; deprivation from attending a course up to 1 month; suspension from the faculty up to 1 month; deprivation from exams in one or more courses; suspension of master/PhD enrolment up to 2 months or a term; cancellation of the exam in one or more courses; suspension up to a term; deprivation from exams for one or more terms; deprivation from master/PhD enrolment for a term or more; suspension for more than a term; **final dismissal from the university**, communicated to all universities and barring enrolment or exams anywhere in Egypt; decisions (except oral notice) kept in the student file; guardian informed; university council may review a final dismissal after ≥ 3 years. Competent bodies (art. 127): professors/associate professors — first 4 penalties; dean — first 8 (all in disturbances, subject to review); university president — all but final dismissal; disciplinary board — all. Investigation required for penalty 5 and above (art. 128); decisions final, objection to an in-absentia board decision within one week (art. 129). | Confirmed [S9, S8] |

---

## 6. Graduation, honours, certificates

- **Confirmed [S1]**: degrees are granted by the **university council** on the faculty council's request (art. 172); only to a student who passed all required exams; passing requires the exam committee's satisfaction (art. 173).
- **Graduation requirements — Confirmed, variants**:
  - Ain Shams Eng.: all programme credits, CGPA ≥ 2.0, all zero-credit courses passed, graduation project (registration after 70 % of credits), field training 8 weeks (pass/fail, not in GPA), ≤ 40 % credits from partner universities [S10].
  - Sohag Eng.: ≥ 160 CH, CGPA ≥ 2.0 incl. the project, **military education course (التربية العسكرية)** passed, pass/fail courses such as summer training [S11].
  - Cairo Law: 139 CH (131 compulsory + 8 elective) + non-credit courses, CGPA ≥ D (2.0) [S9].
  - Foreign-certificate holders: complementary Arabic + religion exam before the degree [S7].
- **Honours (مرتبة الشرف) — Confirmed, variants**:
  - Cairo Law: CGPA not below **3.2 (Very good) in any year** and **never failed** any course [S9].
  - Ain Shams Eng.: CGPA ≥ 3.3 throughout and every term GPA ≥ 3.3, no failed course, no disciplinary penalty [S10].
  - Sohag Eng.: term GPA ≥ 3.3 in all main terms, no F, **no improvement repeat**, no penalty; recorded on the certificate [S11].
  - Beni-Suef Arts: at least B+ in all levels and never failed; honour board for A and above unless repeating or on final chances [S12].
  - Traditional-system rule commonly cited (overall ممتاز or جيد جدا with no year below جيد جدا and no failure) — **unverified** (not found in a primary source).
- **Ranking**: by total marks of all years, not by CGPA (Exec. Reg. art. 85 as cited by Sohag) [S11]; Cairo Law ranks each programme by CGPA [S9] — conflicting practice, make it a setting.
- **Transcript**: granted to graduates and withdrawn students only after all fees are paid [S11].

---

## 7. Student statuses used in practice

Columns: **Sys** = T (traditional year) / C (credit hours) / both; **How** = A (automatic from results or dates) / M (manual decision); **Body** = who decides.

| Status (Arabic) | Meaning | Sys | Enters via | How | Body | Source |
|---|---|---|---|---|---|---|
| Nominated (مرشح) | Allocated by coordination / Study in Egypt, not yet enrolled | both | Coordination result | A (import) | Coordination Office / Ministry | S6, S15 |
| Applicant / pending documents | File incomplete | both | Application | M | Student affairs | S6 |
| Enrolled, regular (مقيد منتظم) | Normal student | both | Documents + fees + medical | M | Student affairs (late enrolment: faculty council) | S6 |
| Affiliated (منتسب) / directed affiliation (انتساب موجه) | Non-attending enrolled student | T mostly | Admission route | M | University president approves | S6 |
| Newly enrolled in year (مستجد) | First time in this year/level | both | Promotion or admission | A | — | S5 |
| Promoted (منقول / ناجح) | Passed the year | T | Year results | A | Faculty council approves results | S7 |
| Promoted with carried courses (منقول بمواد) | ≤ N failed courses carried | T, C-hybrid | Year results | A | Faculty council | S9, S12 |
| Repeating (باق للإعادة) | Failed > N courses; stays in the year | T | Year results | A | Faculty council | S12 |
| Outside candidate (من الخارج) | Spent 2 years in the year; sits failed courses without enrolment; counts as dismissed from the faculty | T | Results + faculty council permission | M (permission) | Faculty council | S3, S5 |
| Final chances (فرص نهائية) | Pre-final/final outside chances 2–3 | T | As above | M | Faculty council | S3, S12 |
| Dismissed — chances exhausted (مفصول لاستنفاد مرات الرسوب) | | T | Results after last chance | A (rule) then M (decision) | Faculty council | S3, S5, S11 |
| Good standing | CGPA ≥ threshold | C | Term results | A | — | S10 |
| Academic warning / probation (إنذار أكاديمي / مراقبة) | GPA below threshold; load capped | C | Term results | A | Student affairs notifies | S10, S11 |
| Final chance (فرصة أخيرة) | Extra terms before GPA dismissal | C | Warning count + credits ≥ 75/80 % | M | Faculty council | S10, S11 |
| Dismissed — academic (مفصول أكاديميا) | Warnings / max duration / low early GPA | C | Results / dates | A (rule) then M | Faculty council (university council beyond extra period) | S10, S11 |
| Excused for exam (غائب بعذر / I) | Course not counted as failure | both | Excuse request | M | Faculty council (medical committee advises) | S3, S5, S10 |
| Absent without excuse (غائب بدون عذر) | Fail ضعيف جدا / F / FW | both | Exam attendance | A | — | S3, S12 |
| Deprived (محروم) | Barred for attendance | both | Attendance | M | Faculty council | S7, S9 |
| Enrolment suspended (موقوف القيد) | Frozen, not counted toward duration | both | Request | M | Faculty council (≤ 2 years); university council beyond | S5, S6 |
| Postponed / deferred (مؤجل) | Credit-hour postponement; conscripted | C | Request / military | M | Faculty council | S11 |
| Conscripted (مجند) | Place kept | both | Military notice | M | Student affairs | S6, S11 |
| Withdrawn from term | Not registered in a main term | C | No registration | A | — | S11 |
| Withdrawn from faculty (منسحب / سحب ملف) | Left on request | both | Request | M | Student affairs / faculty council | S11, S12 |
| Enrolment cancelled (ملغى القيد) | Own request or rule | both | Request / rule | M | Faculty council | S9, S11 |
| Re-enrolled (معاد قيده) | Back after suspension/cancellation | both | Request | M | Faculty council (+ university councils at Sohag) | S9, S11, S12 |
| Transferred out / in (محول) | Moved faculty / university | both | Request / coordination | M | Both faculty councils + university president | S6 |
| Disciplinary suspension (موقوف تأديبيا) | Temporary dismissal | both | Discipline decision | M | Dean / president / disciplinary board | S9 |
| Dismissed — disciplinary (مفصول تأديبيا / فصل نهائي) | | both | Discipline decision | M | President / disciplinary board | S9 |
| Graduand / expected graduate | All requirements met, awaiting council | both | Results | A | — | S1 |
| Graduated (خريج) | Degree granted | both | Degree decision | M | University council on faculty council request | S1 |
| Deceased | | both | Report | M | Student affairs | Judgement |

Postgraduate adds: applicant → enrolled (diploma courses) → registered thesis (مسجل) → suspended (≤ 3 years) → struck/cancelled (شطب / إلغاء) → defended → awarded [S9, S13].

---

## 8. What could not be verified

- The full current text of the Exec. Reg. 809/1975 (no clean text copy found; only arts. 74 and 80 were read in Gazette scans, and arts. 123–129 via Cairo Law's guide). The suspension article is cited as art. 69 by two universities; the conditions-of-enrolment, preparatory-year, affiliation and second-degree articles are known only through Assiut's PDF whose digits are garbled.
- Standard traditional percentage bands (85/75/65/50/30) and any national **رأفة** rule.
- The traditional-system honours rule.
- Law 12/2009 (private/ahlia) admission and academic rules, and a published private or ahlia university bylaw (only an MSA snippet).
- Al-Azhar University student rules (Exec. Reg. 250/1975 university part, chances, suspension); only institute articles and art. 11 were read.
- The SCU yearly guide for paid special programmes (only news snippets); Study in Egypt document list and fee amounts.
- Whether "open education" still exists or was fully replaced by blended learning.

---

## Configurable options implied

Each item is a per-institution (often per-faculty or per-programme, versioned by bylaw year / intake cohort) setting. Defaults are the most common confirmed value.

### Institution and legal frame
| Setting | Variants | Default |
|---|---|---|
| Institution type | public (Law 49/1972) / private / ahlia (Law 12/2009) / Azhar (Law 103/1961) / technological | public |
| Governing bylaw version per programme and intake cohort | any; students keep the bylaw they entered under unless they opt in (Beni-Suef art. 40) | cohort-based |
| Approval workflow per decision type | which body approves: student affairs, education & student affairs committee, faculty council, university education council, university council, university president, disciplinary board | as in §7 |

### Admission
| Setting | Variants | Default |
|---|---|---|
| Enabled admission routes | coordination, equivalent certificate, technical diploma (SCU test), second-degree, affiliation, directed affiliation, international (Study in Egypt), transfer in, special/paid programme direct, private/ahlia unified portal, Azhar coordination, postgraduate | coordination + transfer + international |
| Required documents per route | list with "male only" / "age ≥ X" conditions (Form 2 Military; military status at 19 / over 22; birth certificate; national ID of student and guardian; photos with seating number; preference card; authenticated foreign certificates; passport; employer permit) | per §2 |
| Medical exam required | yes / no; per faculty | yes |
| Complementary Arabic + religion exam for foreign-certificate holders | on / off | on |
| Transfer windows and conditions | before term start; promoted only; first-year via electronic coordination only; minimum GPA/grade; one internal programme change; ≤ % credits passed | per §1.3 |
| Tuition-bearing statuses | Egyptians free / paid programme / second degree / international | public free |

### Study system
| Setting | Variants | Default |
|---|---|---|
| System | traditional year / two-term year / credit hours / hybrid levels-with-credits | per programme |
| Preparatory year | yes / no | no |
| Programme length (years / levels) and min / max duration | 4–6 years; credit hours min 8 terms, max 8–10 years | 4 years / max 8 years |
| Level thresholds (credit hours) | % of programme credits (25/50/75) or fixed CH | 25 % steps |
| Terms | 2 main + optional summer; weeks per term (16), summer (8) | 2 + summer |
| Max/min load by GPA band | e.g. 21/18/14 main, 9/8 summer; 12 under warning; next-level CH allowance | 18 normal, 12 warning |
| Add / drop / withdraw deadlines | weeks 1 / 2 / 6–10 (summer shorter); max withdrawals per level | 1 / 2 / 10 |
| Attendance bar and warnings | 25 % absence bar; warnings at 10/15/20 % | 25 % |
| Second round exams (دور ثاني) | yes / no | no |

### Grading and passing
| Setting | Variants | Default |
|---|---|---|
| Grade scale table | names (ممتاز…ضعيف جدا), letters, % bands, points; 4-point or 5-point | 4-point, Cairo Law bands |
| Course pass mark | 50 % / 60 %; minimum % in final exam (e.g. 40 %) | 50 %, none |
| Special symbols | W, I, FW, P (محروم), CH (غش), Abs, Pass/Fail | all |
| Grade cap after failure | repeated/carried course capped at مقبول/D, or B+, or none; excused absence exempt | مقبول/D, excused exempt |
| Unexcused absence result | ضعيف جدا / F / zero / FW | ضعيف جدا (F) |
| Year / degree overall grade | weighted average or total marks; ranking by total marks or CGPA | total marks (art. 85) |
| Leniency (رأفة) | off / review of ≤ N courses or GPA by control committee, with max marks | off (manual review) |

### Progression (traditional)
| Setting | Variants | Default |
|---|---|---|
| Max carried courses for promotion | 0–3; separate cap on specialised courses | 2 |
| Years allowed per year-of-study inside | 2 | 2 (art. 80) |
| Outside chances by year type | first/preparatory 0; middle 1; pre-final/final 1 + 2 extra; 5-year faculties treat year 2/3 as pre-final | art. 80 (2015) |
| Old-rule cohort handling | pre-2015/16 entrants: final-year "until pass", excuse limit | off |
| Extraordinary exam for final-year students with ≤ N courses left | off / on (≤ 3 courses within 2 months) | off |

### Progression (credit hours)
| Setting | Variants | Default |
|---|---|---|
| Warning trigger | CGPA < 2.0 / term GPA < 2.0; skip first term | CGPA < 2.0 |
| Warning counter reset | when CGPA (or term GPA) back ≥ threshold | yes |
| Dismissal rules (each on/off with number) | N consecutive warnings (4, 6); GPA < 1.0 in first 3 terms; CGPA < 1.5 after 4th term; max duration; unregistered/absent terms without excuse (2 consecutive / 3 non-consecutive) | 6 consecutive + max duration |
| Final chance before dismissal | terms granted (2 + summer), min % credits passed (75/80/85 %), approving body | 2 + summer, 75 %, faculty council |
| Improvement repeat | allowed / max count (2, 5) / best-grade vs latest-grade / failing repeat cancels old grade | best grade, 5 |
| Failed-course repeat | grade cap (B+, D, none); replaces in GPA; transcript shows both | replace, cap none |
| Graduation project gate | min % credits before registering (70 %) | 70 % |

### Enrolment changes
| Setting | Variants | Default |
|---|---|---|
| Suspension (وقف القيد) | max total (2 years / 4 terms / 3 terms); consecutive limit; granularity (year only / term); request deadline (week 7–8); exclusions (level 1, repeating students, outside students, scholarship internationals, unexcused absence last year, during finals); counts toward duration (no); fees during suspension; approving body beyond the limit | 2 years, year granularity, faculty council, university council beyond |
| Excuse handling | max accepted excuses (unlimited / 2 + third by higher council); filing window (before / during / ≤ 2 days after); medical committee; both-terms-equals-one-year rule | unlimited, 2 days |
| Postponement | max terms (2–4); not in first year; automatic for conscription | 4 terms |
| Re-enrolment | max gap (1–2 years); min CGPA; minimum wait after cancellation (1 year); counts as failure year (yes/no) | 2 years, faculty council |
| Withdrawal | clearance required (fees, books); proxy allowed | yes |

### Discipline
| Setting | Variants | Default |
|---|---|---|
| Penalty catalogue | the 13 art. 126 penalties (national, fixed for public universities); private/ahlia may differ | art. 126 |
| Competence matrix | art. 127 (staff 1–4, dean 1–8, president 1–12, board all) | art. 127 |
| Cheating effect | fail all courses of the session (art. 125) | on |
| Honours blocked by penalty | yes / no | yes |

### Graduation and honours
| Setting | Variants | Default |
|---|---|---|
| Graduation requirements | total credits; min CGPA 2.0; zero-credit / pass-fail courses; military education; field training weeks; graduation project; residency (max % transferred credits) | per programme |
| Honours rule | min CGPA (3.2 / 3.3) in every year or term; no F; no improvement repeat; no penalty; B+ every level (5-point) | 3.2 every year + no F |
| Honour board threshold | A and above, excluding repeaters / final-chance students | off |
| Transcript release | after fees cleared | on |

### Postgraduate
| Setting | Variants | Default |
|---|---|---|
| Degree durations (min / max / extension, in main terms) | diploma 1–2 / 2–6; master 4 / 6 / +2; PhD 6 / 10 / +2; doubled for part-time | Mansoura table |
| Registration windows | twice a year | twice |
| Supervision | eligible ranks, lecturer as co-supervisor only, max committee size (3 master / 5 PhD), max theses per supervisor, no kinship | as S9/S13 |
| Progress reports | every 6 months; strike on bad report | 6 months |
| Suspension | 1 year, extendable to 3 | 1 / 3 |
| Cancellation triggers | course failed twice, misconduct, repeated warnings, unfit thesis, own request, max duration, unpaid fees | all on |
