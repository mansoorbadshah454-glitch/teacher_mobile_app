const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccount = JSON.parse(fs.readFileSync('.firebase/school-v5-firebase-adminsdk.json', 'utf8'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function main() {
  const db = admin.firestore();
  const snapshot = await db.collection('global_users').where('role', 'in', ['parent', 'Parent']).limit(1).get();
  if (snapshot.empty) {
    console.log("No parents found");
  } else {
    snapshot.forEach(doc => {
      console.log(doc.id, "=>", doc.data());
    });
  }
}

main().catch(console.error);
