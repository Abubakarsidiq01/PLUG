import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import type { components } from "@/generated/api";
import { callApi } from "@/lib/staff-api";
import { ACCESS_COOKIE, REFRESH_COOKIE, apiOrigin } from "@/lib/staff-console";
import { ConsoleNav } from "../console-nav";
import { disableStaff, inviteStaff } from "./actions";

// Staff accounts (ADR-013): who can open this console, and, for owners, inviting and
// disabling people. Everything here is read from and decided by the API on each request.
// Nested under the admin layout, so the site title template does not reach it.
export const metadata: Metadata = { title: { absolute: "Staff — PLUG" } };

type StaffList = components["schemas"]["StaffList"];
type Me = components["schemas"]["Me"];

const loginUrl = "/admin/login?from=%2Fadmin%2Fstaff";

const done: Record<string, string> = {
  invited: "Invitation sent. It works once, for 72 hours.",
  disabled: "Disabled. Their sessions have ended.",
};
const errors: Record<string, string> = {
  email: "Enter a valid email address.",
  owner: "Only an owner can invite or disable staff.",
  conflict: "That person already has an active staff account.",
  self: "You cannot disable your own account. Ask another owner.",
  mail: "The invitation could not be emailed. Staff email is not configured on the server.",
  expired: "Your session ended. Sign in again.",
  server: "The PLUG server did not answer. Try again.",
};

const timeFormat = new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeZone: "UTC" });

export default async function StaffPage({ searchParams }: PageProps<"/admin/staff">) {
  await connection();
  if (apiOrigin() === null) redirect(loginUrl);
  const jar = await cookies();
  const params = await searchParams;
  const refreshUrl = jar.has(REFRESH_COOKIE) && params.r !== "1" ? "/admin/session/refresh?to=%2Fadmin%2Fstaff" : loginUrl;
  const token = jar.get(ACCESS_COOKIE)?.value;
  if (!token) redirect(refreshUrl);

  const [list, me] = await Promise.all([
    callApi<StaffList>("/v1/admin/staff", { token }),
    callApi<Me>("/v1/me", { token }),
  ]);
  if (list.status === 401 || me.status === 401) redirect(refreshUrl);

  const message = typeof params.done === "string" ? done[params.done] : undefined;
  const problem = typeof params.error === "string" ? errors[params.error] : undefined;
  const reference = typeof params.ref === "string" && /^req_[A-Za-z0-9-]{1,80}$/.test(params.ref) ? params.ref : null;

  const actions = <ConsoleNav current="staff" />;

  let body;
  if (!list.ok || !me.ok) {
    const denied = list.status === 403;
    body = (
      <div className="card notice-card">
        <h2 className="title2">{denied ? "You do not have access" : "Staff could not load"}</h2>
        <p>{denied ? "This page is for PLUG staff who signed in with a second factor." : "The PLUG server did not answer. Reload the page to try again."}</p>
        {!list.ok && list.error?.request_id ? <p className="inspector-reference">Reference: <code>{list.error.request_id}</code></p> : null}
      </div>
    );
  } else {
    const myId = me.data.account.user_id;
    const owner = list.data.staff.some((member) => member.user_id === myId && member.role === "owner");
    body = (
      <>
        <section className="inspector-section" aria-labelledby="staff-members">
          <h2 id="staff-members" className="title2">People</h2>
          <p className="inspector-note">Everyone with a staff account. A disabled account cannot sign in and has no sessions.</p>
          <div className="card table-card inspector-scroll" role="region" aria-label="Staff table" tabIndex={0}>
            <table className="truth-table inspector-table staff-table">
              <thead>
                <tr>
                  <th scope="col">Email</th>
                  <th scope="col">Role</th>
                  <th scope="col">Status</th>
                  <th scope="col">Since</th>
                  {owner ? <th scope="col"><span className="visually-hidden">Actions</span></th> : null}
                </tr>
              </thead>
              <tbody>
                {list.data.staff.map((member) => (
                  <tr key={member.user_id}>
                    <td>{member.email}{member.user_id === myId ? " (you)" : ""}</td>
                    <td>{member.role === "owner" ? "Owner" : "Staff"}</td>
                    <td>{member.status === "active" ? "Active" : "Disabled"}</td>
                    <td><time dateTime={member.created_at}>{timeFormat.format(new Date(member.created_at))}</time></td>
                    {owner ? (
                      <td>
                        {member.status === "active" && member.user_id !== myId ? (
                          <form action={disableStaff}>
                            <input type="hidden" name="user_id" value={member.user_id} />
                            <button type="submit" className="button button-secondary" aria-label={`Disable ${member.email}`}>Disable</button>
                          </form>
                        ) : null}
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
        {owner ? (
          <section className="inspector-section" aria-labelledby="staff-invite">
            <h2 id="staff-invite" className="title2">Invite someone</h2>
            <p className="inspector-note">They get an email with a link to choose a password. Inviting a disabled person restores them.</p>
            <form action={inviteStaff} className="card form-stack staff-invite">
              <label className="field">
                <span className="field-label">Email</span>
                <input className="field-input" type="email" name="email" autoComplete="off" maxLength={254} required />
              </label>
              <fieldset className="role-choice">
                <legend className="field-label">Role</legend>
                <label>
                  <input type="radio" name="role" value="staff" defaultChecked />
                  <span><strong>Staff</strong> can read the console.</span>
                </label>
                <label>
                  <input type="radio" name="role" value="owner" />
                  <span><strong>Owner</strong> can also invite and disable people.</span>
                </label>
              </fieldset>
              <button type="submit" className="button button-primary">Send invitation</button>
            </form>
          </section>
        ) : null}
      </>
    );
  }

  return (
    <main>
      <div className="page-head">
        <div className="container">
          {actions}
          <p className="overline">Admin</p>
          <h1 className="title1">Staff</h1>
          <p className="page-lede">Who can open the staff console.</p>
        </div>
      </div>
      <div className="container inspector-body">
        {message && !problem ? <p className="card inspector-empty" role="status">{message}</p> : null}
        {problem ? (
          <p className="form-error" role="alert">
            {problem}
            {reference ? <> Reference: <code>{reference}</code></> : null}
          </p>
        ) : null}
        {body}
      </div>
    </main>
  );
}
