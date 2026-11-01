import { MongoClient, Db } from "mongodb";

const globalForMongo = globalThis as unknown as {
  mongoClient?: MongoClient;
  mongoConnection?: Promise<MongoClient>;
};

export async function getMongoDb(): Promise<Db> {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not configured");

  if (!globalForMongo.mongoClient) globalForMongo.mongoClient = new MongoClient(uri);
  if (!globalForMongo.mongoConnection) {
    globalForMongo.mongoConnection = globalForMongo.mongoClient.connect().catch((error) => {
      globalForMongo.mongoConnection = undefined;
      throw error;
    });
  }
  await globalForMongo.mongoConnection;
  return globalForMongo.mongoClient.db(process.env.MONGODB_DB ?? "mediconnect");
}
