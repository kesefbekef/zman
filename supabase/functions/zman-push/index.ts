// זמן בכיף — "השליח": רץ כל דקה (pg_cron), שולח לטלפונים את ההתראות שהגיע זמנן.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import webpush from 'npm:web-push@3.6.7';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
webpush.setVapidDetails(Deno.env.get('ZMAN_VAPID_SUBJECT')!, Deno.env.get('ZMAN_VAPID_PUBLIC')!, Deno.env.get('ZMAN_VAPID_PRIVATE')!);

Deno.serve(async req => {
  if (req.headers.get('x-cron-secret') !== Deno.env.get('ZMAN_CRON_SECRET')) return new Response('no', { status: 401 });
  const now = new Date();
  const { data: due, error } = await sb.from('zman_notify').select('*').is('sent_at', null)
    .lte('at', now.toISOString()).gte('at', new Date(now.getTime() - 2 * 3600e3).toISOString()).order('at').limit(200);
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0, gone = 0;
  const subsCache = new Map<string, any[]>();
  for (const n of due ?? []) {
    let subs = subsCache.get(n.to_uid);
    if (!subs) { subs = (await sb.from('zman_push_subs').select('*').eq('user_id', n.to_uid)).data ?? []; subsCache.set(n.to_uid, subs); }
    const payload = JSON.stringify({ title: n.title, body: n.body ?? '', url: n.url ?? './', tag: n.id, cat: n.cat });
    for (const s of subs) {
      if (s.prefs?.[n.cat] === false) continue; // המשתמש ביקש לא לקבל את סוג ההתראה הזה
      try { await webpush.sendNotification(s.sub, payload, { TTL: 3600, urgency: n.cat === 'msg' ? 'high' : 'normal' }); sent++; }
      catch (e: any) {
        if (e?.statusCode === 404 || e?.statusCode === 410) { await sb.from('zman_push_subs').delete().eq('endpoint', s.endpoint); gone++; }
        else console.warn('push', e?.statusCode, e?.body);
      }
    }
    await sb.from('zman_notify').update({ sent_at: now.toISOString() }).eq('id', n.id);
  }
  // ניקיון: התראות ישנות
  await sb.from('zman_notify').delete().lt('at', new Date(now.getTime() - 7 * 864e5).toISOString());
  return new Response(JSON.stringify({ due: due?.length ?? 0, sent, gone }), { headers: { 'Content-Type': 'application/json' } });
});
