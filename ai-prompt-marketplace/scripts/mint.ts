import { AptosClient, AptosAccount, HexString } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL =
  process.env.APTOS_NODE_URL ||
  'https://aptos.testnet.porto.movementlabs.xyz/v1';
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const MODULE_ADDRESS = process.env.PROMPT_MARKETPLACE_MODULE_ADDRESS;

if (!PRIVATE_KEY) {
  throw new Error('Please set your PRIVATE_KEY in the .env file');
}

if (!MODULE_ADDRESS) {
  throw new Error(
    'Please set PROMPT_MARKETPLACE_MODULE_ADDRESS in the .env file'
  );
}

const main = async () => {
  const client = new AptosClient(NODE_URL);
  const account = new AptosAccount(
    HexString.ensure(PRIVATE_KEY).toUint8Array()
  );
  console.log(`Using account address: ${account.address().hex()}`);

  // Get all collections
  async function getAllCollections() {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_collections`,
        type_arguments: [],
        arguments: [],
      };

      const response = await client.view(payload);
      return response[0] as number[];
    } catch (error) {
      console.error('Error getting collections:', error);
      throw error;
    }
  }

  // First check collection info
  async function viewCollectionInfo(collectionId: number) {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_collection_info`,
        type_arguments: [],
        arguments: [collectionId],
      };

      const response = await client.view(payload);
      const [name, description, uri, totalSupply, maxSupply, mintFee] =
        response;
      console.log('\nCollection Info:');
      console.log('Collection ID:', collectionId);
      console.log('Name:', name);
      console.log('Description:', description);
      console.log('URI:', uri);
      console.log('Total Supply:', totalSupply);
      console.log('Max Supply:', maxSupply);
      console.log('Creation Fee:', mintFee, 'MOVE');
      return response;
    } catch (error) {
      console.error('Error viewing collection:', error);
      throw error;
    }
  }

  // Check mint count for the user
  async function getMintCount(collectionId: number, userAddress: string) {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_mint_count`,
        type_arguments: [],
        arguments: [collectionId, userAddress],
      };

      const response = await client.view(payload);
      console.log('\nYour creation count:', response[0]);
      return Number(response[0]);
    } catch (error) {
      console.error('Error getting creation count:', error);
      throw error;
    }
  }

  // Create prompt
  async function createPrompt(collectionId: number) {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::mint_prompt`,
        type_arguments: [],
        arguments: [collectionId],
      };

      const txnRequest = await client.generateTransaction(
        account.address(),
        payload
      );
      const signedTxn = await client.signTransaction(account, txnRequest);
      const txnResult = await client.submitTransaction(signedTxn);

      console.log('\nCreating prompt...');
      console.log('Transaction hash:', txnResult.hash);

      await client.waitForTransaction(txnResult.hash);
      console.log('Prompt created successfully!');

      return txnResult.hash;
    } catch (error) {
      console.error('Error creating prompt:', error);
      throw error;
    }
  }

  try {
    console.log('\nFetching available collections...');
    const collections = await getAllCollections();

    if (!collections || collections.length === 0) {
      console.log('No collections available to create prompts from.');
      return;
    }

    console.log(`\nFound ${collections.length} collections:`);

    for (const collectionId of collections) {
      await viewCollectionInfo(collectionId);
    }

    // For this test, we'll use the first collection
    // We would want to accept collection ID as a argument
    const selectedCollectionId = collections[0];
    console.log(`\nSelected collection ID: ${selectedCollectionId}`);

    const userAddress = account.address().hex();
    const currentMintCount = await getMintCount(
      selectedCollectionId,
      userAddress
    );

    console.log('\nProceeding with prompt creation...');
    const txHash = await createPrompt(selectedCollectionId);

    console.log('\nChecking updated creation count...');
    await getMintCount(selectedCollectionId, userAddress);
  } catch (error) {
    console.error('\nError:', error);
  }
};

main().catch(console.error);
