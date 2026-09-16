//
// General purpose utility functions
//

const INTERACTIVE_TAGS = new Set([
  "A",
  "BUTTON",
  "INPUT",
  "SELECT",
  "TEXTAREA",
  "LABEL",
]);

export default class {
  static hide(elements) {
    const array = elements
      ? Array.isArray(elements)
        ? elements
        : [elements]
      : [];
    array.forEach((el) => {
      el.style.display = "none";
    });
  }

  static show(elements, display) {
    display = display || "block";
    const array = elements
      ? Array.isArray(elements)
        ? elements
        : [elements]
      : [];
    array.forEach((el) => {
      el.style.display = display;
    });
  }

  // return the value of a meta tag in head
  static meta(name) {
    return document.head.querySelector(`meta[name="${name}"]`)?.content;
  }

  // this is not a secure cryptographic digest, but is like Java's String.hashCode()
  // it can be used to create a "probably" unique number from a string.
  static code(str) {
    for (var i = 0, num = 0; i < str.length; i++) {
      num = (Math.imul(31, num) + str.charCodeAt(i)) | 0;
    }
    return Math.abs(num);
  }

  static showMessage(msg, type) {
    type = type || "primary";
    const escapedMsg = msg ? new Option(msg).innerHTML : "Unknown Error";
    const alertsHolder = document.getElementById("alerts");
    const alert = document.createElement("div");
    alert.innerHTML = [
      `<div class="alert alert-${type} alert-dismissible" role="alert">`,
      `   <div>${escapedMsg}</div>`,
      '   <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>',
      "</div>",
    ].join("");
    alertsHolder.append(alert);
  }

  //
  // TODO: this is for screen readers. I don't really know how to use this, but
  // it would be good to figure it out in the future.
  //
  static announce(message) {
    let announcer = document.querySelector('[aria-live="polite"]');

    if (!announcer) {
      announcer = document.createElement("div");
      announcer.setAttribute("aria-live", "polite");
      announcer.setAttribute("aria-atomic", "true");
      announcer.className = "sr-only visually-hidden";
      document.body.appendChild(announcer);
    }

    announcer.textContent = message;

    // Clear after announcement
    setTimeout(() => {
      announcer.textContent = "";
    }, 1000);
  }

  // Turbo.navigator.submitForm(form) and form.submit() will not
  // set the Turbo-Frame header. This function will.
  static submitForm(form) {
    let submitButton = form.querySelector(
      'input[type="submit"], button[type="submit"], button:not([type])',
    );
    if (!submitButton) {
      submitButton = document.createElement("button");
      submitButton.type = "submit";
      submitButton.style.display = "none";
      form.appendChild(submitButton);
    }
    submitButton.click();
  }

  //
  // returns true if the element or any of its parents
  // are "clickable" (buttons, links, inputs, etc)
  //
  static isClickable(element) {
    while (element && element !== document.body) {
      if (INTERACTIVE_TAGS.has(element.tagName)) {
        return true;
      }
      // I don't think we use these anywhere, but it could be a possibility
      // in the future:
      // const role = current.getAttribute('role');
      // if (role && INTERACTIVE_ROLES.has(role)) {
      //   return true;
      // }
      // if (currentElement.getAttribute('contenteditable') === 'true') {
      //   return true;
      // }
      element = element.parentElement;
    }
    return false;
  }

  //
  // returns true if the element or any of its parents
  // are draggable.
  //
  static isDraggable(element) {
    while (element && element !== document.body) {
      if (element.getAttribute("draggable")) {
        return true;
      }
      element = element.parentElement;
    }
    return false;
  }

  static escapeRegex(string) {
    return string.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  //
  // makes a manual request to the server as a turbo stream
  // and apply the response to the DOM
  //
  static turbo(url) {
    return fetch(url, {
      method: "GET",
      headers: { "Content-Type": "text/vnd.turbo-stream.html" },
    })
      .then((response) => response.text())
      .then((html) => Turbo.renderStreamMessage(html));
  }

  //
  // make a fetch that returns either json or turbo stream.
  //
  // It is generally considered "very bad" to write your own fetch wrapper,
  // because there are so many good ones:
  //
  // https://github.com/elbywan/wretch
  // https://github.com/rails/request.js
  // https://github.com/sindresorhus/ky
  // https://github.com/z-fetch/z-fetch/tree/main
  //
  // While this is true, I wanted something tiny and non-flexible for our
  // particular use case:
  //
  // * Always include X-CSRF-Token header.
  // * Request content type is always JSON.
  // * We always accept JSON or Turbo Stream responses.
  // * JSON response is parsed and returned to the caller in a promise.
  // * Turbo Stream response update the DOM directly.
  //

  static get(url, body) {
    return this.fetch("GET", url, body);
  }
  static post(url, body) {
    return this.fetch("POST", url, body);
  }
  static put(url, body) {
    return this.fetch("PUT", url, body);
  }
  static delete(url, body) {
    return this.fetch("DELETE", url, body);
  }

  static async fetch(method, url, body) {
    if (typeof body !== "string") {
      body = JSON.stringify(body);
    }
    return Turbo.fetch(url, {
      method: method,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json, text/vnd.turbo-stream.html",
        "X-CSRF-Token": this.meta("csrf-token"),
      },
      body: body,
    }).then(this.#handleFetchResponse);
  }

  static async #handleFetchResponse(response) {
    const contentType = response.headers.get("Content-Type");
    if (contentType.startsWith("application/json")) {
      const json = await response.json();
      if (!response.ok) {
        const error = (json && json.error) || response.statusText;
        return Promise.reject(error);
      } else {
        return Promise.resolve(json);
      }
    } else if (contentType.startsWith("text/vnd.turbo-stream.html")) {
      if (response.ok) {
        const html = await response.text();
        Turbo.renderStreamMessage(html);
      }
    } else if (contentType.startsWith("text/html")) {
      return Promise.reject(response.statusText);
    }
  }
}
