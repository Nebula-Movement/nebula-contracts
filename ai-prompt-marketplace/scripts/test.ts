fetch('https://indexer.testnet.porto.movementnetwork.xyz/v1/graphql', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: `
        query {
          account_transactions(limit: 10) {
            id
            block_height
            # ...
          }
        }
      `,
  }),
})
  .then((res) => res.json())
  .then((data) => console.log('GraphQL response:', data))
  .catch((err) => console.error('Error:', err));
