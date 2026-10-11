const $ = (selector) => document.querySelector(selector);
const pad = (n) => String(n).padStart(2, '0');
const toISO = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const fromISO = (value) => { const [y, m, d] = value.split('-').map(Number); return new Date(y, m - 1, d); };
const today = toISO(new Date());
const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const defaults = [
  { name: 'Barbell bench press', muscle: 'Chest', sets: 3, reps: 8, weight: 40 },
  { name: 'Incline dumbbell press', muscle: 'Chest', sets: 3, reps: 10, weight: 16 },
  { name: 'Shoulder press', muscle: 'Shoulders', sets: 3, reps: 8, weight: 20 },
];
let db;
try { db = JSON.parse(localStorage.getItem('repday-v1')) || { days: {}, templates: {}, templateUpdatedAt: {} }; }
catch { db = { days: {}, templates: {}, templateUpdatedAt: {} }; }
db.days ||= {}; db.templates ||= {}; db.templateUpdatedAt ||= {};
let selected = today, weekOffset = 0, chartExercise = '';

function save(sync = true) {
  const now = Date.now(); db.updatedAt = now;
  if (db.days[selected]) { db.days[selected].updatedAt = now; delete db.days[selected].completedAt; $('#completeDay').textContent = 'Complete this day'; }
  localStorage.setItem('repday-v1', JSON.stringify(db));
  if (sync) window.RepdayDrive?.queue(db);
}
function nameOfDay(date) { return weekdayNames[date.getDay()]; }
function dayData(date = selected) {
  if (!db.days[date]) {
    const weekday = nameOfDay(fromISO(date));
    const prescription = db.templates[weekday] || (weekday === 'Monday' ? defaults : []);
    db.days[date] = { updatedAt: Date.now(), exercises: prescription.map((item) => {
      const lastEntry = historyFor(item.name).filter((entry) => entry.date < date).at(-1);
      return {
        id: crypto.randomUUID(), name: item.name, muscle: item.muscle,
        videoUrl: item.videoUrl || lastEntry?.exercise.videoUrl || '',
        photo: item.photo || lastEntry?.exercise.photo || '', note: '',
        sets: Array.from({ length: Math.max(3, Number(item.sets) || 3) }, () => ({ reps: '', weight: '', done: false })),
      };
    }) };
    save();
  }
  return db.days[date];
}
function syncTemplate() {
  const weekday = nameOfDay(fromISO(selected));
  db.templates[weekday] = dayData().exercises.map((exercise) => ({
    name: exercise.name, muscle: exercise.muscle, sets: exercise.sets.length,
    reps: exercise.sets.at(-1)?.reps || 8, weight: exercise.sets.at(-1)?.weight || 0,
    videoUrl: exercise.videoUrl || '', photo: exercise.photo || '',
  }));
  db.templateUpdatedAt[weekday] = Date.now();
}
function imageData(file) {
  return new Promise((resolve, reject) => {
    if (!file?.type.startsWith('image/')) return reject(new Error('Choose an image file.'));
    const img = new Image(), url = URL.createObjectURL(file);
    img.onload = () => {
      const scale = Math.min(1, 360 / Math.max(img.width, img.height));
      const canvas = document.createElement('canvas'); canvas.width = Math.max(1, Math.round(img.width * scale)); canvas.height = Math.max(1, Math.round(img.height * scale));
      canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height); URL.revokeObjectURL(url);
      resolve(canvas.toDataURL('image/jpeg', 0.72));
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Could not read image.')); }; img.src = url;
  });
}
function weekStart() { const date = fromISO(today); date.setDate(date.getDate() - ((date.getDay() + 6) % 7) + weekOffset * 7); return date; }
function drawWeek() {
  const start = weekStart(), end = new Date(start); end.setDate(end.getDate() + 6);
  $('#monthLabel').textContent = start.toLocaleDateString('en', { month: 'long', year: 'numeric' });
  $('#weekLabel').textContent = `${start.toLocaleDateString('en', { month: 'short', day: 'numeric' })} — ${end.toLocaleDateString('en', { month: 'short', day: 'numeric' })}`;
  const holder = $('#week'); holder.replaceChildren();
  for (let i = 0; i < 7; i++) {
    const date = new Date(start); date.setDate(date.getDate() + i); const key = toISO(date);
    const button = document.createElement('button'); button.className = `day-card${key === selected ? ' selected' : ''}`;
    button.innerHTML = `<span class="dow">${nameOfDay(date).slice(0, 3)}</span><span class="date">${date.getDate()}</span>${db.days[key]?.exercises?.length ? '<i class="mark"></i>' : ''}`;
    button.onclick = () => { selected = key; render(); }; holder.append(button);
  }
}
function historyFor(name) {
  return Object.entries(db.days).flatMap(([date, day]) => day.exercises.filter((ex) => ex.name.toLowerCase() === name.toLowerCase()).map((exercise) => ({ date, exercise }))).sort((a, b) => a.date.localeCompare(b.date));
}
function safeVideo(url) { try { const parsed = new URL(url); return ['https:', 'http:'].includes(parsed.protocol) ? parsed.href : ''; } catch { return ''; } }
function render() {
  drawWeek(); const date = fromISO(selected), data = dayData();
  $('#greeting').textContent = selected === today ? 'Your training log' : nameOfDay(date);
  $('#workoutTitle').textContent = nameOfDay(date);
  $('#workoutSub').textContent = date.toLocaleDateString('en', { month: 'long', day: 'numeric', year: 'numeric' });
  $('#formDay').textContent = nameOfDay(date);
  $('#completeDay').textContent = data.completedAt ? 'Completed · sync again' : 'Complete this day';
  const list = $('#exerciseList'); list.replaceChildren();
  if (!data.exercises.length) { list.innerHTML = '<div class="empty"><b>A fresh page.</b>Add an exercise to start this day’s workout.</div>'; }
  data.exercises.forEach((exercise, index) => {
    const previous = historyFor(exercise.name).filter((entry) => entry.date < selected);
    const last = previous.at(-1);
    const top = exercise.sets.reduce((best, set) => Number(set.weight) * Number(set.reps) > Number(best.weight) * Number(best.reps) ? set : best, exercise.sets[0]);
    const score = (Number(top.weight) || 0) * (Number(top.reps) || 0);
    const record = Math.max(0, ...previous.flatMap((entry) => entry.exercise.sets.map((set) => (Number(set.weight) || 0) * (Number(set.reps) || 0))));
    const card = document.createElement('article'); card.className = 'exercise';
    card.innerHTML = `<div class="exercise-head"><span class="exercise-num">${String(index + 1).padStart(2, '0')}</span><div class="ex-info"><div class="ex-title"><b class="ex-name"></b><span class="photo-empty">＋</span><img class="photo-round" alt="Exercise reference" hidden></div><div class="ex-muscle"></div></div><span class="last-line"></span><span class="badge">${score > record && score > 0 ? '↑ NEW BEST' : `${score} PTS`}</span><button type="button" class="dots" aria-label="Collapse sets">···</button></div>
      <div class="sets-wrap"><div class="set-head"><span>SET</span><span>REPS</span><span>WEIGHT</span><span>DONE</span><span></span></div><div class="set-list"></div></div>
      <div class="exercise-foot"><button type="button" class="text-action add-set">＋ Add set</button><input class="note-input" maxlength="120" placeholder="One-line note for this exercise…"><small class="previous-note" hidden></small><label class="photo-pick"><span class="photo-pick-text">＋ Add photo</span><input class="photo-input" type="file" accept="image/*"></label><button type="button" class="text-action remove-ex">Remove</button><div class="video-line"><input class="video-input" type="url" placeholder="Video or how-to link…"><a class="video-link" target="_blank" rel="noopener noreferrer" hidden>Watch guide ↗</a></div></div>`;
    card.querySelector('.ex-name').textContent = exercise.name; card.querySelector('.ex-muscle').textContent = exercise.muscle;
    const thumb = card.querySelector('.photo-round'), emptyPhoto = card.querySelector('.photo-empty');
    if (exercise.photo) { thumb.src = exercise.photo; thumb.hidden = false; emptyPhoto.hidden = true; }
    card.querySelector('.photo-pick-text').textContent = exercise.photo ? 'Change photo' : '＋ Add photo';
    card.querySelector('.last-line').textContent = last ? `LAST ${fromISO(last.date).toLocaleDateString('en', { month: 'short', day: 'numeric' })} · ${Math.max(...last.exercise.sets.map((s) => Number(s.weight) || 0))} KG` : 'FIRST SESSION';
    const note = card.querySelector('.note-input'); note.value = exercise.note || ''; note.oninput = () => { exercise.note = note.value; save(); };
    const previousNote = card.querySelector('.previous-note');
    if (last?.exercise.note) { previousNote.hidden = false; previousNote.textContent = `PREVIOUS NOTE · ${fromISO(last.date).toLocaleDateString('en', { month: 'short', day: 'numeric' })}: ${last.exercise.note}`; }
    const videoInput = card.querySelector('.video-input'), videoLink = card.querySelector('.video-link'); videoInput.value = exercise.videoUrl || '';
    const updateVideoLink = () => { const href = safeVideo(videoInput.value.trim()); videoLink.hidden = !href; if (href) videoLink.href = href; };
    videoInput.oninput = () => { exercise.videoUrl = videoInput.value.trim(); syncTemplate(); save(); updateVideoLink(); }; updateVideoLink();
    card.querySelector('.photo-input').onchange = async (event) => { try { const file = event.target.files[0]; if (!file) return; exercise.photo = await imageData(file); syncTemplate(); save(); render(); toast('Photo saved'); } catch { toast('Choose a valid image'); } };
    const rows = card.querySelector('.set-list');
    exercise.sets.forEach((set, setIndex) => {
      const row = document.createElement('div'); row.className = `set-row${set.done ? ' completed' : ''}`;
      const previousSet = last?.exercise.sets?.[setIndex];
      const removeSet = setIndex >= 3 ? '<button type="button" class="remove-set" aria-label="Remove set">×</button>' : '<span class="remove-set-placeholder" aria-hidden="true"></span>';
      row.innerHTML = `<span class="set-number">SET ${String(setIndex + 1).padStart(2, '0')}<small class="previous-set"></small></span><label class="numeric"><input type="number" min="0" step="1" aria-label="Set ${setIndex + 1} reps"><i class="unit">reps</i></label><label class="numeric"><input type="number" min="0" step="0.5" aria-label="Set ${setIndex + 1} weight"><i class="unit">kg</i></label><label class="done-cell" aria-label="Mark set ${setIndex + 1} complete"><input type="checkbox" ${set.done ? 'checked' : ''}><span></span></label>${removeSet}`;
      const numbers = row.querySelectorAll('input[type=number]'); numbers[0].value = set.reps; numbers[1].value = set.weight;
      numbers[0].placeholder = previousSet?.reps ?? '';
      numbers[1].placeholder = previousSet?.weight ?? '';
      row.querySelector('.previous-set').textContent = previousSet ? `PREV ${previousSet.reps || '—'} × ${previousSet.weight || '—'} kg` : '';
      numbers[0].oninput = () => { set.reps = numbers[0].value; syncTemplate(); save(); };
      numbers[1].oninput = () => { set.weight = numbers[1].value; syncTemplate(); save(); drawChart(); };
      row.querySelector('input[type=checkbox]').onchange = (event) => { set.done = event.target.checked; row.classList.toggle('completed', set.done); save(); };
      row.querySelector('.remove-set')?.addEventListener('click', () => { exercise.sets.splice(setIndex, 1); syncTemplate(); save(); render(); });
      rows.append(row);
    });
    card.querySelector('.add-set').onclick = () => { exercise.sets.push({ reps: '', weight: '', done: false }); syncTemplate(); save(); render(); };
    card.querySelector('.remove-ex').onclick = () => { if (!confirm(`Remove ${exercise.name} from this day?`)) return; data.exercises.splice(index, 1); syncTemplate(); save(); render(); };
    card.querySelector('.dots').onclick = () => { card.querySelector('.sets-wrap').hidden = !card.querySelector('.sets-wrap').hidden; };
    list.append(card);
  });
  updateStats(); drawChart();
}
function allExercises() { return [...new Set(Object.values(db.days).flatMap((day) => day.exercises.map((ex) => ex.name)))].sort(); }
function updateStats() {
  const days = Object.values(db.days), all = days.flatMap((day) => day.exercises), sets = all.flatMap((ex) => ex.sets);
  $('#sessions').textContent = days.filter((day) => day.exercises.length).length; $('#totalSets').textContent = sets.length;
  const best = sets.map((set) => Number(set.weight) || 0).sort((a, b) => b - a)[0]; $('#bestLift').textContent = best ? `${best} kg` : '—';
}
function drawChart() {
  const names = allExercises(), select = $('#chartExercise');
  if (!chartExercise || !names.includes(chartExercise)) chartExercise = names[0] || '';
  select.replaceChildren(); names.forEach((name) => { const option = document.createElement('option'); option.value = name; option.textContent = name; select.append(option); });
  if (!names.length) { const option = document.createElement('option'); option.textContent = 'No exercises yet'; select.append(option); }
  select.value = chartExercise; select.onchange = () => { chartExercise = select.value; drawChart(); };
  const history = chartExercise ? historyFor(chartExercise).map((entry) => ({ date: entry.date, weight: Math.max(...entry.exercise.sets.map((set) => Number(set.weight) || 0)) })).filter((point) => point.weight > 0) : [];
  const box = $('#chart'); if (!history.length) { box.innerHTML = '<div class="empty">Log weights to see exercise progress here.</div>'; return; }
  const W = 720, H = 170, left = 35, right = 12, top = 14, bottom = 16;
  const min = Math.min(...history.map((point) => point.weight)), max = Math.max(...history.map((point) => point.weight)), spread = Math.max(5, max - min), low = Math.max(0, min - spread * .25), high = max + spread * .25;
  const x = (i) => left + (history.length === 1 ? (W - left - right) / 2 : i * (W - left - right) / (history.length - 1));
  const y = (value) => top + (high - value) / (high - low) * (H - top - bottom);
  const path = history.map((point, i) => `${i ? 'L' : 'M'} ${x(i)} ${y(point.weight)}`).join(' ');
  const grid = [0, 1, 2].map((i) => { const value = low + (high - low) * i / 2, yy = y(value); return `<line x1="${left}" y1="${yy}" x2="${W}" y2="${yy}" stroke="#eff0eb"/><text x="0" y="${yy + 3}" fill="#a0a39a" font-size="9">${value.toFixed(value % 1 ? 1 : 0)}</text>`; }).join('');
  const dots = history.map((point, i) => `<circle cx="${x(i)}" cy="${y(point.weight)}" r="4" fill="white" stroke="#879f43" stroke-width="2"><title>${point.date}: ${point.weight} kg</title></circle>`).join('');
  box.innerHTML = `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${grid}<path d="${path}" fill="none" stroke="#879f43" stroke-width="2.5" stroke-linecap="round"/>${dots}</svg>`;
}
let toastTimer;
function toast(message) { const node = $('#toast'); node.textContent = message; node.classList.add('show'); clearTimeout(toastTimer); toastTimer = setTimeout(() => node.classList.remove('show'), 1900); }
$('#prevWeek').onclick = () => { weekOffset--; const date = fromISO(selected); date.setDate(date.getDate() - 7); selected = toISO(date); render(); };
$('#nextWeek').onclick = () => { weekOffset++; const date = fromISO(selected); date.setDate(date.getDate() + 7); selected = toISO(date); render(); };
$('#toggleForm').onclick = () => { const form = $('#exerciseForm'); form.hidden = !form.hidden; $('#formDay').textContent = nameOfDay(fromISO(selected)); if (!form.hidden) $('#nameInput').focus(); };
$('#completeDay').onclick = async () => {
  const day = dayData(), timestamp = Date.now();
  day.completedAt = timestamp; day.updatedAt = timestamp; db.updatedAt = timestamp;
  localStorage.setItem('repday-v1', JSON.stringify(db));
  const button = $('#completeDay'); button.disabled = true; button.textContent = 'Saving to Drive…';
  const synced = await window.RepdayDrive?.syncNow();
  button.disabled = false;
  if (synced) { toast('Day completed and saved to Drive'); render(); }
  else { button.textContent = 'Retry Drive save'; toast('Day saved here; Drive update failed'); }
};
$('#exerciseForm').onsubmit = async (event) => {
  event.preventDefault(); const name = $('#nameInput').value.trim(); if (!name) return;
  let photo = ''; try { if ($('#photoInput').files[0]) photo = await imageData($('#photoInput').files[0]); } catch { return toast('Choose a valid image'); }
  const previous = historyFor(name).filter((entry) => entry.date < selected).at(-1);
  const videoUrl = $('#videoInput').value.trim() || previous?.exercise.videoUrl || '';
  photo ||= previous?.exercise.photo || '';
  const count = Math.max(3, Math.min(20, Number($('#setsInput').value) || 3)), reps = Math.max(1, Number($('#repsInput').value) || 8), weight = Math.max(0, Number($('#weightInput').value) || 0);
  dayData().exercises.push({ id: crypto.randomUUID(), name, muscle: $('#muscleInput').value, videoUrl, photo, note: '', sets: Array.from({ length: count }, () => ({ reps, weight, done: false })) });
  syncTemplate(); save(); event.target.reset(); $('#setsInput').value = 3; $('#repsInput').value = 8; $('#weightInput').value = 0; event.target.hidden = true; render(); toast('Exercise added');
};
$('#driveConnect').onclick = () => window.RepdayDrive?.connect();
$('#exportData').onclick = () => {
  const blob = new Blob([JSON.stringify(db, null, 2)], { type: 'application/json' });
  const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'repday-workout-backup.json'; link.click(); URL.revokeObjectURL(link.href);
};
$('#importData').onchange = async (event) => {
  try {
    const imported = JSON.parse(await event.target.files[0].text());
    if (!imported || typeof imported.days !== 'object' || !imported.days) throw new Error('Invalid backup');
    const dates = new Set([...Object.keys(db.days), ...Object.keys(imported.days)]);
    for (const date of dates) {
      const local = db.days[date], incoming = imported.days[date];
      if (!local || (Number(incoming?.updatedAt) || 0) > (Number(local.updatedAt) || 0)) db.days[date] = incoming;
    }
    for (const weekday of Object.keys(imported.templates || {})) {
      if ((Number(imported.templateUpdatedAt?.[weekday]) || 0) > (Number(db.templateUpdatedAt?.[weekday]) || 0)) {
        db.templates[weekday] = imported.templates[weekday]; db.templateUpdatedAt[weekday] = imported.templateUpdatedAt[weekday];
      } else if (!db.templates[weekday]) db.templates[weekday] = imported.templates[weekday];
    }
    save(); render(); toast('Backup imported and saved');
  } catch { toast('That backup file could not be imported'); }
  event.target.value = '';
};
window.addEventListener('repday:data-loaded', (event) => { db = event.detail; localStorage.setItem('repday-v1', JSON.stringify(db)); render(); });
window.addEventListener('repday:toast', (event) => toast(event.detail));
if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('./service-worker.js').catch(() => {});
if (window.RepdayDrive?.ready) window.RepdayDrive.ready.then(render).catch(render); else render();
