module prompt_marketplace::prompt_marketplace {
    use std::option::{Self, Option};
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::account;

    // NFT Resource Structs
    struct PromptNFT has key, store {
        id: u64,
        collection_id: u64,  // Reference to collection ID
        collection_name: String,
        description: String,
        uri: String,
        creator: address,
        owner: address
    }

    struct Collection has key {
        id: u64,  // Unique collection ID
        name: String,
        description: String,
        uri: String,
        total_supply: u64,
        max_supply: u64,
        mint_fee_per_nft: u64,
        creator_addr: address,
        public_mint_limit_per_addr: u64,
        paused: bool  // New field for emergency pause
    }

    struct MintTracker has key {
        collection_id: u64,  // Reference to collection ID
        mints_per_addr: vector<address>,  // Track mints per address
    }

    struct Registry has key {
        collections: vector<u64>,  // Store collection IDs
        next_collection_id: u64,  // Counter for generating unique collection IDs
        collection_addr_map: vector<CollectionAddrMap>  // Map collection IDs to addresses
    }

    struct CollectionAddrMap has store {
        collection_id: u64,
        addr: address
    }

    struct Config has key {
        admin_addr: address,
        pending_admin_addr: Option<address>,
    }

    struct CollectionStats has key {
        collection_id: u64,
        total_volume: u64,
        num_holders: u64,
        floor_price: Option<u64>,
        last_mint_time: u64
    }

    struct CollectionEvents has key {
        mint_events: event::EventHandle<NFTMintedEvent>,
        batch_mint_events: event::EventHandle<BatchNFTMintedEvent>,
        pause_events: event::EventHandle<CollectionPausedEvent>
    }

    #[event]
    struct NFTMintedEvent has drop, store {
        collection_id: u64,
        token_id: u64,
        recipient: address,
        mint_price: u64,
        timestamp: u64
    }

    #[event]
    struct BatchNFTMintedEvent has drop, store {
        collection_id: u64,
        start_token_id: u64,
        end_token_id: u64,
        recipient: address,
        total_mint_price: u64,
        timestamp: u64
    }

    #[event]
    struct CollectionPausedEvent has drop, store {
        collection_id: u64,
        paused: bool,
        timestamp: u64
    }

    // Error constants
    const EONLY_ADMIN: u64 = 1;
    const ENOT_PENDING_ADMIN: u64 = 2;
    const EMINT_LIMIT_EXCEEDED: u64 = 3;
    const EMAX_SUPPLY_REACHED: u64 = 4;
    const ECOLLECTION_NOT_FOUND: u64 = 5;
    const ECOLLECTION_PAUSED: u64 = 6;
    const EBATCH_MINT_TOO_LARGE: u64 = 7;
    const EBATCH_MINT_EXCEEDS_SUPPLY: u64 = 8;

    const MAX_BATCH_MINT_SIZE: u64 = 50;

    fun init_module(sender: &signer) {
        move_to(sender, Registry {
            collections: vector::empty(),
            next_collection_id: 1,
            collection_addr_map: vector::empty()
        });
        move_to(sender, Config {
            admin_addr: signer::address_of(sender),
            pending_admin_addr: option::none(),
        });
    }

    public entry fun create_collection(
        sender: &signer,
        name: String,
        description: String,
        uri: String,
        max_supply: u64,
        mint_fee_per_nft: u64,
        public_mint_limit_per_addr: u64
    ) acquires Registry {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<Registry>(@prompt_marketplace);
        
        let collection_id = registry.next_collection_id;
        registry.next_collection_id = collection_id + 1;
        
        move_to(sender, Collection {
            id: collection_id,
            name,
            description,
            uri,
            total_supply: 0,
            max_supply,
            mint_fee_per_nft,
            creator_addr: sender_addr,
            public_mint_limit_per_addr,
            paused: false
        });

        // Initialize mint tracker
        move_to(sender, MintTracker {
            collection_id,
            mints_per_addr: vector::empty(),
        });

        move_to(sender, CollectionStats {
            collection_id,
            total_volume: 0,
            num_holders: 0,
            floor_price: option::none(),
            last_mint_time: timestamp::now_seconds()
        });

        move_to(sender, CollectionEvents {
            mint_events: account::new_event_handle<NFTMintedEvent>(sender),
            batch_mint_events: account::new_event_handle<BatchNFTMintedEvent>(sender),
            pause_events: account::new_event_handle<CollectionPausedEvent>(sender)
        });

        vector::push_back(&mut registry.collections, collection_id);
        vector::push_back(&mut registry.collection_addr_map, CollectionAddrMap {
            collection_id,
            addr: sender_addr
        });
    }

    public entry fun mint_nft(
        sender: &signer,
        collection_id: u64,
    ) acquires Collection, MintTracker, Registry, CollectionStats, CollectionEvents {
        let sender_addr = signer::address_of(sender);
        
        // Get collection address from registry
        let collection_addr = get_collection_addr(collection_id);
        assert!(collection_addr != @0x0, ECOLLECTION_NOT_FOUND);

        let collection = borrow_global_mut<Collection>(collection_addr);
        assert!(!collection.paused, ECOLLECTION_PAUSED);

        let mint_tracker = borrow_global_mut<MintTracker>(collection_addr);

        // Validate minting conditions
        assert!(collection.total_supply < collection.max_supply, EMAX_SUPPLY_REACHED);
        
        // Check mint limit
        let user_mint_count = count_user_mints(&mint_tracker.mints_per_addr, sender_addr);
        assert!(user_mint_count < collection.public_mint_limit_per_addr, EMINT_LIMIT_EXCEEDED);

        // Handle payment
        if (collection.mint_fee_per_nft > 0) {
            coin::transfer<AptosCoin>(sender, collection.creator_addr, collection.mint_fee_per_nft);
        };

        // Create NFT
        let nft = PromptNFT {
            id: collection.total_supply + 1,
            collection_id: collection.id,
            collection_name: collection.name,
            description: collection.description,
            uri: collection.uri,
            creator: collection_addr,
            owner: sender_addr
        };

        // Update state
        collection.total_supply = collection.total_supply + 1;
        vector::push_back(&mut mint_tracker.mints_per_addr, sender_addr);
        move_to(sender, nft);

        // Update collection stats
        let stats = borrow_global_mut<CollectionStats>(collection_addr);
        stats.total_volume = stats.total_volume + collection.mint_fee_per_nft;
        stats.last_mint_time = timestamp::now_seconds();
        if (collection.total_supply == 0) {
            stats.num_holders = stats.num_holders + 1;
        };

        // Emit mint event
        let events = borrow_global_mut<CollectionEvents>(collection_addr);
        event::emit_event(&mut events.mint_events, NFTMintedEvent {
            collection_id,
            token_id: collection.total_supply + 1,
            recipient: sender_addr,
            mint_price: collection.mint_fee_per_nft,
            timestamp: timestamp::now_seconds()
        });
    }

    // Helper function to get collection address from ID
    fun get_collection_addr(collection_id: u64): address acquires Registry {
        let registry = borrow_global<Registry>(@prompt_marketplace);
        let i = 0;
        let len = vector::length(&registry.collection_addr_map);
        while (i < len) {
            let map = vector::borrow(&registry.collection_addr_map, i);
            if (map.collection_id == collection_id) {
                return map.addr
            };
            i = i + 1;
        };
        @0x0
    }

    // View functions
    #[view]
    public fun get_collection_info(collection_id: u64): (String, String, String, u64, u64, u64) acquires Collection, Registry {
        let collection_addr = get_collection_addr(collection_id);
        assert!(collection_addr != @0x0, ECOLLECTION_NOT_FOUND);
        
        let collection = borrow_global<Collection>(collection_addr);
        (
            collection.name,
            collection.description,
            collection.uri,
            collection.total_supply,
            collection.max_supply,
            collection.mint_fee_per_nft
        )
    }

    #[view]
    public fun get_mint_count(collection_id: u64, user_addr: address): u64 acquires MintTracker, Registry {
        let collection_addr = get_collection_addr(collection_id);
        assert!(collection_addr != @0x0, ECOLLECTION_NOT_FOUND);
        
        let mint_tracker = borrow_global<MintTracker>(collection_addr);
        count_user_mints(&mint_tracker.mints_per_addr, user_addr)
    }

    #[view]
    public fun get_collections(): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(@prompt_marketplace);
        *&registry.collections
    }

    // Helper function to count user mints
    fun count_user_mints(mints: &vector<address>, user: address): u64 {
        let count = 0;
        let i = 0;
        let len = vector::length(mints);
        while (i < len) {
            if (*vector::borrow(mints, i) == user) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    // Batch mint
    public entry fun batch_mint(
        sender: &signer,
        collection_id: u64,
        amount: u64
    ) acquires Collection, MintTracker, Registry, CollectionStats, CollectionEvents {
        assert!(amount > 0 && amount <= MAX_BATCH_MINT_SIZE, EBATCH_MINT_TOO_LARGE);
        
        let collection_addr = get_collection_addr(collection_id);
        assert!(collection_addr != @0x0, ECOLLECTION_NOT_FOUND);
        
        let collection = borrow_global<Collection>(collection_addr);
        assert!(!collection.paused, ECOLLECTION_PAUSED);
        assert!(collection.total_supply + amount <= collection.max_supply, EBATCH_MINT_EXCEEDS_SUPPLY);

        let start_token_id = collection.total_supply + 1;
        let total_mint_price = collection.mint_fee_per_nft * amount;

        let i = 0;
        while (i < amount) {
            mint_nft(sender, collection_id);
            i = i + 1;
        };

        // Emit batch mint event
        let events = borrow_global_mut<CollectionEvents>(collection_addr);
        event::emit_event(&mut events.batch_mint_events, BatchNFTMintedEvent {
            collection_id,
            start_token_id,
            end_token_id: start_token_id + amount - 1,
            recipient: signer::address_of(sender),
            total_mint_price,
            timestamp: timestamp::now_seconds()
        });
    }

    // Emergency pause function
    public entry fun toggle_collection_pause(
        sender: &signer,
        collection_id: u64
    ) acquires Collection, Registry, Config, CollectionEvents {
        let config = borrow_global<Config>(@prompt_marketplace);
        assert!(signer::address_of(sender) == config.admin_addr, EONLY_ADMIN);

        let collection_addr = get_collection_addr(collection_id);
        assert!(collection_addr != @0x0, ECOLLECTION_NOT_FOUND);

        let collection = borrow_global_mut<Collection>(collection_addr);
        collection.paused = !collection.paused;

        // Emit pause event
        let events = borrow_global_mut<CollectionEvents>(collection_addr);
        event::emit_event(&mut events.pause_events, CollectionPausedEvent {
            collection_id,
            paused: collection.paused,
            timestamp: timestamp::now_seconds()
        });
    }
}
