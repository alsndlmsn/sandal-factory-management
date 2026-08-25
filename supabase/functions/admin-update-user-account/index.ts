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

function validEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
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

  const accessToken = authorization.slice("Bearer ".length);
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: actorData, error: actorError } = await admin.auth.getUser(accessToken);
  if (actorError || !actorData.user) return json({ error: "انتهت الجلسة أو لم تعد صالحة." }, 401);

  const { data: actor, error: actorProfileError } = await admin
    .from("profiles")
    .select("id,is_manager,is_enabled")
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
  const newEmail = String(payload.new_email || "").trim().toLowerCase();
  const newPassword = String(payload.new_password || "");
  if (!targetUserId || targetUserId === actor.id || reason.length < 3) {
    return json({ error: "المستخدم أو سبب التعديل غير صالح." }, 400);
  }
  if (!newEmail && !newPassword) return json({ error: "أدخل بريدًا جديدًا أو كلمة مرور مؤقتة." }, 400);
  if (newEmail && !validEmail(newEmail)) return json({ error: "صيغة البريد الإلكتروني غير صحيحة." }, 400);
  if (newPassword && newPassword.length < 8) return json({ error: "كلمة المرور المؤقتة يجب ألا تقل عن 8 أحرف." }, 400);

  const { data: target, error: targetError } = await admin
    .from("profiles")
    .select("id,email,full_name,is_enabled,deleted_at")
    .eq("id", targetUserId)
    .maybeSingle();
  if (targetError || !target) return json({ error: "المستخدم المستهدف غير موجود." }, 404);
  if (target.deleted_at) return json({ error: "لا يمكن تعديل حساب مؤرشف." }, 400);

  const oldEmail = target.email || "";
  const authUpdate: { email?: string; email_confirm?: boolean; password?: string } = {};
  if (newEmail && newEmail !== oldEmail.toLowerCase()) {
    authUpdate.email = newEmail;
    authUpdate.email_confirm = true;
  }
  if (newPassword) authUpdate.password = newPassword;

  if (Object.keys(authUpdate).length) {
    const { error: authError } = await admin.auth.admin.updateUserById(targetUserId, authUpdate);
    if (authError) return json({ error: "تعذر تحديث حساب Auth. لم يتم حفظ التعديل." }, 400);
  }

  if (authUpdate.email) {
    const { error: profileError } = await admin
      .from("profiles")
      .update({ email: authUpdate.email })
      .eq("id", targetUserId);
    if (profileError) return json({ error: "تم تحديث Auth لكن تعذر تحديث ملف المستخدم؛ راجع التدقيق وأعد المحاولة." }, 207);
  }

  const { error: auditError } = await admin.from("activity_logs").insert({
    actor_id: actor.id,
    action: "user_account_update",
    entity_type: "profile",
    entity_id: targetUserId,
    old_data: { email: oldEmail, password_changed: false },
    new_data: { email: authUpdate.email || oldEmail, password_changed: Boolean(authUpdate.password) },
    reason,
    severity: "critical",
  });
  if (auditError) return json({ error: "تم التحديث لكن تعذر تسجيل التدقيق؛ راجع السجل الإداري." }, 207);

  return json({ email_updated: Boolean(authUpdate.email), password_reset: Boolean(authUpdate.password) });
});
