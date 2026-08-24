import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.57.4/+esm';

const config = window.APP_CONFIG || {};
const validUrl = typeof config.SUPABASE_URL === 'string' && config.SUPABASE_URL.startsWith('https://') && !config.SUPABASE_URL.includes('YOUR_PROJECT');
const validKey = typeof config.SUPABASE_PUBLISHABLE_KEY === 'string' && config.SUPABASE_PUBLISHABLE_KEY.length > 20 && !config.SUPABASE_PUBLISHABLE_KEY.includes('YOUR_');

export const isSupabaseConfigured = validUrl && validKey;
export const factoryConfig = {
  factoryName: config.FACTORY_NAME || 'مصنع الصنادل البلاستيكية',
  timezone: config.FACTORY_TIMEZONE || 'Africa/Khartoum',
};

export const supabase = isSupabaseConfigured
  ? createClient(config.SUPABASE_URL, config.SUPABASE_PUBLISHABLE_KEY, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;

export function requireSupabase() {
  if (!supabase) {
    throw new Error('لم يتم إعداد اتصال Supabase. انسخ config.example.js إلى config.js وأدخل الرابط والمفتاح العام.');
  }
  return supabase;
}

export function getErrorMessage(error) {
  const message = error?.message || error?.details || 'حدث خطأ غير معروف.';
  const known = {
    'Invalid login credentials': 'بيانات الدخول غير صحيحة.',
    'Email not confirmed': 'لم يتم تأكيد البريد الإلكتروني بعد.',
    'JWT expired': 'انتهت الجلسة، يرجى تسجيل الدخول مرة أخرى.',
    'new row violates row-level security policy': 'ليست لديك صلاحية لتنفيذ هذا الإجراء.',
  };
  return known[message] || message;
}
