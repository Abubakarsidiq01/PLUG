"use client";

import { useActionState, useEffect, useRef } from "react";
import { acceptInvite, type AcceptState } from "./actions";

const initial: AcceptState = { error: null };

export function AcceptForm() {
  const [state, formAction, pending] = useActionState(acceptInvite, initial);
  const invite = useRef<HTMLInputElement>(null);

  // The emailed link carries the invitation after the #, which browsers never send to a
  // server. Copy it into the field, again after a failed attempt clears the form.
  useEffect(() => {
    const token = new URLSearchParams(window.location.hash.slice(1)).get("token");
    if (token && invite.current && invite.current.value === "") invite.current.value = token;
  }, [state]);

  return (
    <form action={formAction} className="form-stack">
      {state.error ? <p className="form-error" role="alert">{state.error}</p> : null}
      <label className="field">
        <span className="field-label">Invitation code</span>
        <input ref={invite} className="field-input" name="invite_token" autoComplete="off" spellCheck={false} maxLength={128} required />
      </label>
      <label className="field">
        <span className="field-label">New password</span>
        <input className="field-input" type="password" name="password" autoComplete="new-password" minLength={12} maxLength={64} required />
        <span className="field-hint">12 to 64 characters, and not easy to guess.</span>
      </label>
      <label className="field">
        <span className="field-label">Repeat the password</span>
        <input className="field-input" type="password" name="password_repeat" autoComplete="new-password" minLength={12} maxLength={64} required />
      </label>
      <button type="submit" className="button button-primary" disabled={pending}>Create my staff account</button>
    </form>
  );
}
