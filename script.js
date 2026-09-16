// Keep the same reference on retries; never store customer details in the browser.
const briefForm = document.getElementById("briefForm");
const newEnquiryReference = () => "PCO-" + (crypto.randomUUID ? crypto.randomUUID().toUpperCase() : Array.from(crypto.getRandomValues(new Uint8Array(16)), b => b.toString(16).padStart(2, "0")).join("").toUpperCase());
briefForm.elements.enquiry_reference.value = newEnquiryReference();
const buildHandoverBrief = (body) => {
  const value = (key) => String(body.get(key) || "Not provided").trim();
  const permitted = body.get("sharing_permission") === "accepted";
  return [
    "PRIVATE CHARTER OFFICE — ENQUIRY HANDOVER",
    "Reference: " + value("enquiry_reference"),
    "Destination: " + value("area"),
    "Dates: " + value("dates"),
    "Date flexibility: " + value("date_flexibility"),
    "Guests: " + value("guests"),
    "Budget range (GBP): " + value("budget"),
    "Budget basis: " + value("budget_scope"),
    "Priorities: " + value("requirements"),
    "Customer: " + value("name"),
    "Email: " + value("email"),
    "Phone / WhatsApp: " + value("phone"),
    "Sharing permission: " + (permitted ? "Accepted" : "NOT GIVEN — contact customer before sharing"),
    "Consent wording version: " + value("consent_version"),
    "Office action: review fit and confirm an approved partner before handover.",
    "Partner action: acknowledge this reference, assess availability and confirm next steps. No booking or price is confirmed by this enquiry."
  ].join("\n");
};
let attemptedPayload = null;
briefForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.currentTarget;
  const button = form.querySelector('button[type="submit"]');
  const status = document.getElementById("formStatus");
  if (button.disabled || !form.reportValidity()) return;
  const body = new FormData(form);
  const reference = String(body.get("enquiry_reference"));
  body.set("_subject", "Private Charter Mandate — " + reference);
  body.set("handover_brief", buildHandoverBrief(body));
  const payload = JSON.stringify({ ...Object.fromEntries(body), action: "intake" });
  if (attemptedPayload !== null && attemptedPayload !== payload) {
    status.textContent = "A previous submission may already be saved under " + reference + ". Please restore the original details to retry, or email privatecharteroffice@gmail.com with this reference so we can review the changes.";
    status.focus();
    return;
  }
  attemptedPayload = payload;
  const originalLabel = button.innerHTML;
  button.disabled = true;
  button.textContent = "Sending…";
  form.setAttribute("aria-busy", "true");
  status.textContent = "Sending your brief…";
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch("https://prsmpxewavilnymdaroi.supabase.co/functions/v1/charter-bridge", {
      method: "POST",
      body: payload,
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
    });
    const result = await response.json();
    if (!response.ok || result.ok !== true) throw new Error("Submission not confirmed");
    const success = document.getElementById("success");
    const successReference = document.getElementById("successReference");
    status.textContent = "Your enquiry has been saved. Your reference is " + reference + ".";
    if (success && successReference) {
      successReference.textContent = "Your reference is " + reference + ".";
      success.style.display = "block";
      form.style.display = "none";
      success.focus();
    }
  } catch {
    status.textContent = "We couldn’t confirm your submission. Your details are still here. Please retry with the same details or email privatecharteroffice@gmail.com quoting " + reference + ".";
    status.focus();
  } finally {
    clearTimeout(timeout);
    button.disabled = false;
    button.innerHTML = originalLabel;
    form.removeAttribute("aria-busy");
  }
});


// Presentation failures must not prevent enquiry submission.
try {
const reveals = [...document.querySelectorAll("[data-reveal]")];
const io = new IntersectionObserver(
  (es) =>
    es.forEach((e) => {
      if (e.isIntersecting) e.target.classList.add("is-visible");
    }),
  { threshold: 0.14 },
);
reveals.forEach((e) => io.observe(e));
const onScroll = () =>
  document.documentElement.style.setProperty("--scroll", window.scrollY + "px");
onScroll();
addEventListener("scroll", onScroll, { passive: true });
const mb = document.getElementById("menuBtn"),
  mm = document.getElementById("mobileMenu");
const closeMenu = () => {
  mm.style.display = "none";
  mb.setAttribute("aria-expanded", "false");
};
mb.setAttribute("aria-expanded", "false");
mb.addEventListener("click", () => {
  const open = mm.style.display !== "block";
  mm.style.display = open ? "block" : "none";
  mb.setAttribute("aria-expanded", String(open));
});
mm.querySelectorAll("a").forEach((a) => a.addEventListener("click", closeMenu));
addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeMenu();
});
addEventListener("resize", () => {
  if (innerWidth > 900) closeMenu();
});

} catch {
  document.querySelectorAll("[data-reveal]").forEach(element => element.classList.add("is-visible"));
}
