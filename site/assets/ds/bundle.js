/* @ds-bundle: {"format":4,"namespace":"RCode","components":[{"name":"CockpitBox"},{"name":"ProgressBar"},{"name":"StatusList"},{"name":"Button"},{"name":"Chip"},{"name":"Terminal"}]} */
(function () {
  "use strict";

  function el(tag, className) {
    var node = document.createElement(tag);
    if (className) {
      node.className = className;
    }
    return node;
  }

  function text(value) {
    return document.createTextNode(value == null ? "" : String(value));
  }

  function appendChildren(node, children) {
    (children || []).forEach(function (child) {
      if (child === null || child === undefined || child === false) {
        return;
      }
      if (typeof child === "string" || typeof child === "number") {
        node.appendChild(text(child));
      } else {
        node.appendChild(child);
      }
    });
  }

  // ---- CockpitBox ---------------------------------------------------------
  // The one container of the system: surface fill, 1px line border,
  // radius-sm, space-4 padding, an h2 mono heading optionally prefixed
  // with its shortcut number ("2 · Subagents"). Selected state moves
  // border and heading into focus.

  function CockpitBox(props) {
    props = props || {};
    var box = el(
      "div",
      "rc-cockpit-box" + (props.selected ? " rc-cockpit-box--selected" : "")
    );

    var heading = el("h2", "rc-cockpit-box__heading h2");
    var title = props.title || "";
    if (typeof props.index === "number") {
      title = props.index + " · " + title;
    }
    heading.appendChild(text(title));
    box.appendChild(heading);

    var body = el("div", "rc-cockpit-box__body");
    appendChildren(body, props.children);
    box.appendChild(body);

    return box;
  }

  // ---- ProgressBar ----------------------------------------------------------
  // Fills left to right in a solid tone color; the remainder renders as
  // a dither of space-2 (8px) cells in the same hue, never a grey track.

  var PROGRESS_TONE_VAR = {
    brand: "--clay",
    go: "--go",
    wait: "--wait",
    stop: "--stop"
  };

  function ProgressBar(props) {
    props = props || {};
    var toneVar = PROGRESS_TONE_VAR[props.tone] || PROGRESS_TONE_VAR.wait;
    var raw = typeof props.value === "number" ? props.value : 0;
    var value = Math.max(0, Math.min(1, raw));

    var wrap = el("div", "rc-progressbar");

    if (props.label) {
      var label = el("div", "rc-progressbar__label label");
      label.appendChild(text(props.label));
      wrap.appendChild(label);
    }

    var track = el("div", "rc-progressbar__track");
    track.style.setProperty("--rc-tone", "var(" + toneVar + ")");
    track.setAttribute("role", "progressbar");
    track.setAttribute("aria-valuemin", "0");
    track.setAttribute("aria-valuemax", "100");
    track.setAttribute("aria-valuenow", String(Math.round(value * 100)));
    if (props.label) {
      track.setAttribute("aria-label", props.label);
    }

    var fill = el("div", "rc-progressbar__fill");
    fill.style.width = value * 100 + "%";
    track.appendChild(fill);

    wrap.appendChild(track);
    return wrap;
  }

  // ---- StatusList -----------------------------------------------------------
  // Status is always told by glyph and color together, never color alone.

  var STATUS_GLYPH = {
    done: { glyph: "✓", toneVar: "--go" },
    failed: { glyph: "✗", toneVar: "--stop" },
    running: { glyph: "⟳", toneVar: "--wait" },
    "needs-input": { glyph: "●", toneVar: "--wait" },
    inactive: { glyph: "○", toneVar: "--muted" }
  };

  function StatusList(props) {
    props = props || {};
    var list = el("ul", "rc-status-list");

    (props.items || []).forEach(function (item) {
      var meta = STATUS_GLYPH[item.state] || STATUS_GLYPH.inactive;
      var row = el("li", "rc-status-row");

      var glyph = el("span", "rc-status-row__glyph");
      glyph.style.color = "var(" + meta.toneVar + ")";
      glyph.setAttribute("aria-hidden", "true");
      glyph.appendChild(text(meta.glyph));
      row.appendChild(glyph);

      var label = el("span", "rc-status-row__label code");
      label.appendChild(text(item.label));
      row.appendChild(label);

      if (item.detail) {
        var detail = el("span", "rc-status-row__detail small");
        detail.appendChild(text(item.detail));
        row.appendChild(detail);
      }

      row.setAttribute("data-state", item.state || "inactive");
      list.appendChild(row);
    });

    return list;
  }

  // ---- Button -----------------------------------------------------------
  // Primary: clay fill with on-clay text. Secondary: line border with
  // ink text. radius-sm, visible 2px focus ring in --focus.

  function Button(props) {
    props = props || {};
    var variant = props.variant === "secondary" ? "secondary" : "primary";
    var isLink = typeof props.href === "string" && props.href.length > 0;
    var node = el(isLink ? "a" : "button", "rc-button rc-button--" + variant);

    if (isLink) {
      node.setAttribute("href", props.href);
    } else {
      node.setAttribute("type", "button");
    }

    node.appendChild(text(props.label));
    return node;
  }

  // ---- Chip -----------------------------------------------------------------
  // A tone-filled label, text in ground, the same treatment the Cockpit
  // uses for "needs-input".

  var CHIP_TONE_VAR = {
    wait: "--wait",
    go: "--go",
    stop: "--stop",
    muted: "--muted"
  };

  function Chip(props) {
    props = props || {};
    var toneVar = CHIP_TONE_VAR[props.tone] || CHIP_TONE_VAR.muted;
    var chip = el("span", "rc-chip label");
    chip.style.setProperty("--rc-tone", "var(" + toneVar + ")");
    chip.appendChild(text(props.label));
    return chip;
  }

  // ---- Terminal ---------------------------------------------------------
  // A surface block with a line border, mono code lines, each prefixed
  // with the prompt.

  function Terminal(props) {
    props = props || {};
    var prompt = typeof props.prompt === "string" ? props.prompt : "$ ";
    var box = el("div", "rc-terminal");

    (props.lines || []).forEach(function (line) {
      var row = el("div", "rc-terminal__line code");
      row.appendChild(text(prompt + line));
      box.appendChild(row);
    });

    return box;
  }

  window.RCode = {
    CockpitBox: CockpitBox,
    ProgressBar: ProgressBar,
    StatusList: StatusList,
    Button: Button,
    Chip: Chip,
    Terminal: Terminal
  };
})();
