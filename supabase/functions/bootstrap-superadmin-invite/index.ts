import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const AUTHORIZED_EMAIL_SHA256 = "ae96df648c47167723de76f37ffdeaab11526f451c608d6f0e81ab8622017f67";
const ACCEPTED = { ok: true, code: "activation_request_accepted" } as const;

type ExistingAuthUser = {
  email?: string | null;
  invited_at?: string | null;
  email_confirmed_at?: string | null;
  confirmed_at?: string | null;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(405, { ok: false, code: "method_not_allowed" });
  }

  // Both values are deliberately kept outside source control. Until they exist,
  // bootstrap remains closed and cannot emit an invitation.
  const activationUrl = Deno.env.get("CBTA_ADMIN_ACTIVATION_URL")?.trim();
  const authorizedEmail = Deno.env.get("CBTA_BOOTSTRAP_EMAIL")?.trim().toLowerCase();
  if (!activationUrl || !authorizedEmail) {
    return json(503, { ok: false, code: "bootstrap_not_enabled" });
  }

  if ((await sha256Hex(authorizedEmail)) !== AUTHORIZED_EMAIL_SHA256) {
    return json(503, { ok: false, code: "bootstrap_misconfigured" });
  }

  let parsedActivationUrl: URL;
  try {
    parsedActivationUrl = new URL(activationUrl);
  } catch {
    return json(503, { ok: false, code: "bootstrap_misconfigured" });
  }

  if (
    parsedActivationUrl.protocol !== "https:" ||
    parsedActivationUrl.pathname !== "/auth/confirm" ||
    parsedActivationUrl.search !== "" ||
    parsedActivationUrl.hash !== "" ||
    parsedActivationUrl.username !== "" ||
    parsedActivationUrl.password !== ""
  ) {
    return json(503, { ok: false, code: "bootstrap_misconfigured" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const rawSecretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!supabaseUrl || !rawSecretKeys) {
    return json(503, { ok: false, code: "backend_not_ready" });
  }

  let secretKey: string | undefined;
  try {
    secretKey = (JSON.parse(rawSecretKeys) as Record<string, string>)["default"];
  } catch {
    return json(503, { ok: false, code: "backend_not_ready" });
  }

  if (!secretKey) {
    return json(503, { ok: false, code: "backend_not_ready" });
  }

  const admin = createClient(supabaseUrl, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Inspect only the fixed recipient. If an unconfirmed identity was created by a
  // public sign-up attempt before bootstrap, inviting it upgrades that existing
  // record into the controlled invite flow (Supabase stamps invited_at). Once an
  // invite was already issued, do not resend it from this public one-purpose endpoint.
  const { data: usersPage, error: usersError } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });

  if (usersError) {
    console.error("bootstrap listUsers failed", usersError.message);
    return json(503, { ok: false, code: "temporarily_unavailable" });
  }

  const existing = usersPage.users.find(
    (user) => user.email?.trim().toLowerCase() === authorizedEmail,
  ) as ExistingAuthUser | undefined;

  if (existing?.invited_at || existing?.email_confirmed_at || existing?.confirmed_at) {
    return json(202, ACCEPTED);
  }

  const { error: inviteError } = await admin.auth.admin.inviteUserByEmail(
    authorizedEmail,
    { redirectTo: activationUrl },
  );

  if (inviteError) {
    // Keep provider/account state server-side. The external response is identical
    // whether the request won a race, the account changed state, or the invite sent.
    console.error("bootstrap invite failed", inviteError.message);
  }

  return json(202, ACCEPTED);
});
