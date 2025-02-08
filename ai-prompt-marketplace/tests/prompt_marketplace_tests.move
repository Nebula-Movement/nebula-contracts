#[test_only]
module prompt_marketplace::prompt_marketplace_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use prompt_marketplace::prompt_marketplace;

    #[test(creator = @0x123, buyer = @0x456)]
    fun test_create_and_mint_nft(
        creator: &signer,
        buyer: &signer,
    ) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(creator);
        
        // Create test accounts
        let creator_addr = signer::address_of(creator);
        let buyer_addr = signer::address_of(buyer);
        account::create_account_for_test(creator_addr);
        account::create_account_for_test(buyer_addr);

        // Initialize module
        prompt_marketplace::init_module(creator);

        // Test collection creation
        prompt_marketplace::create_collection(
            creator,
            string::utf8(b"Test Collection"),
            string::utf8(b"Test Description"),
            string::utf8(b"https://test.uri"),
            10, // max_supply
            1000000, // mint_fee_per_nft (1 APT)
            0, // public_mint_start_time
            timestamp::now_seconds() + 86400, // public_mint_end_time (24 hours from now)
            5 // public_mint_limit_per_addr
        );

        // Get collection info
        let (name, description, uri, total_supply, max_supply, mint_fee) = 
            prompt_marketplace::get_collection_info(creator_addr);
        
        assert!(string::utf8(b"Test Collection") == name, 0);
        assert!(total_supply == 0, 1);
        assert!(max_supply == 10, 2);
        assert!(mint_fee == 1000000, 3);

        // Test mint count
        let mint_count = prompt_marketplace::get_mint_count(creator_addr, buyer_addr);
        assert!(mint_count == 0, 4);
    }

    #[test(admin = @prompt_marketplace)]
    #[expected_failure(abort_code = 1)] // EONLY_ADMIN
    fun test_unauthorized_init(admin: &signer) {
        account::create_account_for_test(signer::address_of(admin));
        prompt_marketplace::init_module(admin);
    }
} 