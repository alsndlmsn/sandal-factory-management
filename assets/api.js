import { requireSupabase, getErrorMessage } from './supabase-client.js';

export async function selectRows(table, { columns = '*', filters = [], order = 'created_at.desc', limit = 100, offset = 0 } = {}) {
  const client = requireSupabase();
  let query = client.from(table).select(columns, { count: 'exact' });
  filters.forEach(({ field, operator = 'eq', value }) => {
    if (value !== undefined && value !== null && value !== '') query = query[operator](field, value);
  });
  if (order) {
    const [column, direction = 'asc'] = order.split('.');
    query = query.order(column, { ascending: direction !== 'desc' });
  }
  const { data, error, count } = await query.range(offset, offset + limit - 1);
  if (error) throw new Error(getErrorMessage(error));
  return { data: data || [], count: count || 0 };
}

export async function selectOne(table, id, columns = '*') {
  const client = requireSupabase();
  const { data, error } = await client.from(table).select(columns).eq('id', id).maybeSingle();
  if (error) throw new Error(getErrorMessage(error));
  return data;
}

export async function insertRow(table, payload) {
  const client = requireSupabase();
  const { data: authData } = await client.auth.getUser();
  const needsActor = !['profiles', 'units', 'item_unit_conversions', 'sale_lines', 'inventory_transaction_lines'].includes(table);
  const enrichedPayload = needsActor && authData.user?.id && payload.created_by === undefined
    ? { ...payload, created_by: authData.user.id }
    : payload;
  const { data, error } = await client.from(table).insert(enrichedPayload).select().single();
  if (error) throw new Error(getErrorMessage(error));
  return data;
}

export async function updateRow(table, id, payload) {
  const client = requireSupabase();
  const { data, error } = await client.from(table).update(payload).eq('id', id).eq('status', 'draft').select().single();
  if (error) throw new Error(getErrorMessage(error));
  return data;
}

export async function callRpc(name, args = {}) {
  const client = requireSupabase();
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(getErrorMessage(error));
  return data;
}

export async function getDashboard() {
  return callRpc('dashboard_summary');
}

export async function getCurrentUser() {
  const client = requireSupabase();
  const { data, error } = await client.auth.getUser();
  if (error) throw new Error(getErrorMessage(error));
  return data.user;
}

export async function callAdminUserManagement(payload) {
  const client = requireSupabase();
  const { data, error } = await client.functions.invoke('admin-user-management', { body: payload });
  if (error) throw new Error(getErrorMessage(error));
  if (data?.error) throw new Error(data.error);
  return data;
}

export function downloadCsv(filename, rows, columns) {
  const escape = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`;
  const body = [columns.map((column) => escape(column.label)).join(','), ...rows.map((row) => columns.map((column) => escape(column.value(row))).join(','))].join('\n');
  const blob = new Blob(['\ufeff' + body], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
