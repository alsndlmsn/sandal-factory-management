import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json'
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return new Response(JSON.stringify({ error: 'يلزم تسجيل الدخول.' }), { status: 401, headers: cors });
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey);
    const token = authHeader.replace('Bearer ', '');
    const { data: { user: caller }, error: callerError } = await admin.auth.getUser(token);
    if (callerError || !caller) return new Response(JSON.stringify({ error: 'جلسة الدخول غير صالحة.' }), { status: 401, headers: cors });
    const { data: managerRole } = await admin.from('roles').select('id').eq('code', 'manager').maybeSingle();
    const { data: managerAccess } = await admin.from('user_roles').select('user_id').eq('user_id', caller.id).eq('role_id', managerRole?.id || '').maybeSingle();
    if (!managerAccess) return new Response(JSON.stringify({ error: 'هذه العملية متاحة للمدير فقط.' }), { status: 403, headers: cors });
    const body = await req.json();
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    const full_name = String(body.full_name || '').trim();
    const role_code = String(body.role_code || 'sales');
    if (!email || !password || !full_name || password.length < 8) return new Response(JSON.stringify({ error: 'أدخل الاسم والبريد وكلمة مرور لا تقل عن 8 أحرف.' }), { status: 400, headers: cors });
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name } });
    if (createError || !created.user) return new Response(JSON.stringify({ error: createError?.message || 'تعذر إنشاء المستخدم.' }), { status: 400, headers: cors });
    const { error: profileError } = await admin.from('profiles').upsert({ id: created.user.id, email, full_name, is_enabled: true, must_change_password: true });
    if (profileError) throw profileError;
    const { data: selectedRole } = await admin.from('roles').select('id').eq('code', role_code).maybeSingle();
    if (!selectedRole) throw new Error('الدور المختار غير موجود.');
    const { error: roleError } = await admin.from('user_roles').insert({ user_id: created.user.id, role_id: selectedRole.id, assigned_by: caller.id });
    if (roleError) throw roleError;
    return new Response(JSON.stringify({ ok: true, user_id: created.user.id }), { status: 200, headers: cors });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'حدث خطأ غير متوقع.' }), { status: 500, headers: cors });
  }
});
