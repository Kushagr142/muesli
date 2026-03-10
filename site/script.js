const modeButtons = document.querySelectorAll("[data-mode]");
const modePanels = document.querySelectorAll("[data-panel]");

for (const button of modeButtons) {
  button.addEventListener("click", () => {
    const mode = button.dataset.mode;

    for (const candidate of modeButtons) {
      const active = candidate === button;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-selected", String(active));
    }

    for (const panel of modePanels) {
      panel.classList.toggle("is-active", panel.dataset.panel === mode);
    }
  });
}

const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    }
  },
  {
    threshold: 0.18,
  },
);

for (const section of document.querySelectorAll(".reveal")) {
  observer.observe(section);
}

const firstReveal = document.querySelector(".reveal");
if (firstReveal) {
  requestAnimationFrame(() => {
    firstReveal.classList.add("is-visible");
  });
}
