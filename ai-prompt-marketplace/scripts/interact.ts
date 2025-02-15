import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
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
      console.log('All Collections:', response[0]);
      return response[0] as number[];
    } catch (error) {
      console.error('Error getting collections:', error);
      throw error;
    }
  }

  // Example: Create a collection
  async function createCollection() {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::create_collection`,
        type_arguments: [],
        arguments: [
          'My Collection test', // name
          'A collection of amazing prompts', // description
          'https://example.com/collection', // uri
          '1000000', // max_supply (1M prompts)
          '100000000', // creation_fee_per_prompt (1 MOVE = 100000000 octas)
          '5', // public_creation_limit_per_addr
        ],
      };

      const txnRequest = await client.generateTransaction(
        account.address(),
        payload
      );
      const signedTxn = await client.signTransaction(account, txnRequest);
      const txnResult = await client.submitTransaction(signedTxn);

      console.log('Collection creation submitted!');
      console.log('Transaction hash:', txnResult.hash);

      // Wait for transaction
      const txnInfo = await client.waitForTransactionWithResult(txnResult.hash);

      // Get collection ID from the updated registry
      const collections = await getAllCollections();
      const newCollectionId = collections[collections.length - 1];
      console.log('Collection created successfully!');
      console.log('Collection ID:', newCollectionId);

      return {
        txHash: txnResult.hash,
        collectionId: newCollectionId,
      };
    } catch (error) {
      console.error('Error creating collection:', error);
      throw error;
    }
  }

  // Example: View collection info
  async function viewCollectionInfo(collectionId: number) {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_collection_info`,
        type_arguments: [],
        arguments: [collectionId],
      };

      const response = await client.view(payload);
      const [name, description, uri, totalSupply, maxSupply, creationFee] =
        response;
      console.log('Collection Info:');
      console.log('Name:', name);
      console.log('Description:', description);
      console.log('URI:', uri);
      console.log('Total Supply:', totalSupply);
      console.log('Max Supply:', maxSupply);
      console.log('Creation Fee:', creationFee);
      return response;
    } catch (error) {
      console.error('Error viewing collection:', error);
      throw error;
    }
  }

  async function getCreationCount(collectionId: number, userAddress: string) {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_mint_count`,
        type_arguments: [],
        arguments: [collectionId, userAddress],
      };

      const response = await client.view(payload);
      console.log('Creation count for user:', response[0]);
      return Number(response[0]);
    } catch (error) {
      console.error('Error getting creation count:', error);
      throw error;
    }
  }

  // async function createPrompt(collectionId: number) {
  //   try {
  //     const payload = {
  //       function: `${MODULE_ADDRESS}::prompt_marketplace::mint_prompt`,
  //       type_arguments: [],
  //       arguments: [collectionId],
  //     };

  //     const txnRequest = await client.generateTransaction(
  //       account.address(),
  //       payload
  //     );
  //     const signedTxn = await client.signTransaction(account, txnRequest);
  //     const txnResult = await client.submitTransaction(signedTxn);
  //     await client.waitForTransaction(txnResult.hash);

  //     console.log('Prompt created successfully!');
  //     console.log('Transaction hash:', txnResult.hash);
  //     return txnResult.hash;
  //   } catch (error) {
  //     console.error('Error creating prompt:', error);
  //     throw error;
  //   }
  // }

  try {
    console.log('\nCreating collection...');
    const { txHash, collectionId } = await createCollection();
    console.log('Created collection with transaction:', txHash);
    console.log('Collection ID:', collectionId);

    console.log('\nGetting collection info...');
    await viewCollectionInfo(collectionId);

    console.log('\nGetting creation count...');
    await getCreationCount(collectionId, account.address().hex());

    console.log('\nListing all collections...');
    const allCollections = await getAllCollections();
    console.log('All collection IDs:', allCollections);

    // Uncomment to create a prompt
    // console.log('\nCreating prompt...');
    // await createPrompt(collectionId);
  } catch (error) {
    console.error('Error:', error);
  }
};

main().catch(console.error);
