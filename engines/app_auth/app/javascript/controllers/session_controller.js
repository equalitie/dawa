//
// This controller manages all the client-side steps for
// webauthn authentication.
//
// username may be supplied either as a target or a value.
//
import { Controller } from "@hotwired/stimulus";
import util from "util";

export default class extends Controller {
  static targets = ["username", "hideOnSuccess", "showOnSuccess"];
  static values = { username: String };

  login(event) {
    event.preventDefault();
    const username = this.hasUsernameTarget
      ? this.usernameTarget.value
      : this.usernameValue;
    const params = Object.assign(
      {
        login: username,
        timezone: document.getElementById("timezone")?.value,
      },
      event.params,
    );
    const url = "/auth/session/initiate";
    util
      .post(url, params)
      .then((json) => {
        this.requestCredential(json, event.params);
      })
      .catch((error) => {
        util.showMessage(error, "danger");
      });
  }

  requestCredential(options, params) {
    const evalByCredential = this.extractEvalByCredential(options);
    const pubkeyOptions =
      PublicKeyCredential.parseRequestOptionsFromJSON(options);
    pubkeyOptions.extensions.prf["evalByCredential"] = evalByCredential;
    navigator.credentials
      .get({ publicKey: pubkeyOptions })
      .then((credential) => {
        this.verify(credential, params);
      })
      .catch((error) => {
        util.showMessage(error, "danger");
      });
  }

  async verify(credential, params) {
    const url = "/auth/session/verify";

    const mergedParams = Object.assign(
      {
        credential: credential.toJSON(),
        client_extension_results: this.getClientExtensionResults(credential),
      },
      params,
    );

    util
      .post(url, mergedParams)
      .then((json) => {
        if (json.status == "ok") {
          this.success();
          if (json.location) {
            window.location = json.location;
          }
        }
      })
      .catch((error) => {
        util.showMessage(error, "danger");
      });
  }

  //
  // Uint8Array does not get serialized into JSON, so it
  // must be converted first.
  //
  getClientExtensionResults(credential) {
    var results = credential.getClientExtensionResults();
    if (results.prf?.results?.first) {
      results.prf.results.first = new Uint8Array(
        results.prf.results.first,
      ).toBase64({ alphabet: "base64url" });
    }
    return results;
  }

  success() {
    util.hide(this.hideOnSuccessTargets);
    util.show(this.showOnSuccessTargets);
  }

  //
  // Chrome fails whenever I try calling `PublicKeyCredential.parseRequestOptionsFromJSON`
  // with options that include evalByCredential. It returns this error:
  //
  //   'extensions.prf.evalByCredential' contains invalid base64url data
  //
  // However, I am certain that is not the case. So, this function exists
  // to manually convert the PRF values from base64 url safe to Uint8Arrays.
  //
  extractEvalByCredential(options) {
    if (options.extensions?.prf?.evalByCredential) {
      const newByCreds = {};
      const byCreds = options.extensions.prf.evalByCredential;
      delete options.extensions.prf.evalByCredential;
      for (const [key, value] of Object.entries(byCreds)) {
        newByCreds[key] = {
          first: Uint8Array.fromBase64(value.first, { alphabet: "base64url" }),
        };
      }
      return newByCreds;
    } else {
      return {};
    }
  }
}
