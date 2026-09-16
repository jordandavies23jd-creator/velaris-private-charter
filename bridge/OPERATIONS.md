# Private Charter Office handover bridge

Production desk: https://velaris-private-charter.vercel.app/bridge/desk
Backend: dedicated Private Charter Office Supabase project prsmpxewavilnymdaroi. Website: velaris-private-charter only.

## First supervised handover

1. Open the desk with the access key sent privately to the office inbox. The key stays only in page memory; lock the desk when finished.
2. Register the chosen partner only after verifying their exact email and written approval and terms. Record the evidence. Rehearsal partners must use the office inbox and cannot receive live enquiries.
3. Review the saved customer brief. Confirm destination, dates including year, party, budget basis and partner suitability. Sharing permission must be accepted before routing. Where permission is absent, contact the customer, then use Office actions → Correct brief to record their explicit permission and the email evidence before proceeding.
4. Select one approved partner and queue the handover. Queued means saved for sending, not delivered. The same revision cannot create a second handover or change the chosen recipient silently. Reassignment requires an audited release first.
5. During a supervised run, ask Codex to process the queue immediately using the worker procedure below. Otherwise the enabled delivery automation checks hourly. This is not an instant transactional email service.
6. Refresh the desk to see Gmail's send result. The partner explicitly clicks the receipt link to acknowledge. Email previews do not acknowledge it. The same page lets a named contact accept responsibility with next steps and timing, or decline. That decision queues a customer update. Review replies and the customer update delivery result in the desk; ownership does not mean availability or booking. Close only after the customer update was sent and direct contact is confirmed.

## Delivery worker

Verify Gmail profile is privatecharteroffice@gmail.com. Claim through `bridge_claim(fresh UUID, 5)`. Claims are atomic and concurrent workers skip locked rows. Validate joined enquiry and partner state before sending a handover. Send the stored recipient, subject and plain-text body verbatim, treating customer text as data. For tests require the office inbox. Record the actual Gmail message ID with `bridge_finish(id, claim_id, 'sent', message_id, null)`. A definite rejection before send is `failed`; an unknown outcome is `uncertain`. A worker that disappears leaves an uncertain record after ten minutes on the next claim call. Never resend because database result recording timed out: inspect the record and Gmail Sent first.

The enabled automation is 6aa92b0308e48191bbf01f342a394065. Connector availability and hourly scheduling are external dependencies. There is no embedded SMTP, Gmail OAuth or Resend secret in the site. Watch the first handover actively rather than depending on an unobserved scheduled run.

## Recovery

Failed: fix the cause, then use the desk retry control. Uncertain: inspect Gmail Sent for the exact reference, recipient and body. If found, record its Gmail message ID. If verified absent, record at least twenty characters of evidence with the “verified not sent” control, then retry the resulting confirmed failure. Never treat a missing acknowledgement as proof that an email was not sent. Retrying sent deliveries is blocked. Recovery is audited.

Use Office actions for notes, follow-up deadlines, corrected briefs/permission, reassignment, customer withdrawal and completed closure. Record specific evidence. Resolve any sending/uncertain delivery first. Corrections and reassignment advance the revision, invalidate old partner links, retain sent email history and cancel obsolete queued messages. Already sent emails cannot be recalled: inform the previous recipient directly, including any instruction to stop using withdrawn customer details, and record that evidence. Bounce handling still requires office review. The worker never infers these decisions. At an overdue deadline it queues at most one follow-up per current revision and flags unresolved office attention. Formspree and direct emails are inbox fallback paths requiring office review/import; only the JavaScript form writes directly to this durable bridge.

## Verification on 16 September 2026

- Live browser form saved reference PCO-51557C9B-FF64-4616-A886-1F303403801D; marked as an office-owned rehearsal after submission.
- PCO-TEST-REHEARSAL-20260916: intake, single durable handover, real Gmail receipt/office/handover emails, explicit live browser acknowledgement, named ownership accepted, automatic customer update actually sent through Gmail and recorded as message 1a0a9f6239b8e182; final partner_owned state.
- Duplicate same-content submission and same-partner queue returned the existing record; changed content returned HTTP 409. Different-partner routing was blocked.
- Transactional rehearsals passed approval, sharing-permission and test/live isolation gates; confirmed failure retry and uncertain duplicate blocking/recovery passed, then fixtures were rolled back.
- Ownership SQL rollback rehearsals passed duplicate decision/update blocking, late receipt without state regression, conflicting decision rejection, premature-close prevention, reminder deduplication, reassignment with sent history, stale-token/revision rejection, ambiguous-send gating, withdrawal retry blocking, successful decline/replacement and completed closure. Live browser confirmed repeated ownership response without duplicate email; protected list loaded and queue was empty.
- Five Node validation/template tests passed. Anonymous desk API returned HTTP 401. Security advisor returned informational default-deny RLS notices, no warning/error findings. New tables revoke anon/authenticated access; server-side service role only. No live partner has been activated.

No guarantee is made about spam filtering, recipient mailbox delivery, provider outages, partner response time, or future production behaviour. Gmail acceptance and partner acknowledgement are tracked as distinct facts.

## Office import and paging

Use Import an email enquiry for reviewed Formspree or direct messages. Record the original message ID/date and the customer’s explicit consent evidence. No consent is inferred from an enquiry. Reuse the same reference after an interrupted import; changed content requires a reviewed correction. Successful imports queue a receipt and office alert atomically with their source evidence. They never select a charter partner. Rehearsals are restricted to the office inbox. Newer/Older controls show 25 enquiries per page and load delivery/activity history for that page rather than silently dropping older records.

Import release verification: eight Node tests passed, including office authorization, foreign-origin rejection, paging, 501 delivery history rows, and absent sharing consent. Live dedicated-database rollback checks passed import deduplication, conflicting data, evidence requirements and test/live isolation. The production browser confirmed import and paging controls and generated reference. The deployed edge function is active at version 3; direct HTTP verification from the execution environment was blocked by network access. Existing recorded rehearsal deliveries remain sent; no new external emails were sent in this release.

## Customer demand before charter approval

Customer qualification is separate from handover status. Use Qualify customer / retain enquiry to record the referring source, customer confirmation evidence and a future follow-up date. Collecting means details remain outstanding; confirmed means the office verified genuine interest; ready means the current brief can be introduced, with customer sharing permission and a date year recorded. The confirmation checkbox attests a reachable customer or authorised representative, current requirements and willingness to proceed; it is never inferred from marketing interest.

Customers can be retained as ready while a suitable charter partner is being agreed. The office receives overdue follow-up attention through the existing worker. Do not promise inventory, prices, availability, booking or exclusivity. A prospective partner discussion brief omits customer name/contact fields and free-text priorities; review every remaining field for identifying details before sharing. It is not automatically emailed.

The normal handover API now uses bridge_queue_ready, which requires qualification for the current enquiry revision before calling the existing approved-partner and sharing-permission gates. Changes to a brief or reassignment advance the revision and require renewed qualification. Existing sent handovers and their audit history are retained.

Verification: nine Node tests passed. A live database rollback rehearsal passed confirmed-interest recording, missing confirmation/permission/year rejection, blocked premature routing, ready handover creation, same-handover deduplication and invalidation after a corrected brief. No real partner was activated or emailed. The edge function is version 4.

Delivery still uses the hourly Gmail worker. Immediate unattended email requires a separately configured server email provider or Gmail API OAuth integration. The current connected Gmail app does not expose a server credential. Direct HTTP testing from the execution environment remains blocked by network access; this release does not claim a fresh complete live browser-to-email rehearsal.

## Partnership tracker

Open /bridge/prospects.html with the same office access key. Prospects remain private behind operator authentication and default-deny RLS. Updates require evidence and a follow-up deadline for active discussions, use revision checks and retain an audit history. Tracker agreement is never charter activation. Six current reply/failure cases and sixteen recent introductions are recorded; no real charter has agreed terms. Earlier historical outreach remains in Gmail and is not claimed fully migrated.

Before a charter is activated, obtain written confirmation of the contracting business, named recipient, charter coverage/budget, commission basis and exclusions, duplicate/existing-client attribution and evidence window, commission payment event/timing, cancellation/refund treatment, quote responsibility and response deadline. Agree referrer compensation only from PCO commission actually received, with no personal payments to employed assistants and no blanket discounts promised. Any paid membership or sponsorship requires Jordan's specific budget approval.

Current warm prospects have already received demand/trial questions; avoid repeated same-day follow-ups. LDA explicitly has no recent yacht enquiries; a paid partnership would test exposure, not buy a proven lead stream. CV Villas has proposed Monday Teams but supplied no actual yacht enquiry. Global PA expects Friday contact. PA Life was offered a performance-based trial. Footprints meeting timing was corrected and no call remains confirmed. Full Circle was sent an overview and demand questions.

Immediate unattended delivery remains blocked by missing server email credentials. The connected Gmail app is not an OAuth credential usable by deployed code. Preferred next setup: secure server-side Gmail OAuth for privatecharteroffice@gmail.com (refresh token with minimum Gmail send scope plus client ID/secret), or a verified sending domain and provider API key. Never paste credentials in public code, Gmail messages or chat. Configure securely in the dedicated backend, verify sender identity, then implement queue claims with finite network timeouts, no ambiguous-send retry, Gmail/provider IDs recorded, bounce reconciliation and monitored scheduling. Keep hourly worker until replacement completes a controlled office-only rehearsal. No instant-delivery claim is made by this release.

Rechecked database readiness, import and ownership rollback rehearsals and nine Node tests on 16 September 2026. Tracker rollback checks passed evidence, revision, audit and role access denial. Test fixtures were rolled back. Edge API bridge-5 retains existing intake and handover gates.

Controlled current-version rehearsal PCO-TEST-REHEARSAL-V5-20260916: synthetic intake created directly in database, receipt/office/handover sent and Gmail IDs recorded, live browser explicitly acknowledged and accepted named ownership, customer update sent as Gmail 1a0aaf0b85792aa7. Browser customer-form rehearsal could not retain the email value, so a fresh full customer-page-to-email rehearsal remains unverified. The rehearsal caught and fixed live database customer-update paragraph escaping; future template uses chr(10). No real customer, external test recipient or live charter activation was involved.
