import { AptosClient, AptosAccount, HexString, Types } from 'aptos';
import dotenv from 'dotenv';

dotenv.config();

const NODE_URL =
  process.env.APTOS_NODE_URL ||
  'https://aptos.testnet.porto.movementlabs.xyz/v1';
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!PRIVATE_KEY) {
  throw new Error('Please set your PRIVATE_KEY in the .env file');
}

const main = async () => {
  const client = new AptosClient(NODE_URL);
  const account = new AptosAccount(
    HexString.ensure(PRIVATE_KEY).toUint8Array()
  );
  console.log(`Using sender address: ${account.address().hex()}`);

  async function transferMoveTokens(recipientAddress: string, amount: string) {
    try {
      // Convert amount to octas (1 MOVE = 100000000 octas)
      const amountInOctas = (Number(amount) * 100000000).toString();

      const payload = {
        function: '0x1::aptos_account::transfer',
        type_arguments: ['0x1::aptos_coin::AptosCoin'],
        arguments: [recipientAddress, amountInOctas],
      };

      const txnRequest = await client.generateTransaction(
        account.address(),
        payload
      );
      const signedTxn = await client.signTransaction(account, txnRequest);
      const txnResult = await client.submitTransaction(signedTxn);

      console.log('\nTransfer submitted...');
      console.log('Transaction hash:', txnResult.hash);

      await client.waitForTransaction(txnResult.hash);
      console.log('Transfer completed successfully!');

      return txnResult.hash;
    } catch (error) {
      console.error('Error transferring tokens:', error);
      throw error;
    }
  }

  async function getBalance(address: string) {
    try {
      const resource = await client.getAccountResource(
        address,
        '0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>'
      );
      const balance = (resource.data as any).coin.value;
      return Number(balance) / 100000000;
    } catch (error) {
      console.error('Error getting balance:', error);
      throw error;
    }
  }

  try {
    const recipientAddress = process.argv[2];
    const amount = process.argv[3];

    if (!recipientAddress || !amount) {
      console.log(
        '\nUsage: npm run transfer -- <recipient_address> <amount_in_move>'
      );
      console.log('Example: npm run transfer -- 0x123...abc 10.5');
      return;
    }

    const senderBalance = await getBalance(account.address().hex());
    console.log(`\nSender's balance: ${senderBalance} MOVE`);

    const recipientBalanceBefore = await getBalance(recipientAddress);
    console.log(`Recipient's balance before: ${recipientBalanceBefore} MOVE`);

    console.log(`\nTransferring ${amount} MOVE to ${recipientAddress}...`);
    await transferMoveTokens(recipientAddress, amount);

    const senderBalanceAfter = await getBalance(account.address().hex());
    const recipientBalanceAfter = await getBalance(recipientAddress);

    console.log('\nTransfer complete!');
    console.log(`Sender's new balance: ${senderBalanceAfter} MOVE`);
    console.log(`Recipient's new balance: ${recipientBalanceAfter} MOVE`);
  } catch (error) {
    console.error('\nError:', error);
  }
};

main().catch(console.error);
