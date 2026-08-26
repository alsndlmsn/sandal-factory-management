(() => {
  const cfg = window.APP_CONFIG || {};
  const DB_NAME = cfg.offlineDbName || 'sandal_factory_offline_v2';
  const DB_VERSION = 1;
  const KEY_ID = 'cache-key-v1';
  let dbPromise;
  let keyPromise;

  const bytesToBase64 = bytes => {
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
    return btoa(binary);
  };
  const base64ToBytes = value => {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  };
  const openDb = () => {
    if (!('indexedDB' in window)) return Promise.reject(new Error('IndexedDB غير متاح في هذا المتصفح.'));
    if (dbPromise) return dbPromise;
    dbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv', { keyPath: 'id' });
        if (!db.objectStoreNames.contains('outbox')) db.createObjectStore('outbox', { keyPath: 'idempotency_key' });
        if (!db.objectStoreNames.contains('receipts')) db.createObjectStore('receipts', { keyPath: 'idempotency_key' });
        if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta', { keyPath: 'id' });
      };
      request.onsuccess = () => {
        const db = request.result;
        db.onversionchange = () => db.close();
        resolve(db);
      };
      request.onerror = () => reject(request.error || new Error('تعذر فتح التخزين المحلي الآمن.'));
      request.onblocked = () => reject(new Error('يوجد تبويب قديم يمنع تحديث التخزين المحلي. أغلق التبويبات الأخرى ثم أعد المحاولة.'));
    });
    return dbPromise;
  };
  const txRequest = (storeName, mode, operation) => openDb().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode);
    const store = tx.objectStore(storeName);
    let request;
    try { request = operation(store); } catch (error) { reject(error); return; }
    let result;
    request.onsuccess = () => { result = request.result; };
    request.onerror = () => reject(request.error || new Error('تعذر الوصول إلى التخزين المحلي.'));
    tx.oncomplete = () => resolve(result);
    tx.onerror = () => reject(tx.error || new Error('فشلت معاملة التخزين المحلي.'));
    tx.onabort = () => reject(tx.error || new Error('أُلغيت معاملة التخزين المحلي.'));
  }));
  const getKey = async () => {
    if (keyPromise) return keyPromise;
    keyPromise = (async () => {
      if (!window.crypto?.subtle) throw new Error('التشفير المحلي غير متاح؛ يجب استخدام HTTPS ومتصفح حديث.');
      const existing = await txRequest('meta', 'readonly', store => store.get(KEY_ID));
      if (existing?.key) return existing.key;
      const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
      await txRequest('meta', 'readwrite', store => store.put({ id: KEY_ID, key, created_at: new Date().toISOString() }));
      return key;
    })().catch(error => { keyPromise = null; throw error; });
    return keyPromise;
  };
  const encrypt = async (id, value) => {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const encoded = new TextEncoder().encode(JSON.stringify(value));
    const aad = new TextEncoder().encode(String(id));
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad, tagLength: 128 }, await getKey(), encoded);
    return { version: 1, algorithm: 'AES-GCM', iv: bytesToBase64(iv), ciphertext: bytesToBase64(new Uint8Array(ciphertext)), saved_at: new Date().toISOString() };
  };
  const decrypt = async (id, record) => {
    if (!record?.ciphertext || !record?.iv) throw new Error('سجل التخزين المحلي غير صالح.');
    const aad = new TextEncoder().encode(String(id));
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: base64ToBytes(record.iv), additionalData: aad, tagLength: 128 }, await getKey(), base64ToBytes(record.ciphertext));
    return JSON.parse(new TextDecoder().decode(plain));
  };
  const get = async id => {
    const record = await txRequest('kv', 'readonly', store => store.get(id));
    if (!record) return null;
    try { return await decrypt(id, record); } catch (error) {
      window.dispatchEvent(new CustomEvent('offline:storage-error', { detail: { id, error: String(error.message || error) } }));
      return null;
    }
  };
  const put = async (id, value) => { const encrypted = await encrypt(id, value); return txRequest('kv', 'readwrite', store => store.put({ id, ...encrypted })); };
  const remove = async id => txRequest('kv', 'readwrite', store => store.delete(id));
  const list = async () => {
    const records = await txRequest('kv', 'readonly', store => store.getAll());
    const output = [];
    for (const record of records || []) {
      try { output.push({ id: record.id, value: await decrypt(record.id, record), saved_at: record.saved_at }); } catch {}
    }
    return output;
  };
  const migrateLegacyCache = async legacyKey => {
    const marker = await txRequest('meta', 'readonly', store => store.get('legacy-cache-migrated-v1'));
    if (marker?.done) return { migrated: 0, skipped: true };
    let legacy = {};
    try { legacy = JSON.parse(localStorage.getItem(legacyKey) || '{}'); } catch {}
    const entries = Object.entries(legacy).filter(([, item]) => item && typeof item === 'object' && 'data' in item);
    for (const [id, item] of entries) await put(`cache:${id}`, item);
    await txRequest('meta', 'readwrite', store => store.put({ id: 'legacy-cache-migrated-v1', done: true, migrated: entries.length, at: new Date().toISOString() }));
    if (entries.length) { try { localStorage.removeItem(legacyKey); } catch {} }
    return { migrated: entries.length, skipped: false };
  };
  const enqueue = async item => {
    if (!item?.idempotency_key) throw new Error('لا يمكن حفظ عملية دون Idempotency Key.');
    const existing = await txRequest('outbox', 'readonly', store => store.get(item.idempotency_key));
    if (existing) return existing;
    const record = { ...item, status: item.status || 'pending', attempts: Number(item.attempts || 0), created_at_client: item.created_at_client || new Date().toISOString(), updated_at_client: new Date().toISOString() };
    if (Object.prototype.hasOwnProperty.call(record, 'payload')) { record.payload_cipher = await encrypt(`outbox:${item.idempotency_key}`, record.payload); delete record.payload; }
    await txRequest('outbox', 'readwrite', store => store.add(record));
    return { ...record, payload: item.payload };
  };
  const getOutbox = async () => {
    const records = await txRequest('outbox', 'readonly', store => store.getAll());
    const output = [];
    for (const record of records || []) {
      try { output.push(record.payload_cipher ? { ...record, payload: await decrypt(`outbox:${record.idempotency_key}`, record.payload_cipher) } : record); } catch (error) { output.push({ ...record, status: 'conflict', error: 'تعذر فك تشفير العملية المحلية.' }); }
    }
    return output;
  };
  const updateOutbox = async (idempotencyKey, patch) => {
    const current = await txRequest('outbox', 'readonly', store => store.get(idempotencyKey));
    if (!current) return null;
    const next = { ...current, ...patch, updated_at_client: new Date().toISOString() };
    if (Object.prototype.hasOwnProperty.call(next, 'payload')) { next.payload_cipher = await encrypt(`outbox:${idempotencyKey}`, next.payload); delete next.payload; }
    return txRequest('outbox', 'readwrite', store => store.put(next));
  };
  const saveReceipt = async receipt => txRequest('receipts', 'readwrite', store => store.put(receipt));
  const getReceipt = async key => txRequest('receipts', 'readonly', store => store.get(key));
  window.offlineStore = { openDb, get, put, remove, list, migrateLegacyCache, enqueue, getOutbox, updateOutbox, saveReceipt, getReceipt, getKey };
})();
