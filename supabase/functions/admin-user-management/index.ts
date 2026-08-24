import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const attempts = new Map<string, number[]>();
const allowedActions = new Set(['set_temporary_password', 'send_recovery_email', 'disable_user', 'enable_user', 'change_role']);
const roles = new Set(['manager', 'sales', 'warehouse', 'cashier', 'payroll']);

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}
function cleanError() { return response({ error: 'تعذر تنفيذ إدارة المستخدم. تحقق من الصلاحيات والبيانات.' }, 400); }
function rateLimited(key: string) {
  const now = Date.now();
  const recent = (attempts.get(key) || []).filter((time) => now - time < 15 * 60 * 1000);
  recent.push(now);
  attempts.set(key, recent);
  return recent.length > 5;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response({ error: 'طريقة الطلب غير مسموحة.' }, 405);
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = request.headers.get('Authorization');
  if (!supabaseUrl || !serviceKey || !authHeader?.startsWith('Bearer ')) return response({ error: 'جلسة غير صالحة.' }, 401);

  const admin = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const accessToken = authHeader.replace('Bearer ', '');
  const { data: actorData, error: actorError } = await admin.auth.getUser(accessToken);
  if (actorError || !actorData.user) return response({ error: 'انتهت الجلسة أو لم تعد صالحة.' }, 401);
  const actorId = actorData.user.id;
  const { data: actor, error: profileError } = await admin.from('profiles').select('id,full_name,email,role,is_enabled').eq('id', actorId).single();
  if (profileError || actor?.role !== 'manager' || actor.is_enabled !== true) return response({ error: 'هذه العملية متاحة لمدير النظام فقط.' }, 403);

  let payload: Record<string, unknown>;
  try { payload = await request.json(); } catch { return cleanError(); }
  const action = String(payload.action || '');
  const targetUserId = String(payload.target_user_id || '');
  const reason = String(payload.reason || '').trim();
  if (!allowedActions.has(action) || !targetUserId || reason.length < 3 || targetUserId === actorId && action === 'set_temporary_password') return cleanError();
  if (rateLimited(`${actorId}:${targetUserId}`)) return response({ error: 'تم تجاوز عدد المحاولات. حاول بعد 15 دقيقة.' }, 429);

  const { data: target, error: targetError } = await admin.from('profiles').select('id,full_name,email,role,is_enabled').eq('id', targetUserId).single();
  if (targetError || !target) return response({ error: 'المستخدم المستهدف غير موجود.' }, 404);
  let auditAction = action;
  let auditAfter: Record<string, unknown> = { action };

  try {
    if (action === 'set_temporary_password') {
      const temporaryPassword = String(payload.temporary_password || '');
      if (targetUserId === actorId || temporaryPassword.length < 12 || /^(.)\1+$/.test(temporaryPassword) || !/[A-Za-z]/.test(temporaryPassword) || !/\d/.test(temporaryPassword)) return response({ error: 'كلمة المرور المؤقتة ضعيفة أو غير صالحة.' }, 400);
      const { error } = await admin.auth.admin.updateUserById(targetUserId, { password: temporaryPassword });
      if (error) throw error;
      const { error: updateError } = await admin.from('profiles').update({ must_change_password: true, password_reset_at: new Date().toISOString() }).eq('id', targetUserId);
      if (updateError) throw updateError;
      auditAction = 'temporary password set';
      auditAfter = { must_change_password: true };
    } else if (action === 'send_recovery_email') {
      if (!target.email) return response({ error: 'لا يوجد بريد إلكتروني لهذا المستخدم.' }, 400);
      const { error } = await admin.auth.resetPasswordForEmail(target.email);
      if (error) throw error;
      auditAction = 'recovery email requested';
      auditAfter = { email: target.email };
    } else if (action === 'disable_user' || action === 'enable_user') {
      const { error } = await admin.auth.admin.updateUserById(targetUserId, { ban_duration: action === 'disable_user' ? '876000h' : 'none' });
      if (error) throw error;
      const { error: updateError } = await admin.from('profiles').update({ is_enabled: action === 'enable_user', updated_at: new Date().toISOString() }).eq('id', targetUserId);
      if (updateError) throw updateError;
      auditAfter = { is_enabled: action === 'enable_user' };
    } else if (action === 'change_role') {
      const newRole = String(payload.new_role || '');
      if (targetUserId === actorId || !roles.has(newRole)) return response({ error: 'الدور الجديد غير صالح.' }, 400);
      const { error } = await admin.rpc('change_user_role', { p_target_user_id: targetUserId, p_new_role: newRole, p_reason: reason });
      if (error) throw error;
      auditAfter = { role: newRole };
    }
    const { error: auditError } = await admin.from('audit_logs').insert({ actor_id: actorId, actor_display_name: actor.full_name || actor.email || 'مدير', action: auditAction, entity_type: 'profile', entity_id: targetUserId, before_data: { role: target.role, is_enabled: target.is_enabled }, after_data: auditAfter, reason, severity: 'high', local_display_time: new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Khartoum', dateStyle: 'short', timeStyle: 'medium' }).format(new Date()) });
    if (auditError) throw auditError;
    return response({ success: true, action: auditAction });
  } catch (_error) {
    return response({ error: 'لم يتم تنفيذ العملية. لم يتم إرجاع أي كلمة مرور أو رمز سري.' }, 400);
  }
});
