// pipelines.js : MongoDB aggregation demos (advanced feature #7).
// Run:  mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/aggregations/pipelines.js
const dbm = db.getSiblingDB('mediconnect');

print('\n--- A1: most common symptoms with average intensity ($unwind, $group, $sort, $limit) ---');
printjson(dbm.case_details.aggregate([
  { $unwind: '$symptoms' },
  { $group: { _id: '$symptoms.name', cases: { $sum: 1 }, avg_intensity: { $avg: '$symptoms.intensity' } } },
  { $project: { _id: 0, symptom: '$_id', cases: 1, avg_intensity: { $round: ['$avg_intensity', 2] } } },
  { $sort: { cases: -1, symptom: 1 } },
  { $limit: 8 }
]).toArray());

print('\n--- A2: monthly case volume ($dateToString) ---');
printjson(dbm.case_details.aggregate([
  { $group: { _id: { $dateToString: { format: '%Y-%m', date: '$created_at' } }, cases: { $sum: 1 } } },
  { $sort: { _id: -1 } }, { $limit: 6 }
]).toArray());

print('\n--- A3: average vitals per number of reported symptoms ($size, $group) ---');
printjson(dbm.case_details.aggregate([
  { $group: { _id: { $size: '$symptoms' }, cases: { $sum: 1 },
              avg_heart_rate: { $avg: '$vitals.heart_rate' }, avg_spo2: { $avg: '$vitals.spo2' } } },
  { $project: { _id: 0, symptoms_reported: '$_id', cases: 1,
                avg_heart_rate: { $round: ['$avg_heart_rate', 1] }, avg_spo2: { $round: ['$avg_spo2', 1] } } },
  { $sort: { symptoms_reported: 1 } }
]).toArray());

print('\n--- A4: unread notifications by type ($match, $group) ---');
printjson(dbm.notifications.aggregate([
  { $match: { is_read: false } },
  { $group: { _id: '$type', unread: { $sum: 1 } } },
  { $sort: { unread: -1 } }
]).toArray());

print('\n--- A5: consultations per specialization with average duration ($group, $avg) ---');
printjson(dbm.consultation_notes.aggregate([
  { $group: { _id: '$specialization', notes: { $sum: 1 }, avg_minutes: { $avg: '$custom_fields.duration_minutes' } } },
  { $project: { _id: 0, specialization: '$_id', notes: 1, avg_minutes: { $round: ['$avg_minutes', 1] } } },
  { $sort: { notes: -1 } }
]).toArray());

print('\n--- A6: full-text search on the text index, ranked ($text, textScore) ---');
printjson(dbm.case_details.find(
  { $text: { $search: 'wheezing night cough' } },
  { _id: 0, case_id: 1, anonymised_summary: 1, score: { $meta: 'textScore' } }
).sort({ score: { $meta: 'textScore' } }).limit(3).toArray());
