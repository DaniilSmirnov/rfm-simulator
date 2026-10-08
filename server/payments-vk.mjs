import { Buffer } from 'node:buffer';
import { createHash, timingSafeEqual } from 'node:crypto';
import { catalog } from './store.mjs';

export const PAYMENT_HANDLER_VERSION = 'vk-test-callback-v4';

export class PaymentError extends Error {
  constructor(code, message, critical = true) { super(message); this.code = code; this.critical = critical; }
}
const reject = message => { throw new PaymentError(20, message); };
const id = value => typeof value === 'string' && /^[1-9]\d{0,14}$/.test(value) && Number.isSafeInteger(Number(value));
export function testBuyer(env, user) {
  return env.VK_PAYMENTS_MODE === 'test' && id(user) &&
    (env.VK_PAYMENTS_TEST_USERS || '').split(',').map(s => s.trim()).some(s => s === '*' || s === user) &&
    /^[1-9]\d{0,3}$/.test(env.VK_STAGE_02_TEST_PRICE || '') && !!env.PAYMENTS;
}
export function paymentCatalog(env, user) {
  return catalog.map(p => ({...p, purchase_enabled: p.sku === 'stage_02' && testBuyer(env, user),
    ...(p.sku === 'stage_02' && testBuyer(env, user) ? {payment_mode:'test', price:Number(env.VK_STAGE_02_TEST_PRICE)} : {})}));
}
export async function ledger(env, action, body) {
  const object = env.PAYMENTS.get(env.PAYMENTS.idFromName(`vk:${env.VK_APP_ID}`));
  const response = await object.fetch(new Request(`https://ledger/${action}`, {method:'POST',body:JSON.stringify(body)}));
  const data = await response.json();
  if (!response.ok) throw new PaymentError(data.code || 1, data.error || 'Хранилище покупок недоступно.', response.status < 500);
  return data;
}
export async function accountStore(env, user) {
  const skus = testBuyer(env, user) ? (await ledger(env, 'rights', {user,mode:'test'})).skus : [];
  return {entitlements:{mode:'restricted',skus},catalog:paymentCatalog(env,user)};
}
export async function preparePurchase(env, user, sku) {
  if (!testBuyer(env,user) || sku !== 'stage_02') reject('Тестовая покупка недоступна.');
  const store = await accountStore(env,user);
  return {...store,item:sku,owned:store.entitlements.skus.includes(sku)};
}
export function verifyCallback(raw, env) {
  if (!env.VK_APP_SECRET || !id(env.VK_APP_ID)) throw new PaymentError(1,'Платежи не настроены.',false);
  if (raw.length > 16384) reject('Слишком большое уведомление.');
  const params = new URLSearchParams(raw);
  const values = Object.create(null);
  for (const [key,value] of params) {
    if (!/^[a-z][a-z0-9_]*$/.test(key) || Object.hasOwn(values,key)) reject('Некорректные параметры.');
    values[key] = value;
  }
  const signature = values.sig;
  if (!/^[a-f0-9]{32}$/.test(signature || '')) throw new PaymentError(10,'Некорректная подпись.');
  const canonical = Object.keys(values).filter(k=>k!=='sig').sort().map(k=>`${k}=${values[k]}`).join('');
  const expected = createHash('md5').update(canonical + env.VK_APP_SECRET,'utf8').digest('hex');
  if (!timingSafeEqual(Buffer.from(signature),Buffer.from(expected))) throw new PaymentError(10,'Некорректная подпись.');
  if (values.app_id !== env.VK_APP_ID || !testBuyer(env,values.user_id)) reject('Тестовые платежи недоступны для этого аккаунта.');
  if (values.receiver_id && values.receiver_id !== values.user_id) reject('Подарки не поддерживаются.');
  return values;
}
export async function paymentCallback(raw, env) {
  const p = verifyCallback(raw,env);
  // Item metadata is read-only; only the explicitly test order callback can grant rights.
  if (p.notification_type === 'get_item_test' || p.notification_type === 'get_item') {
    if (p.item !== 'stage_02') reject('Товар не существует.');
    return {response:{item_id:'stage_02',title:'Зимний Турини (тест)',photo_url:'',price:Number(env.VK_STAGE_02_TEST_PRICE)}};
  }
  if (p.notification_type !== 'order_status_change_test') {
    const received = typeof p.notification_type === 'string' ? p.notification_type.slice(0, 64) : null;
    reject(`Неподдерживаемый notification_type=${JSON.stringify(received)}. Ожидается get_item, get_item_test или order_status_change_test. Обработчик: ${PAYMENT_HANDLER_VERSION}.`);
  }
  if (p.status !== 'chargeable') throw new PaymentError(100,'Неподдерживаемый статус заказа.');
  // VK sends the SKU as item_id and the price as item_price. Keep legacy
  // numeric-ID/amount callbacks compatible, but reject conflicting fields.
  const amount = p.item_price ?? p.amount;
  if (!id(p.order_id) || !['stage_02', '2'].includes(p.item_id) ||
      (p.item !== undefined && p.item !== 'stage_02') || !id(amount) ||
      (p.amount !== undefined && (!id(p.amount) || p.amount !== amount))) {
    reject('Некорректный заказ или стоимость.');
  }
  const receipt = await ledger(env,'grant',{mode:'test',order:p.order_id,user:p.user_id,sku:'stage_02',amount:Number(amount),expected_price:Number(env.VK_STAGE_02_TEST_PRICE)});
  return {response:receipt};
}

// SQL rows are the source of ownership; deleting an order revokes its grant
// unless another confirmed order for the same user/SKU remains.
export class VkPayments {
  constructor(ctx) {
    this.storage = ctx.storage;
    this.ready = ctx.blockConcurrencyWhile
      ? ctx.blockConcurrencyWhile(() => this.initialize()) : this.initialize();
  }
  async initialize() {
    const sql = this.storage.sql;
    sql.exec(`CREATE TABLE IF NOT EXISTS payment_orders (
      mode TEXT NOT NULL CHECK(mode = 'test'), order_id TEXT NOT NULL,
      user_id TEXT NOT NULL, sku TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0),
      app_order_id INTEGER NOT NULL, created_at INTEGER NOT NULL,
      PRIMARY KEY(mode, order_id))`);
    sql.exec('CREATE INDEX IF NOT EXISTS payment_orders_owner ON payment_orders(mode, user_id, sku)');
    sql.exec('CREATE TABLE IF NOT EXISTS payment_migrations (name TEXT PRIMARY KEY)');
    if ([...sql.exec("SELECT name FROM payment_migrations WHERE name = 'kv_orders_v1'")].length) return;
    const orders = [];
    let startAfter;
    while (true) {
      const batch = await this.storage.list({prefix:'orders:test:',limit:1000,...(startAfter ? {startAfter} : {})});
      for (const [key,p] of batch) {
        const order = key.slice('orders:test:'.length);
        if (!id(order) || !id(p.user) || p.sku !== 'stage_02' || !Number.isInteger(p.amount) || p.amount < 1 ||
            p.receipt?.order_id !== Number(order) || !Number.isSafeInteger(p.receipt?.app_order_id)) {
          throw new Error('Invalid legacy payment receipt');
        }
        orders.push({order,...p});
        startAfter = key;
      }
      if (batch.size < 1000) break;
    }
    this.storage.transactionSync(() => {
      for (const p of orders) sql.exec('INSERT OR IGNORE INTO payment_orders VALUES (?, ?, ?, ?, ?, ?, ?)',
        'test',p.order,p.user,p.sku,p.amount,p.receipt.app_order_id,p.created_at);
      sql.exec("INSERT INTO payment_migrations VALUES ('kv_orders_v1')");
    });
    // Retain old KV entries as a backup. They are never read for rights again.
  }
  async fetch(request) {
    try {
      await this.ready;
      const p = await request.json();
      if (p.mode !== 'test' || !id(p.user)) reject('Некорректный аккаунт.');
      const sql = this.storage.sql;
      if (new URL(request.url).pathname === '/rights') {
        return Response.json({skus:[...sql.exec('SELECT DISTINCT sku FROM payment_orders WHERE mode = ? AND user_id = ? ORDER BY sku',p.mode,p.user)].map(row=>row.sku)});
      }
      if (new URL(request.url).pathname !== '/grant' || !id(p.order) || p.sku !== 'stage_02' || !Number.isInteger(p.amount) || p.amount < 1) reject('Некорректный заказ.');
      const receipt = this.storage.transactionSync(() => {
        const previous = [...sql.exec('SELECT * FROM payment_orders WHERE mode = ? AND order_id = ?',p.mode,p.order)][0];
        if (previous) {
          if (previous.user_id !== p.user || previous.sku !== p.sku || previous.amount !== p.amount) reject('Конфликт заказа.');
          return {order_id:Number(previous.order_id),app_order_id:previous.app_order_id};
        }
        if (p.amount !== p.expected_price) reject('Некорректная стоимость.');
        sql.exec('INSERT INTO payment_orders VALUES (?, ?, ?, ?, ?, ?, ?)',p.mode,p.order,p.user,p.sku,p.amount,Number(p.order),Date.now());
        return {order_id:Number(p.order),app_order_id:Number(p.order)};
      });
      return Response.json(receipt);
    } catch (error) {
      if (error instanceof PaymentError) return Response.json({error:error.message,code:error.code},{status:409});
      return Response.json({error:'Хранилище покупок временно недоступно.',code:1},{status:503});
    }
  }
}
