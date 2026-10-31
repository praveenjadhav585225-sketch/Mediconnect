// mongo_tests.js : validator and index tests. Test documents are removed at the end.
// Run:  mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/tests/mongo_tests.js
const dbm = db.getSiblingDB('mediconnect');
const results = [];
const TEST_CASE = 'aaaaaaaa-0000-4000-8000-000000000001';
const good = () => ({
  case_id: TEST_CASE, narrative: 'For about five days I have had a dry cough and mild wheezing at night.',
  symptoms: [{ name: 'dry cough', onset_days: 5, intensity: 4 }],
  vitals: { heart_rate: 80, spo2: 97 }, anonymised_summary: 'Adult presenting with dry cough for about 5 days.',
  created_at: new Date()
});
function check(id, desc, fn, expectFail, expectCode) {
  let outcome, code = null;
  try { fn(); outcome = 'accepted'; }
  catch (e) { outcome = 'rejected'; code = e.code || (e.errorResponse && e.errorResponse.code) || null; }
  const ok = expectFail ? (outcome === 'rejected' && (!expectCode || code === expectCode)) : outcome === 'accepted';
  results.push({ id, desc, expected: expectFail ? 'rejected' + (expectCode ? ' (' + expectCode + ')' : '') : 'accepted', got: outcome + (code ? ' (' + code + ')' : ''), result: ok ? 'PASS' : 'FAIL' });
}
dbm.case_details.deleteMany({ case_id: TEST_CASE });

check('M01', 'Valid case_details document accepted', () => dbm.case_details.insertOne(good()), false);
check('M02', 'Duplicate case_id rejected (unique index)', () => dbm.case_details.insertOne(good()), true, 11000);
dbm.case_details.deleteMany({ case_id: TEST_CASE });
check('M03', 'Missing required field (narrative) rejected', () => { const d = good(); delete d.narrative; dbm.case_details.insertOne(d); }, true, 121);
check('M04', 'Too-short narrative rejected', () => { const d = good(); d.narrative = 'too short'; dbm.case_details.insertOne(d); }, true, 121);
check('M05', 'Intensity 11 rejected (maximum 10)', () => { const d = good(); d.symptoms[0].intensity = 11; dbm.case_details.insertOne(d); }, true, 121);
check('M06', 'Malformed case_id (not a UUID) rejected', () => { const d = good(); d.case_id = 'case-1'; dbm.case_details.insertOne(d); }, true, 121);
check('M07', 'Empty symptoms array rejected (minItems 1)', () => { const d = good(); d.symptoms = []; dbm.case_details.insertOne(d); }, true, 121);
check('M08', 'Unknown extra field rejected (additionalProperties false)', () => { const d = good(); d.patient_name = 'X'; dbm.case_details.insertOne(d); }, true, 121);
check('M09', 'Impossible vital (spo2 150) rejected', () => { const d = good(); d.vitals.spo2 = 150; dbm.case_details.insertOne(d); }, true, 121);
check('M10', 'created_at as string rejected (must be date)', () => { const d = good(); d.created_at = '2026-01-01'; dbm.case_details.insertOne(d); }, true, 121);
check('M11', 'Notification with unknown type rejected (enum)', () => dbm.notifications.insertOne({ user_id: TEST_CASE, type: 'SPAM', message: 'x', is_read: false, created_at: new Date() }), true, 121);
check('M12', 'Valid notification accepted', () => dbm.notifications.insertOne({ user_id: TEST_CASE, type: 'CASE_SUBMITTED', message: 'test', is_read: false, created_at: new Date() }), false);
check('M13', 'Duplicate consultation_id note rejected (unique index)', () => {
  const n = { consultation_id: TEST_CASE, specialization: 'Cardiology', observations: 'test', updated_at: new Date() };
  dbm.consultation_notes.insertOne(n); dbm.consultation_notes.insertOne({ ...n }); }, true, 11000);

const idx = (c) => dbm.getCollection(c).getIndexes().map(i => i.name);
check('M14', 'Unique, text and multikey indexes on case_details exist', () => {
  const names = idx('case_details');
  for (const n of ['uq_case_id', 'txt_narrative_summary', 'mk_symptom_name']) if (!names.includes(n)) throw new Error('missing ' + n);
}, false);
check('M15', 'Notification compound index exists', () => { if (!idx('notifications').includes('ix_user_unread_recent')) throw new Error('missing'); }, false);
check('M16', 'Aggregation pipeline returns rows', () => {
  const r = dbm.case_details.aggregate([{ $unwind: '$symptoms' }, { $group: { _id: '$symptoms.name', n: { $sum: 1 } } }]).toArray();
  if (!r.length) throw new Error('empty'); }, false);
check('M17', 'Text search returns results', () => {
  if (!dbm.case_details.find({ $text: { $search: 'cough' } }).limit(1).toArray().length) throw new Error('empty'); }, false);

dbm.case_details.deleteMany({ case_id: TEST_CASE });
dbm.consultation_notes.deleteMany({ consultation_id: TEST_CASE });
dbm.notifications.deleteMany({ user_id: TEST_CASE });
console.table(results);
const failed = results.filter(r => r.result === 'FAIL').length;
print('passed: ' + (results.length - failed) + '  failed: ' + failed + '  total: ' + results.length);
