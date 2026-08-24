import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json'
};
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return response({ error: 'يلزم تسجيل الدخول.' }, 401);
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const token = authHeader.replace('Bearer ', '');
    const { data: { user: caller }, error: callerError } = await admin.auth.getUser(token);
    if (callerError || !caller) return response({ error: 'جلسة الدخول غير صالحة.' }, 401);
    const { data: managerRole } = await admin.from('roles').select('id').eq('code', 'manager').maybeSingle();
    const { data: managerAccess } = await admin.from('user_roles').select('user_id').eq('user_id', caller.id).eq('role_id', managerRole?.id || '').maybeSingle();
    if (!managerAccess) return response({ error: 'هذه العملية متاحة للمدير فقط.' }, 403);
    const body = await req.json();
    const action = String(body.action || 'create');
    const roleCode = String(body.role_code || 'sales');

    if (action === 'update') {
      const userId = String(body.user_id || '');
      const fullName = String(body.full_name || '').trim();
      const password = String(body.password || '');
      if (!userId || !fullName) return response({ error: 'بيانات المستخدم غير مكتملة.' }, 400);
      const authUpdate: Record<string, unknown> = { user_metadata: { full_name: fullName } };
      if (password) {
        if (password.length < 8) return response({ error: 'كلمة المرور لا تقل عن 8 أحرف.' }, 400);
        authUpdate.password = password;
      }
      const { error: authError } = await admin.auth.admin.updateUserById(userId, authUpdate);
      if (authError) return response({ error: authError.message }, 400);
      const { error: profileError } = await admin.from('profiles').update({ full_name: fullName, is_enabled: body.is_enabled !== false, updated_at: new Date().toISOString() }).eq('id', userId);
      if (profileError) throw profileError;
      const { data: selectedRole } = await admin.from('roles').select('id').eq('code', roleCode).maybeSingle();
      if (!selectedRole) return response({ error: 'الدور المختار غير موجود.' }, 400);
      await admin.from('user_roles').delete().eq('user_id', userId);
      const { error: roleError } = await admin.from('user_roles').insert({ user_id: userId, role_id: selectedRole.id, assigned_by: caller.id });
      if (roleError) throw roleError;
      return response({ ok: true, user_id: userId });
    }

    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    const fullName = String(body.full_name || '').trim();
    if (!email || !password || !fullName || password.length < 8) return response({ error: 'أدخل الاسم والبريد وكلمة مرور لا تقل عن 8 أحرف.' }, 400);
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName } });
    if (createError || !created.user) return response({ error: createError?.message || 'تعذر إنشاء المستخدم.' }, 400);
    const { error: profileError } = await admin.from('profiles').upsert({ id: created.user.id, email, full_name: fullName, is_enabled: true, must_change_password: true });
    if (profileError) throw profileError;
    const { data: selectedRole } = await admin.from('roles').select('id').eq('code', roleCode).maybeSingle();
    if (!selectedRole) return response({ error: 'الدور المختار غير موجود.' }, 400);
    const { error: roleError } = await admin.from('user_roles').insert({ user_id: created.user.id, role_id: selectedRole.id, assigned_by: caller.id });
    if (roleError) throw roleError;
    return response({ ok: true, user_id: created.user.id });
  } catch (error) {
    return response({ error: error instanceof Error ? error.message : 'حدث خطأ غير متوقع.' }, 500);
  }
});
