/**
 * Migration script to create connection_codes entries for existing families
 * Run this once to migrate old families to the new connection_codes structure
 */

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize Firebase Admin
const app = initializeApp();
const db = getFirestore(app);

async function migrateConnectionCodes() {
  console.log('🔄 Starting connection codes migration...');
  
  try {
    // Get all families
    const familiesSnapshot = await db.collection('families').get();
    console.log(`📊 Found ${familiesSnapshot.docs.length} families to check`);
    
    let migrated = 0;
    let skipped = 0;
    
    for (const familyDoc of familiesSnapshot.docs) {
      const familyData = familyDoc.data();
      const familyId = familyDoc.id;
      const connectionCode = familyData.connectionCode;
      
      if (!connectionCode) {
        console.log(`⚠️  Family ${familyId} has no connectionCode, skipping`);
        skipped++;
        continue;
      }
      
      // Check if connection code entry already exists
      const existingCodeQuery = await db.collection('connection_codes')
        .where('code', '==', connectionCode)
        .where('familyId', '==', familyId)
        .limit(1)
        .get();
      
      if (!existingCodeQuery.empty) {
        console.log(`✅ Connection code ${connectionCode} already exists for family ${familyId}`);
        skipped++;
        continue;
      }
      
      // Create connection code entry
      const connectionCodeData = {
        code: connectionCode,
        familyId: familyId,
        isActive: familyData.isActive ?? true,
        createdAt: familyData.createdAt || new Date(),
        createdBy: familyData.createdBy || 'migration',
        elderlyName: familyData.elderlyName || 'Unknown',
      };
      
      await db.collection('connection_codes').add(connectionCodeData);
      
      console.log(`✅ Created connection code entry: ${connectionCode} -> ${familyId}`);
      migrated++;
    }
    
    console.log(`🎉 Migration complete! Migrated: ${migrated}, Skipped: ${skipped}`);
    
  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  }
}

// Run migration if called directly
if (require.main === module) {
  migrateConnectionCodes()
    .then(() => {
      console.log('Migration completed successfully');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Migration failed:', error);
      process.exit(1);
    });
}

module.exports = { migrateConnectionCodes };