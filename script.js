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
document.getElementById("briefForm").addEventListener("submit", (e) => {
  e.preventDefault();
  e.currentTarget.style.display = "none";
  const s = document.getElementById("success");
  s.style.display = "block";
  document.getElementById("brief").scrollIntoView({ behavior: "smooth" });
});
