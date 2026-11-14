// The Exam Hub's entry rules (D-350). Eager and tiny on purpose: the Profile tab reads it, the hub itself is a deferred
// part (`deferredExamHub`).
library;

/// The hub's kill switch.
const kExamHubFeatureKey = 'exam.hub';

/// A membership role that teaches: the org teacher and the teaching assistant.
bool examHubTeachingRole(String? role) => role == 'teacher' || role == 'teacher_assistant';

/// Does one of [entries] (the organization overview's live entries) make this person a teacher there? A person whose
/// account role is student can still teach in an organization: their Profile tab offers the hub too.
bool examHubTeachesInAnyOrg(Iterable<Map<String, dynamic>> entries) {
  for (final e in entries) {
    final roles = e['roles'];
    if (roles is List && roles.any((r) => examHubTeachingRole('$r'))) return true;
  }
  return false;
}
