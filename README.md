The **AI Prompt Marketplace Module** is a smart contract on the **Movement blockchain** that enables users to create, mint, and manage AI prompt NFTs. It facilitates a decentralized marketplace where creators can monetize their AI-generated prompts by minting them as NFTs and selling them to others.

## Workflow

1. **Initialization**
   - The contract is deployed and initialized by setting up necessary resources.
   - An admin is appointed to manage administrative tasks.

2. **Creating a Prompt Collection**
   - A creator calls `create_collection` with parameters:
     - **Description**: Text describing the collection.
     - **Name**: The name of the collection.
     - **URI**: Metadata URI for the collection stored off-chain via IPFS.
     - **Max Supply**: Total number of NFTs that can be minted in the collection.
     - **Mint Fee**: Optional number of NFTs to pre-mint upon creation.
     - **Public Mint Settings**: Mint limit per address, and mint fee per NFT.
   - A collection is created, and pre-minted NFTs are minted if specified.
   - Relevant Events are Emitted

3. **Minting Prompts**
   - Users call `mint_prompt` to mint NFTs from a collection.
     - Must not exceed the mint limit per address.
   - Payment amount is deducted and transferred to the creator.
   - NFTs are minted and transferred to the user's address.
