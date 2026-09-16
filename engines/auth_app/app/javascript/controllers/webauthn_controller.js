import { Controller } from "@hotwired/stimulus";
import util from "util";

export default class extends Controller {
  static targets = ["hideOnSuccess", "showOnSuccess", "credentials"];
  static values = { redirect: String };

  //
  // any params passed to this call are added to all
  // the subsequent requests made by this controller.
  //
  initiateRegistration(event) {
    const url = "/auth/webauthn/register_initiate";
    util.post(url, event.params).then(
      (json) => {
        this.createCredential(json, event.params);
      },
      (error) => {
        util.showMessage(error, "danger");
      },
    );
  }

  createCredential(options, params) {
    const credentialOptions =
      PublicKeyCredential.parseCreationOptionsFromJSON(options);
    navigator.credentials.create({ publicKey: credentialOptions }).then(
      (credential) => {
        this.verifyCredential(credential, params);
      },
      (error) => {
        if (error.name == "NotAllowedError") {
          util.showMessage("Passkey registration canceled or timed out.");
        } else {
          util.showMessage(error.message, "danger");
        }
      },
    );
  }

  verifyCredential(credential, params) {
    const url = "/auth/webauthn/register_verify";

    // some browsers need a little help setting the authenticatorData field:
    credential.response.authenticatorData ||=
      credential.response.getAuthenticatorData();

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
        if (json["status"] == "ok") {
          this.success();
        }
      })
      .catch((error) => {
        util.showMessage(error, "danger");
      });
  }

  refresh() {
    util.turbo("/auth/credentials");
  }

  success() {
    util.hide(this.hideOnSuccessTargets);
    util.show(this.showOnSuccessTargets);
  }

  //
  // this gets called whenever any element has
  // data-webauthn-target="credential"
  //
  //credentialTargetConnected(el) {
  //  this.success();
  //}

  //
  // ByteArray does not get serialized into JSON, so it
  // must be converted to base64 first.
  //
  getClientExtensionResults(credential) {
    var results = credential.getClientExtensionResults();
    if (results?.prf?.results?.first) {
      results.prf.results.first = new Uint8Array(
        results.prf.results.first,
      ).toBase64({ alphabet: "base64url" });
    }
    return results;
  }
}
