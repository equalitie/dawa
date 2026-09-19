//
// A custom Turbo action to redirect to a new URL.
//
Turbo.StreamActions.redirect = function () {
  // Use setTimeout to break out of the current event loop,
  // allowing other stream actions to run before we redirect.
  setTimeout(() => {
    // hard redirect, full page reload.
    window.location.href = this.target;
  }, 0);
  this.stopPropagation?.();
};

//
// A custom Turbo action to reload the page.
// This is useful, for example, when the locale or timezone
// has changed.
//
Turbo.StreamActions.reloadWindow = function () {
  setTimeout(() => {
    window.location.reload();
  }, 0);
  this.stopPropagation?.();
};

// A custom Turbo action to close all bootstrap modal dialogs.
//
Turbo.StreamActions.closeDialog = function () {
  if (this.target) {
    bootstrap.Modal.getOrCreateInstance("#" + this.target).hide();
  } else {
    [...document.getElementsByClassName("modal")].forEach((el) => {
      bootstrap.Modal.getOrCreateInstance(el).hide();
    });
  }
};

//
// A custom Turbo action to open a modal dialog,
// or all modals with class "auto-open".
//
Turbo.StreamActions.openDialog = function () {
  if (this.target) {
    bootstrap.Modal.getOrCreateInstance("#" + this.target).show();
  } else {
    [...document.getElementsByClassName("modal auto-open")].forEach((el) => {
      bootstrap.Modal.getOrCreateInstance(el).show();
    });
  }
};

//
// A custom Turbo action to reload a single turbo-frame.
//
// (1) Allows you to specify a frame that does not auto-load,
//     but can be reloaded. Use "src" attr for auto loading
//     and "data-reload" for src that is only used when this
//     reload action is received.
//     This approach is discussed here:
//     https://www.norydev.com/writing/refresh-a-single-turbo-frame
//
// (2) Allows you to specify cache id. The reload is only triggered
//     when the data-cache in the stream action is greater than the
//     cache id already stored in the turbo-frame attr data-cache.
//     (or if no cache-id is set)
//
//

function normalizeTurboTargets(obj) {
  const rawTargets = obj.target || obj.targets;
  if (!rawTargets) return [];
  if (typeof rawTargets === "string") {
    return rawTargets.includes(" ") ? rawTargets.split(" ") : [rawTargets];
  }
  return Array.isArray(rawTargets) ? rawTargets : [rawTargets];
}

//
// if we want to also have a cache-key
//
// const newCacheId = parseInt(this.dataset.cache);
// const currentCacheId = parseInt(frame.dataset.cache);
// frame.dataset.cache = newCacheId;
// if (
//   isNaN(newCacheId) ||
//   isNaN(currentCacheId) ||
//   newCacheId > currentCacheId
// ) {
//   .. reload logic ..
// }
//

Turbo.StreamActions.reload = function () {
  const targets = normalizeTurboTargets(this);
  const requestId = this.getAttribute("request-id");
  if (requestId && Turbo.session.recentRequests.has(requestId)) {
    // console.log("SKIP RELOAD (x-turbo-request-id seen)", requestId);
    return;
  }
  targets.forEach((target) => {
    document.querySelectorAll(`turbo-frame#${target}`).forEach((frame) => {
      // console.log("DO FRAME RELOAD", target);
      if (frame.src) {
        frame.reload();
      } else if (frame.dataset.reload) {
        frame.src = frame.dataset.reload;
      }
    });
  });
};
