export const EMAIL = /^[^\s@<>\r\n]+@[^\s@<>\r\n]+\.[^\s@<>\r\n]+$/;
export function validateIntake(raw) {
  const fields = { area:180, dates:180, guests:120, budget:80, budget_scope:100,
    date_flexibility:100, name:120, email:254, phone:80, requirements:4000 };
  const payload = {};
  for (const [key, max] of Object.entries(fields)) {
    const value = typeof raw[key] === 'string' ? raw[key].trim() : '';
    if (value.length > max || /\u0000/.test(value)) throw new Error('INVALID_FIELD');
    payload[key] = value;
  }
  for (const key of ['area','dates','guests','budget','budget_scope','name','email']) {
    if (!payload[key]) throw new Error('MISSING_REQUIREMENTS');
  }
  if (!EMAIL.test(payload.email)) throw new Error('INVALID_EMAIL');
  if (raw.service_acknowledgement !== 'accepted') throw new Error('SERVICE_ACKNOWLEDGEMENT_REQUIRED');
  if (!/^PCO-[A-Z0-9-]{8,75}$/.test(raw.enquiry_reference || '')) throw new Error('INVALID_REFERENCE');
  payload.sharing_permission = raw.sharing_permission === 'accepted' ? 'accepted' : 'not_given';
  payload.service_acknowledgement = 'accepted';
  payload.consent_version = '2026-09-16';
  return { reference: raw.enquiry_reference, payload };
}
export function handoverBody(reference,payload,company,link) {
  return `Hello ${company} team,\n\nPlease assess this Private Charter Office enquiry.\n\nReference: ${reference}\nDestination: ${payload.area}\nDates: ${payload.dates}\nFlexibility: ${payload.date_flexibility || 'Not specified'}\nParty: ${payload.guests}\nBudget (GBP): ${payload.budget}\nBudget basis: ${payload.budget_scope}\nPriorities: ${payload.requirements || 'Not specified'}\n\nCustomer: ${payload.name}\nEmail: ${payload.email}\nPhone: ${payload.phone || 'Not provided'}\nSharing permission: accepted; wording version ${payload.consent_version}.\n\nPlease use this link to acknowledge receipt and confirm whether a named member of your team will take responsibility for reviewing the enquiry. Include the next step and expected timing, or decline if you cannot proceed:\n${link}\n\nAcknowledgement confirms receipt only. It does not confirm availability, a booking or a commission. Charter contracts and funds remain with the selected charter professional.\n\nJordan Davies\nPrivate Charter Office`;
}
export function receiptBody(reference,payload) {
  return `Hello ${payload.name},\n\nYour charter enquiry has been saved under reference ${reference}. We will review your destination, dates, party and budget before arranging an introduction.\n\n${payload.sharing_permission==='accepted' ? 'We have recorded your permission to share your brief with the selected charter professional.' : 'We will contact you before sharing your brief and contact details with a charter professional.'}\n\nNo yacht availability, price or booking is confirmed by this receipt.\n\nPrivate Charter Office\nprivatecharteroffice@gmail.com`;
}
