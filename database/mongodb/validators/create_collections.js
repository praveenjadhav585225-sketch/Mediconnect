// create_collections.js : creates the 3 collections with $jsonSchema validation (database-level validation).
// Run:  mongosh "mongodb://localhost:27017/mediconnect" database/mongodb/validators/create_collections.js
// Safe to re-run: existing collections get their validator updated with collMod.

const UUID_RE = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

const schemas = {
  // Free-text clinical details of a case. The ONLY place the narrative is stored.
  case_details: {
    bsonType: 'object',
    title: 'Case details',
    required: ['case_id', 'narrative', 'symptoms', 'anonymised_summary', 'created_at'],
    additionalProperties: false,
    properties: {
      _id: {},
      case_id: { bsonType: 'string', pattern: UUID_RE, description: 'medical_cases.case_id in PostgreSQL' },
      narrative: { bsonType: 'string', minLength: 20, maxLength: 5000 },
      symptoms: {
        bsonType: 'array', minItems: 1, maxItems: 30,
        items: {
          bsonType: 'object', required: ['name', 'onset_days', 'intensity'], additionalProperties: false,
          properties: {
            name: { bsonType: 'string', minLength: 2, maxLength: 100 },
            onset_days: { bsonType: 'number', minimum: 0, maximum: 3650 },
            intensity: { bsonType: 'number', minimum: 1, maximum: 10 }
          }
        }
      },
      vitals: {
        bsonType: 'object', additionalProperties: false,
        properties: {
          temperature_c: { bsonType: 'number', minimum: 30, maximum: 45 },
          heart_rate: { bsonType: 'number', minimum: 20, maximum: 250 },
          bp_systolic: { bsonType: 'number', minimum: 50, maximum: 260 },
          bp_diastolic: { bsonType: 'number', minimum: 30, maximum: 160 },
          spo2: { bsonType: 'number', minimum: 50, maximum: 100 }
        }
      },
      medical_history_flags: { bsonType: 'array', items: { bsonType: 'string', maxLength: 60 } },
      attachments: {
        bsonType: 'array', maxItems: 10,
        items: { bsonType: 'object', required: ['filename'], properties: {
          filename: { bsonType: 'string', maxLength: 200 }, type: { bsonType: 'string' }, size_bytes: { bsonType: 'number', minimum: 0 } } }
      },
      anonymised_summary: { bsonType: 'string', minLength: 10, maxLength: 500 },
      created_at: { bsonType: 'date' },
      updated_at: { bsonType: 'date' }
    }
  },

  // Doctor-written notes. Shape varies by specialization, which is why this is a document store.
  consultation_notes: {
    bsonType: 'object',
    title: 'Consultation notes',
    required: ['consultation_id', 'specialization', 'observations', 'updated_at'],
    additionalProperties: false,
    properties: {
      _id: {},
      consultation_id: { bsonType: 'string', pattern: UUID_RE },
      specialization: { bsonType: 'string', minLength: 3, maxLength: 80 },
      observations: { bsonType: 'string', minLength: 1, maxLength: 5000 },
      assessment_by_doctor: { bsonType: 'string', maxLength: 5000 },
      advice_by_doctor: { bsonType: 'string', maxLength: 5000 },
      custom_fields: { bsonType: 'object' },
      updated_at: { bsonType: 'date' }
    }
  },

  notifications: {
    bsonType: 'object',
    title: 'In-app notifications',
    required: ['user_id', 'type', 'message', 'is_read', 'created_at'],
    additionalProperties: false,
    properties: {
      _id: {},
      user_id: { bsonType: 'string', pattern: UUID_RE },
      type: { enum: ['APPOINTMENT_BOOKED', 'APPOINTMENT_CONFIRMED', 'APPOINTMENT_CANCELLED', 'CASE_SUBMITTED',
                     'CONSULTATION_COMPLETED', 'DOCTOR_VERIFIED', 'DOCTOR_REJECTED', 'REVIEW_RECEIVED'] },
      message: { bsonType: 'string', minLength: 1, maxLength: 500 },
      related_id: { bsonType: 'string' },
      is_read: { bsonType: 'bool' },
      created_at: { bsonType: 'date' }
    }
  }
};

if (typeof db !== 'undefined') {
  const dbm = db.getSiblingDB('mediconnect');
  const existing = dbm.getCollectionNames();
  for (const [name, schema] of Object.entries(schemas)) {
    const opts = { validator: { $jsonSchema: schema }, validationLevel: 'strict', validationAction: 'error' };
    if (existing.includes(name)) {
      dbm.runCommand({ collMod: name, ...opts });
      print('updated validator : ' + name);
    } else {
      dbm.createCollection(name, opts);
      print('created collection: ' + name);
    }
  }
}
