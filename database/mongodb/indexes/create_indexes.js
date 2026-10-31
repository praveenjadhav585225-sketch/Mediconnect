// create_indexes.js : unique, text and multikey indexes. Safe to re-run (createIndex is idempotent).
// Run:  mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/indexes/create_indexes.js
const dbm = db.getSiblingDB('mediconnect');

// case_details
dbm.case_details.createIndex({ case_id: 1 }, { unique: true, name: 'uq_case_id' });
dbm.case_details.createIndex({ narrative: 'text', anonymised_summary: 'text' },
                             { name: 'txt_narrative_summary', default_language: 'english', weights: { anonymised_summary: 3, narrative: 1 } });
dbm.case_details.createIndex({ 'symptoms.name': 1 }, { name: 'mk_symptom_name' });       // multikey (array field)
dbm.case_details.createIndex({ created_at: -1 }, { name: 'ix_created_desc' });

// consultation_notes
dbm.consultation_notes.createIndex({ consultation_id: 1 }, { unique: true, name: 'uq_consultation_id' });
dbm.consultation_notes.createIndex({ specialization: 1, updated_at: -1 }, { name: 'ix_spec_updated' });

// notifications: "my unread notifications, newest first"
dbm.notifications.createIndex({ user_id: 1, is_read: 1, created_at: -1 }, { name: 'ix_user_unread_recent' });

for (const c of ['case_details', 'consultation_notes', 'notifications']) {
  print(c + ': ' + dbm.getCollection(c).getIndexes().map(i => i.name).join(', '));
}
