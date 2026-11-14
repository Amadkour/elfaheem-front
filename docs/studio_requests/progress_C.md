# Agent C — Requests system (governance, D-057 → D-140 / D-141) — progress

Branches `feature/studio-req` in both repos (from `feature/studio-requests`). Owner's brief items 3.1–3.6, 6.5–6.7,
7.5, 7.6. Decisions D-140 (for someone else · attachments · export by ids) and D-141 (approval chain).

| # | Task | State | Files | Tests |
|---|------|-------|-------|-------|
| 1 | Submit for someone else (3.1–3.5) | done | back: `data/governance_models.py` (`OrgWorkBeneficiary`), `services/organization/governance/beneficiary.py`, `org_catalog.py` (`workflow.on_behalf`), both governance routers, `migrations/versions/0037_gov_requests.py`; app: `gov_models.dart` (`Beneficiary`, `BeneficiaryDraft`, `GovPerson`), `gov_api.dart`, `gov_request_parts.dart` (`GovForSection`, `pickGovBeneficiary`, `GovBeneficiaryRows`), `gov_member_pages.dart` (submit form), `gov_items_page.dart` (staff New item + card), `gov_item_screen.dart` | `e2e_gov_requests.py` §1, `migration_0037.py` (SQLite + PostgreSQL), `test/org/gov_requests_test.dart`, `test/ui/gov_requests_layout_test.dart` |
| 2 | Export one / selected / all-with-filters (3.6) | done | back: `export_data.py` (`ids=`, per-item check, beneficiary / reason / attachment columns), router; app: `gov_wiring.dart` (`govExportItemIds`), bulk bar "Export selected", item page "Export" | `e2e_gov_requests.py` §2 |
| 3 | Attachments (6.6 / 7.5) | done | back: `governance/attachments.py` (magic bytes, size cap, server key, private storage, links after the view check), `POST /public/governance/{org}/attachments`, `GET /public/governance/attachments/{id}`; app: `uploadGovAttachment`, `openGovAttachment` (image preview in app, PDF in the system viewer), `GovAttachmentChips` | `e2e_gov_requests.py` §3 |
| 4 | Approval chain (6.7) | done | back: `governance/chain.py`, `items.decide` / `resubmit` / reopen, `councils.close` hook, `GET|PUT /entities/{id}/chain`, `POST /public/governance/items/{id}/resubmit`; app: `GovChainCard`, `GovChainPreview`, `GovChainEditor(Page)` (entity page tab), resubmit sheet, reason required on reject | `e2e_gov_requests.py` §4, `e2e_governance.py` (reject carries a note) |
| 5 | Notifications (6.5) | done | back: `notify.stakeholders` / `item_update` (submitter · beneficiary · manager · council) on create and every status change, wired into decide / step / status / withdraw / resubmit / council close | `e2e_gov_requests.py` (checks marked "5.") |
| 6 | Logs (7.6) | done | back: governance warnings log the exception class only (an SMTP / push error text can hold an address or a name); nothing new logs beneficiary details or file names | `e2e_gov_requests.py` §6 |

Renders (by eye, `test/visual/gov_requests_golden_test.dart`): `test/visual/goldens/gov_requests_{submit,submit_member,detail,rejected}_{390,1440}_{ar,en}_{light,dark}.png`.

Hooks asked of the other agents: none needed — the export uses `fetchExportDataset` + `exportHub` as they are; the new
item columns (`beneficiary`, `beneficiary_relation`, `beneficiary_contact`, `decision_note`, `attachments`) come from
the server's dataset like the others.

Next: nothing open in this track. Not done here on purpose: comment attachments from the app's comment box (the
server accepts them; the composer has no file button yet).
