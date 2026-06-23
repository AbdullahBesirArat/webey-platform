(function () {
  "use strict";

  var reduceMotion = false;
  try {
    reduceMotion = !!window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  } catch (_) {}

  var leaving = false;
  var progressValue = 0;
  var progressFrame = 0;

  var progressBar = document.createElement("div");
  progressBar.id = "wb-progress";
  document.body.prepend(progressBar);

  function stopProgressLoop() {
    if (progressFrame) {
      cancelAnimationFrame(progressFrame);
      progressFrame = 0;
    }
  }

  function runProgressLoop() {
    stopProgressLoop();

    var lastTick = 0;
    function step(now) {
      if (!lastTick) {
        lastTick = now;
      }

      var elapsed = now - lastTick;
      if (elapsed >= 16) {
        lastTick = now;
        if (progressValue < 72) {
          progressValue += 3.2;
        } else if (progressValue < 90) {
          progressValue += 0.8;
        }
        progressBar.style.width = Math.min(progressValue, 92) + "%";
      }

      if (progressValue < 92) {
        progressFrame = requestAnimationFrame(step);
      }
    }

    progressFrame = requestAnimationFrame(step);
  }

  function progStart() {
    progressValue = 0;
    progressBar.classList.remove("wb-done");
    progressBar.style.opacity = "1";
    progressBar.style.width = "0%";
    runProgressLoop();
  }

  function progDone() {
    stopProgressLoop();
    progressValue = 100;
    progressBar.style.width = "100%";
    progressBar.classList.add("wb-done");
  }

  if (document.readyState === "complete") {
    progDone();
  } else {
    progStart();
    window.addEventListener("load", progDone, { once: true });
  }

  function shouldAnimateLink(anchor) {
    if (!anchor) {
      return false;
    }

    var href = anchor.getAttribute("href");
    if (!href || href.charAt(0) === "#") {
      return false;
    }

    if (
      href.indexOf("tel:") === 0 ||
      href.indexOf("mailto:") === 0 ||
      href.indexOf("sms:") === 0 ||
      href.indexOf("javascript:") === 0
    ) {
      return false;
    }

    if (anchor.target === "_blank" || anchor.hasAttribute("download")) {
      return false;
    }

    if (anchor.dataset.noTransition !== undefined) {
      return false;
    }

    var targetUrl;
    try {
      targetUrl = new URL(anchor.href, window.location.href);
    } catch (_) {
      return false;
    }

    if (targetUrl.origin !== window.location.origin) {
      return false;
    }

    if (
      targetUrl.pathname === window.location.pathname &&
      targetUrl.search === window.location.search &&
      targetUrl.hash
    ) {
      return false;
    }

    return true;
  }

  document.addEventListener("click", function (event) {
    var anchor = event.target.closest("a[href]");
    if (!anchor || leaving || event.defaultPrevented) {
      return;
    }

    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) {
      return;
    }

    if (!shouldAnimateLink(anchor)) {
      return;
    }

    event.preventDefault();
    leaving = true;
    progStart();
    document.body.classList.add("wb-leaving");

    window.setTimeout(function () {
      window.location.href = anchor.href;
    }, reduceMotion ? 0 : 120);
  }, true);

  window.addEventListener("pageshow", function (event) {
    if (!event.persisted) {
      return;
    }

    leaving = false;
    document.body.classList.remove("wb-leaving");
    progDone();
  });

  var rippleSelectors = [
    "button",
    ".btn",
    ".btn-p",
    ".btn-g",
    ".np",
    ".ng",
    ".nl",
    ".fqq",
    ".plan-cta",
    ".wb-bn-item",
    ".icon-btn",
    ".apply",
    ".view-item",
    "[role=\"button\"]",
  ].join(",");

  function isLightBackground(element) {
    var bg = getComputedStyle(element).backgroundColor;
    if (!bg || bg === "transparent" || bg === "rgba(0, 0, 0, 0)") {
      return true;
    }

    var rgb = bg.match(/[\d.]+/g);
    if (!rgb || rgb.length < 3) {
      return true;
    }

    var r = Number(rgb[0]);
    var g = Number(rgb[1]);
    var b = Number(rgb[2]);
    return r * 0.299 + g * 0.587 + b * 0.114 > 160;
  }

  function createRipple(target, event) {
    if (reduceMotion) {
      return;
    }

    var rect = target.getBoundingClientRect();
    var size = Math.max(rect.width, rect.height) * 1.65;
    var x = event.clientX - rect.left - size / 2;
    var y = event.clientY - rect.top - size / 2;

    var ripple = document.createElement("span");
    ripple.className = "wb-ripple" + (isLightBackground(target) ? " dark" : "");
    ripple.style.width = size + "px";
    ripple.style.height = size + "px";
    ripple.style.left = x + "px";
    ripple.style.top = y + "px";

    if (getComputedStyle(target).position === "static") {
      target.style.position = "relative";
    }

    var overflow = getComputedStyle(target).overflow;
    if (overflow !== "hidden" && overflow !== "clip") {
      target.style.overflow = "hidden";
    }

    target.appendChild(ripple);
    window.setTimeout(function () {
      ripple.remove();
    }, 520);
  }

  document.addEventListener("pointerdown", function (event) {
    if (event.pointerType === "mouse" && event.button !== 0) {
      return;
    }

    var target = event.target.closest(rippleSelectors);
    if (!target || target.disabled || target.dataset.noRipple !== undefined) {
      return;
    }

    createRipple(target, event);
  }, { passive: true });

  var toastContainer = null;

  var toastIcons = {
    success: "<svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\"><polyline points=\"20 6 9 17 4 12\"/></svg>",
    error: "<svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\"><line x1=\"18\" y1=\"6\" x2=\"6\" y2=\"18\"/><line x1=\"6\" y1=\"6\" x2=\"18\" y2=\"18\"/></svg>",
    warn: "<svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\"><path d=\"M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z\"/><line x1=\"12\" y1=\"9\" x2=\"12\" y2=\"13\"/><line x1=\"12\" y1=\"17\" x2=\"12.01\" y2=\"17\"/></svg>",
    info: "<svg width=\"16\" height=\"16\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\"><circle cx=\"12\" cy=\"12\" r=\"10\"/><line x1=\"12\" y1=\"8\" x2=\"12\" y2=\"12\"/><line x1=\"12\" y1=\"16\" x2=\"12.01\" y2=\"16\"/></svg>",
  };

  function getToastContainer() {
    if (toastContainer) {
      return toastContainer;
    }

    toastContainer = document.createElement("div");
    toastContainer.id = "wb-toast-container";
    document.body.appendChild(toastContainer);
    return toastContainer;
  }

  function dismissToast(element) {
    if (!element || element.dataset.dismissed === "1") {
      return;
    }

    element.dataset.dismissed = "1";
    window.clearTimeout(element._wbTimer);
    element.classList.add("wb-toast-exit");
    window.setTimeout(function () {
      element.remove();
    }, 200);
  }

  function showToast(message, type, duration) {
    var kind = type || "info";
    var ttl = duration || 2800;

    var toast = document.createElement("div");
    toast.className = "wb-toast " + kind;
    toast.innerHTML =
      "<span class=\"wb-toast__icon\">" +
      (toastIcons[kind] || toastIcons.info) +
      "</span><span>" + message + "</span>";

    toast.addEventListener("click", function () {
      dismissToast(toast);
    });

    getToastContainer().appendChild(toast);
    toast._wbTimer = window.setTimeout(function () {
      dismissToast(toast);
    }, ttl);
  }

  if ("IntersectionObserver" in window) {
    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) {
          return;
        }

        entry.target.classList.add("is-visible");
        entry.target.classList.add("on");
        revealObserver.unobserve(entry.target);
      });
    }, {
      threshold: 0.12,
      rootMargin: "0px 0px -32px 0px",
    });

    function observeRevealTargets(scope) {
      scope.querySelectorAll("[data-r], .wb-reveal").forEach(function (node) {
        revealObserver.observe(node);
      });
    }

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        observeRevealTargets(document);
      }, { once: true });
    } else {
      observeRevealTargets(document);
    }

    if ("MutationObserver" in window) {
      var mutationObserver = new MutationObserver(function (mutations) {
        mutations.forEach(function (mutation) {
          mutation.addedNodes.forEach(function (node) {
            if (!node || node.nodeType !== 1) {
              return;
            }

            if (node.matches && (node.matches("[data-r]") || node.matches(".wb-reveal"))) {
              revealObserver.observe(node);
            }

            if (node.querySelectorAll) {
              observeRevealTargets(node);
            }
          });
        });
      });

      mutationObserver.observe(document.body, {
        childList: true,
        subtree: true,
      });
    }
  }

  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape") {
      return;
    }

    var drawer = document.querySelector(".drawer.open");
    if (drawer) {
      drawer.classList.remove("open");
      document.querySelector(".wb-overlay.active")?.classList.remove("active");
      return;
    }

    var notify = document.querySelector(".notify.open");
    if (notify) {
      notify.classList.remove("open");
      return;
    }

    var overlay = document.querySelector(".sb-overlay.show");
    if (overlay) {
      overlay.classList.remove("show");
      return;
    }

    var modal = document.querySelector(".modal-overlay.active");
    if (modal) {
      modal.classList.remove("active");
      return;
    }
  });

  window.wb = window.wb || {};
  window.wb.toast = showToast;
  window.wb.progStart = progStart;
  window.wb.progDone = progDone;
})();
