import { supabase } from './supabaseClient.js';

export async function listInitiatives() {
  const { data, error } = await supabase
    .from('initiatives')
    .select('*, tasks(*)')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function saveInitiative(initiative) {
  const payload = {
    legacy_id: initiative.legacy_id ?? null,
    type: initiative.type ?? 'PROJETO',
    name: initiative.name,
    summary: initiative.summary ?? '',
    owner_name: initiative.owner ?? null,
    priority: initiative.priority ?? 'Média',
    start_date: initiative.start || null,
    end_date: initiative.end || null,
    status: initiative.status ?? 'AGUARDANDO',
    progress: initiative.progress ?? 0,
    auto_progress: initiative.autoProgress ?? false,
    completed_at: initiative.completedAt || null,
    work_weekends: initiative.workWeekends ?? false,
    show_in_daily: initiative.showInDaily ?? false,
    comment: initiative.comment ?? ''
  };

  const query = initiative.dbId
    ? supabase.from('initiatives').update(payload).eq('id', initiative.dbId)
    : supabase.from('initiatives').insert(payload);

  const { data, error } = await query.select().single();
  if (error) throw error;
  return data;
}

export async function getDaily(date) {
  const { data, error } = await supabase
    .from('daily_meetings')
    .select('*')
    .eq('meeting_date', date)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function saveDaily(date, fields) {
  const payload = {
    meeting_date: date,
    daily_lead: fields.dailyLead ?? '',
    daily_people: fields.dailyPeople ?? '',
    daily_done: fields.dailyDone ?? '',
    daily_priorities: fields.dailyPriorities ?? '',
    daily_tickets: fields.dailyTickets ?? '',
    daily_projects: fields.dailyProjects ?? '',
    daily_blockers: fields.dailyBlockers ?? '',
    daily_decisions: fields.dailyDecisions ?? ''
  };

  const { data, error } = await supabase
    .from('daily_meetings')
    .upsert(payload, { onConflict: 'meeting_date' })
    .select()
    .single();
  if (error) throw error;
  return data;
}
