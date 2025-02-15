import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL =
  process.env.APTOS_NODE_URL ||
  'https://aptos.testnet.porto.movementlabs.xyz/v1';
const MODULE_ADDRESS = process.env.PROMPT_MARKETPLACE_MODULE_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!MODULE_ADDRESS) {
  throw new Error(
    'Please set PROMPT_MARKETPLACE_MODULE_ADDRESS in the .env file'
  );
}

if (!PRIVATE_KEY) {
  throw new Error('Please set PRIVATE_KEY in the .env file');
}

const main = async () => {
  const client = new AptosClient(NODE_URL);
  const account = new AptosAccount(
    HexString.ensure(PRIVATE_KEY).toUint8Array()
  );

  console.log(`Using account: ${account.address().hex()}`);

  // Function to get collection info
  async function getCollectionInfo(collectionId: string) {
    try {
      const payload = {
        function: `${MODULE_ADDRESS}::prompt_marketplace::get_collection_info`,
        type_arguments: [],
        arguments: [collectionId],
      };

      const response = await client.view(payload);
      const [name, description, uri, totalSupply, maxSupply, mintFee] =
        response;
      return {
        name,
        description,
        uri,
        totalSupply,
        maxSupply,
        mintFee: Number(mintFee),
      };
    } catch (error) {
      console.error('Error getting collection info:', error);
      throw error;
    }
  }

  async function mintPrompt(collectionId: string) {
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

      console.log('\nMinting prompt...');
      console.log('Transaction hash:', txnResult.hash);

      // Wait for transaction
      await client.waitForTransaction(txnResult.hash);
      console.log('Prompt minted successfully!');

      return txnResult.hash;
    } catch (error) {
      console.error('Error minting prompt:', error);
      throw error;
    }
  }

  async function getBalance(address: string): Promise<number> {
    try {
      const resource = await client.getAccountResource(
        address,
        '0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>'
      );
      const balance = (resource.data as any).coin.value;
      return Number(balance) / 100000000; // Convert from octas to MOVE
    } catch (error) {
      console.error('Error getting balance:', error);
      throw error;
    }
  }

  try {
    const collectionId = process.argv[2];
    if (!collectionId) {
      console.log('\nUsage: npm run create -- <collection_id>');
      console.log('Example: npm run create -- 1');
      return;
    }

    console.log(`\nGetting info for collection ${collectionId}...`);
    const collectionInfo = await getCollectionInfo(collectionId);
    console.log('\nCollection Info:');
    console.log('Name:', collectionInfo.name);
    console.log('Creation Fee:', collectionInfo.mintFee / 100000000, 'MOVE'); // Convert from octas to MOVE

    // Check balance before minting
    const balanceBefore = await getBalance(account.address().hex());
    console.log('\nYour balance before minting:', balanceBefore, 'MOVE');

    // Check if user has enough balance
    if (balanceBefore < collectionInfo.mintFee / 100000000) {
      console.log('\nError: Insufficient balance to mint prompt');
      return;
    }

    // Mint prompt
    const txHash = await mintPrompt(collectionId);

    // Check balance after minting
    const balanceAfter = await getBalance(account.address().hex());
    console.log('\nYour balance after minting:', balanceAfter, 'MOVE');
    console.log('Cost of minting:', balanceBefore - balanceAfter, 'MOVE');
  } catch (error) {
    console.error('\nError:', error);
  }
};

main().catch(console.error);
