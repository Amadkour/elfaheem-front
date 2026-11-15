# Institutions S1: endpoint contract (backend)

Branch `feature/institutions` (back). Decisions D-960 – D-964 (`../back/docs/DECISIONS.md`), migration 0085.
Test: `../back/tests/org_v2/e2e_institutions_s1.py`. Kill switch: `org.institution` (study system + catalog screens).

Every error body is `{"detail": {"code", "message" (ar), "message_en", …extra}}` unless noted.
All paths are under `/api/v1/org/orgs/{org_id}`.

## 1. Study system

### `GET /study-system`

Any live staff member of the organization.

```json
{
  "study_system": "traditional | credit_hours | null",
  "effective": "traditional | credit_hours",
  "source": "org | programs | default",
  "has_graduate_programs": false,
  "programs": {"credit_hours": 3, "traditional": 1, "own_system": 1}
}
```

- `study_system` is the stored setting; `null` means "derived from the programs".
- `effective` is the stored value, or else the majority of the active programs (`credit_hours` when there are none).
- `source`: `org` (stored), `programs` (derived), `default` (no programs).
- `programs` counts the active programs per system. `own_system` is the number of programs that set their own system.

### `PUT /study-system`

Needs `organization.update`.

```json
{"study_system": "traditional | credit_hours | null", "has_graduate_programs": true}
```

- Both fields are optional. An omitted `has_graduate_programs` keeps the stored flag. `study_system` is always applied, and an omitted one means `null`.
- The answer is the GET body plus `"programs_changed": n`, the number of programs whose `system_type` was rewritten.
- Inheritance:
  - Every program that does not have its own system gets the new one. A `null` setting writes nothing.
  - A program has its own system after `PUT /registrar/programs/{pid}` with `system_type`.
  - The first time a value is stored, a program already on `traditional` also counts as having its own system.
  - A program created later through `POST /academic/programs` takes the organization's system.
- Errors: 422 (pydantic) for any other value, 403 without the right.

### Organization creation

`POST /api/v1/org/orgs` (and `organization` inside the public application) also accepts these fields:

```json
{"study_system": "traditional | credit_hours", "has_graduate_programs": true}
```

When `type` is `university` or `faculty`, the new organization is created with the **minimum set** (see 2). This happens once, and organizations that already exist are never touched.

## 2. Department catalog

### `GET /dept-catalog`

Needs `departments.view`.

```json
{
  "study_system": "credit_hours",
  "has_graduate_programs": false,
  "academic_departments": 2,
  "can_apply": true,
  "items": [
    {
      "key": "student_affairs",
      "group": "academic | service",
      "kind": "scientific | service",
      "preset": "student_affairs",
      "name_ar": "شئون الطلاب", "name_en": "Student Affairs",
      "description_ar": "…", "description_en": "…",
      "icon": "school", "color": "#2563EB",
      "audience": ["students"],
      "min_set": true,
      "condition": null,
      "recommended": true,
      "needs_name": false,
      "dept_id": 12,
      "request_types": [
        {"key": "enrollment_certificate", "name_ar": "إفادة قيد", "name_en": "Certificate of enrollment",
         "kind": "request", "applied": true}
      ]
    }
  ]
}
```

Item fields:
- `preset` is the existing `DEPT_PRESETS` key the template maps onto, or `null` for a template that is new to the catalog.
- `audience` is the default audience given to a department created from the template.
- `min_set` marks a template of the minimum set.
- `condition` is `null` (always part of the minimum set), `credit_hours`, or `graduate_programs`.
- `recommended` is `min_set` with its condition evaluated for this organization. Use it to pre-tick the minimum set.
- `needs_name` is true only for the academic template: the admin names the department.
- `dept_id` is the department already made from this template, or `null`. It is always `null` for the academic template.
- `request_types[].applied` says whether that request type already exists on `dept_id`.

Templates, in order (`key`, with its preset in brackets):
- Academic: `academic_department` (kind scientific, needs a name).
- Minimum set:
  - `student_affairs` (student_affairs)
  - `exam_control` (course_control)
  - `youth_care` (student_activities)
  - `staff_affairs` (staff_affairs)
  - `academic_advising` (academic_advising), condition `credit_hours`
  - `postgraduate` (postgraduate), condition `graduate_programs`
- Optional:
  - `medical_unit` (healthcare)
  - `library` (library)
  - `quality` (quality)
  - `it` (it)
  - `graduates` (graduates)
  - `international_relations`, `training`, `admissions_registration`, `scholarships_aid` and `community_service` (no preset)

### `POST /dept-catalog/apply`

Needs `departments.insert`.

```json
{"templates": [
  {"key": "library"},
  {"key": "it", "request_types": ["account_issue"]},
  {"key": "academic_department", "name_ar": "قسم الفيزياء", "name_en": "Physics"}
]}
```

- `request_types` can be omitted or `null`, which applies every default request type of the template. A list applies only those keys.
- `name_ar` / `name_en`: at least one is required for `academic_department`. For other templates they are optional and replace the default name.
- `templates` holds 1 – 40 entries.

The apply is idempotent. A department is found again in this order:
1. by `template_key`;
2. else by the template's preset, when that department has no `template_key` yet. It is adopted and given the `template_key`;
3. for the academic template, by an active scientific department with the same Arabic or English name.

A request type is found again by its key on that department. Re-applying adds only what is missing.

A created department has these values:
- `kind`, `preset`, `template_key` and the default `audience` from the template;
- the preset's `features` plus `workflow`;
- a unique code.

An academic department also gets its department council (`council_id` is set).

Answer `200`:

```json
{
  "created": [ /* department rows, the same shape as GET /departments/{id} without "counts" */ ],
  "reused": [ /* department rows */ ],
  "request_types_created": 4,
  "catalog": { /* the GET /dept-catalog body */ }
}
```

Errors:
- 422 `template_unknown` `{key}`
- 422 `request_type_unknown` `{template, keys}`
- 422 `template_name_required` `{key}`
- 403 without the right

## 3. Department audience

The department endpoints (`GET|POST /departments`, `GET|PUT /departments/{dept_id}`, `POST …/governance/entities`) gain two fields:

```json
{"audience": ["students", "staff"], "template_key": "student_affairs"}
```

- `audience`: a subset of `students`, `staff` and `departments`, stored in that order. `null`, or all three, means everyone. Send `null` to clear it.
  - An empty list or an unknown value answers 422 `bad_audience` `{values}`.
  - The app uses it to decide where "New request" appears for a department. The server stores it only. Filtering on the server comes in a later slice.
- `template_key` is read-only, or `null` for departments not made from the catalog.

## 4. Roles

`GET /access/roles` lists five new system roles. Every role now carries `"portfolio"`, which is `null` except for the vice deans.

| key | name_ar | portfolio |
|---|---|---|
| `dean` | عميد | null |
| `vice_dean_education_students` | وكيل الكلية لشئون التعليم والطلاب | `education_students` |
| `vice_dean_postgraduate_research` | وكيل الكلية لشئون الدراسات العليا والبحوث | `postgraduate_research` |
| `vice_dean_community_service` | وكيل الكلية لشئون خدمة المجتمع وتنمية البيئة | `community_service` |
| `council_secretary` | أمين المجلس | null |

They are assigned like any role, through the existing access endpoints. A council secretary is normally given the role scoped to the council's department.

## 5. Courses only in academic departments

The rule covers three calls:
- `POST /courses` with a `dept_id`;
- `PUT /courses/{course_id}` that changes `dept_id`;
- `PUT /departments/{dept_id}/courses` with mode `add` or `set` and course ids.

Each answers **422** with this body when the department's `kind` is not `scientific`:

```json
{"detail": {"code": "course_dept_not_academic", "message": "المقررات تتبع الأقسام العلمية فقط — اختر قسماً علمياً أو بدون قسم",
            "message_en": "Courses belong to academic departments only: pick an academic department or none", "kind": "service"}}
```

`dept_id: null` (no department) is always allowed, and so is mode `remove`. Courses already sitting in a non-scientific department are left as they are, and editing them without touching `dept_id` still works.
