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
