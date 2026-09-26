/* R.Code for Claude Code — site behavior: theme toggle, copy buttons,
   and the live Cockpit demo on the home page. No framework, no build
   step. Progressive enhancement only — every page reads without JS. */
(function () {
  "use strict";

  var THEME_KEY = "rcode-theme";

  function getStoredTheme() {
    try {
      return window.localStorage.getItem(THEME_KEY);
    } catch (e) {
      return null;
    }
  }

  function setStoredTheme(value) {
    try {
      window.localStorage.setItem(THEME_KEY, value);
    } catch (e) {
      /* No persistence available (private browsing, disabled storage).
         The theme still applies for the rest of this page view. */
    }
  }

  function systemPrefersLight() {
    return (
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-color-scheme: light)").matches
    );
  }

  function effectiveTheme() {
    var stored = getStoredTheme();
    if (stored === "light" || stored === "dark") {
      return stored;
    }
    return systemPrefersLight() ? "light" : "dark";
  }

  function updateToggleLabel(button, current) {
    var next = current === "light" ? "dark" : "light";
    button.textContent = "Switch to " + next;
    button.setAttribute("aria-label", "Switch to " + next + " theme");
  }

  function initThemeToggle() {
    var button = document.getElementById("theme-toggle");
    if (!button) {
      return;
    }
    var current = effectiveTheme();
    updateToggleLabel(button, current);

    button.addEventListener("click", function () {
      var now =
        document.documentElement.getAttribute("data-theme") ||
        effectiveTheme();
      var next = now === "light" ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", next);
      setStoredTheme(next);
      updateToggleLabel(button, next);
    });
  }

  function copyText(text) {
    if (
      navigator.clipboard &&
      typeof navigator.clipboard.writeText === "function"
    ) {
      return navigator.clipboard.writeText(text);
    }
    return Promise.reject(new Error("Clipboard API unavailable"));
  }

  function selectText(node) {
    var range = document.createRange();
    range.selectNodeContents(node);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function initCopyButtons() {
    var buttons = document.querySelectorAll(".copy-btn");
    Array.prototype.forEach.call(buttons, function (button) {
      var targetId = button.getAttribute("data-copy-target");
      var target = targetId ? document.getElementById(targetId) : null;
      if (!target) {
        return;
      }
      var defaultLabel = button.textContent;

      button.addEventListener("click", function () {
        var text = target.textContent;
        copyText(text)
          .then(function () {
            button.textContent = "Copied";
          })
          .catch(function () {
            try {
              selectText(target);
              button.textContent = "Selected — press Cmd/Ctrl+C";
            } catch (e) {
              button.textContent = "Select the text manually";
            }
          })
          .then(function () {
            window.setTimeout(function () {
              button.textContent = defaultLabel;
            }, 2000);
          });
      });
    });
  }

  // Subagents list mirrors the design system's own StatusList preview
  // demo data verbatim (components/StatusList/preview.html) — no new
  // numbers or names invented for this page.
  var SUBAGENT_DEMO_ITEMS = [
    { label: "planning-agent", state: "done" },
    { label: "testing-agent", state: "failed" },
    { label: "code-reviewer-agent", state: "running", detail: "366s" },
    { label: "Team Lead", state: "needs-input" }
  ];

  function initCockpitDemo() {
    var root = document.getElementById("cockpit-demo");
    if (!root || !window.RCode) {
      return;
    }

    root.appendChild(
      window.RCode.CockpitBox({
        title: "Context",
        children: [
          window.RCode.ProgressBar({
            value: 0.42,
            tone: "brand",
            label: "Context window · demo-project"
          })
        ]
      })
    );

    root.appendChild(
      window.RCode.CockpitBox({
        title: "Team Lead",
        index: 1,
        children: [window.RCode.Chip({ label: "needs-input", tone: "wait" })]
      })
    );

    root.appendChild(
      window.RCode.CockpitBox({
        title: "Subagents",
        index: 2,
        selected: true,
        children: [window.RCode.StatusList({ items: SUBAGENT_DEMO_ITEMS })]
      })
    );
  }

  function initHeroActions() {
    var actions = document.getElementById("hero-actions");
    if (!actions || !window.RCode) {
      return;
    }
    actions.appendChild(
      window.RCode.Button({
        label: "Install in one line",
        variant: "primary",
        href: "install.html"
      })
    );
    actions.appendChild(
      window.RCode.Button({
        label: "See the Cockpit",
        variant: "secondary",
        href: "cockpit.html"
      })
    );
  }

  initThemeToggle();
  initCopyButtons();
  initCockpitDemo();
  initHeroActions();
})();
