import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL =
  process.env.APTOS_NODE_URL ||
  'https://aptos.testnet.porto.movementlabs.xyz/v1';
const MODULE_ADDRESS = process.env.PROMPT_MARKETPLACE_MODULE_ADDRESS;

if (!MODULE_ADDRESS) {
  throw new Error(
    'Please set PROMPT_MARKETPLACE_MODULE_ADDRESS in the .env file'
  );
}

const main = async () => {
  const client = new AptosClient(NODE_URL);

  // Function to get all collections with details
  async function getCollectionsWithDetails() {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_collections_with_details`,
        type_arguments: [],
        arguments: [],
      };

      const response = await client.view(payload);
      const collectionIds = response[0] as unknown as string[];
      const uris = response[1] as unknown as string[];

      return collectionIds.map((id: string, index: number) => ({
        id: id,
        uri: uris[index],
      }));
    } catch (error) {
      console.error('Error getting collections:', error);
      throw error;
    }
  }

  try {
    console.log('\nFetching all collections...');
    console.log('------------------------');

    const collections = await getCollectionsWithDetails();

    if (collections.length === 0) {
      console.log('No collections found.');
    } else {
      collections.forEach((collection) => {
        console.log(`Collection ID: ${collection.id}`);
        console.log(`URI: ${collection.uri}`);
        console.log('------------------------');
      });
      console.log(`Total collections: ${collections.length}`);
    }
  } catch (error) {
    console.error('\nError:', error);
  }
};

main().catch(console.error);
