import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "طريقة الطلب غير مسموحة." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || request.headers.get("apikey");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !authorization?.startsWith("Bearer ")) {
    return json({ error: "جلسة غير صالحة." }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const accessToken = authorization.slice("Bearer ".length);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: actorData, error: actorError } = await admin.auth.getUser(accessToken);
  if (actorError || !actorData.user) return json({ error: "انتهت الجلسة أو لم تعد صالحة." }, 401);

  const { data: actor, error: actorProfileError } = await admin
    .from("profiles")
    .select("id,full_name,email,is_manager,is_enabled")
    .eq("id", actorData.user.id)
    .maybeSingle();
  if (actorProfileError || !actor || actor.is_manager !== true || actor.is_enabled !== true) {
    return json({ error: "هذه العملية متاحة لمدير النظام فقط." }, 403);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "بيانات الطلب غير صالحة." }, 400);
  }
  const targetUserId = String(payload.target_user_id || "").trim();
  const reason = String(payload.reason || "").trim();
  if (!targetUserId || reason.length < 3 || targetUserId === actor.id) {
    return json({ error: "المستخدم المستهدف أو سبب الأرشفة غير صالح." }, 400);
  }

  const { data: target, error: targetError } = await admin
    .from("profiles")
    .select("id,full_name,email,is_enabled,deleted_at")
    .eq("id", targetUserId)
    .maybeSingle();
  if (targetError || !target) return json({ error: "المستخدم المستهدف غير موجود." }, 404);
  let archived = target.deleted_at !== null;
  if (!archived) {
    const { data: archiveResult, error: archiveError } = await userClient.rpc("admin_delete_user", {
      p_user_id: targetUserId,
      p_reason: reason,
    });
    if (archiveError) return json({ error: "تعذر أرشفة المستخدم مع حفظ سجله." }, 400);
    archived = archiveResult?.archived === true || archiveResult?.is_enabled === false;
  }

  const { error: banError } = await admin.auth.admin.updateUserById(targetUserId, {
    ban_duration: "876000h",
  });
  if (banError) {
    return json({ archived: true, auth_disabled: false, warning: "تمت الأرشفة، ويلزم مراجعة تعطيل دخول Auth." }, 207);
  }

  return json({ archived, auth_disabled: true });
});
