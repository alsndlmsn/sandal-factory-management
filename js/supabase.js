const appConfig = window.APP_CONFIG || {};
const supabaseReady = Boolean(appConfig.supabaseUrl && appConfig.supabaseAnonKey && window.supabase);
const db = supabaseReady ? window.supabase.createClient(appConfig.supabaseUrl, appConfig.supabaseAnonKey) : null;

async function dbSelect(table, columns='*', options={}) {
  if (!db) throw new Error('لم يتم إعداد اتصال Supabase بعد.');
  let query = db.from(table).select(columns);
  if (options.order) query = query.order(options.order.column, { ascending: options.order.ascending !== false });
  if (options.limit) query = query.limit(options.limit);
  if (options.eq) Object.entries(options.eq).forEach(([key,value]) => { query = query.eq(key,value); });
  if (options.gte) query = query.gte(options.gte[0], options.gte[1]);
  if (options.lt) query = query.lt(options.lt[0], options.lt[1]);
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}
async function dbInsert(table, payload) { if (!db) throw new Error('لم يتم إعداد اتصال Supabase بعد.'); const { data, error } = await db.from(table).insert(payload).select().single(); if (error) throw error; return data; }
async function dbRpc(name, args={}) { if (!db) throw new Error('لم يتم إعداد اتصال Supabase بعد.'); const { data, error } = await db.rpc(name, args); if (error) throw error; return data; }
async function dbFunction(name, payload={}) { if (!db) throw new Error('لم يتم إعداد اتصال Supabase بعد.'); const { data, error } = await db.functions.invoke(name, { body: payload }); if (error) throw error; return data; }
function friendlyError(error) { const message = String(error?.message || error || 'حدث خطأ غير معروف'); if (/JWT|auth|password|credential/i.test(message)) return 'بيانات الدخول غير صحيحة أو انتهت الجلسة.'; if (/permission|policy|denied|RLS/i.test(message)) return 'ليست لديك صلاحية لتنفيذ هذه العملية.'; if (/duplicate|unique/i.test(message)) return 'هذا الرقم مستخدم من قبل، اختر رقمًا آخر.'; return message; }
