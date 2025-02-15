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
    use aptos_std::table::{Self, Table};

    // Prompt Resource Structs
    struct Prompt has store {
        id: u64,
        collection_id: u64,  // Reference to collection ID
        collection_name: String,
        description: String,
        uri: String,
        creator: address,
        owner: address
    }

    // Store to store user's Prompts
    struct UserPromptStore has key {
        prompts: vector<Prompt>
    }

    struct Collection has key, store {
        id: u64,  // Unique collection ID
        name: String,
        description: String,
        uri: String,
        total_supply: u64,
        max_supply: u64,
        mint_fee_per_prompt: u64,
        creator_addr: address,
        public_mint_limit_per_addr: u64,
        paused: bool 
    }

    struct MintTracker has key, store {
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

    struct CollectionStats has key, store {
        collection_id: u64,
        total_volume: u64,
        num_holders: u64,
        floor_price: Option<u64>,
        last_mint_time: u64
    }

    struct CollectionEvents has key, store {
        mint_events: event::EventHandle<PromptMintedEvent>,
        batch_mint_events: event::EventHandle<BatchPromptMintedEvent>,
        pause_events: event::EventHandle<CollectionPausedEvent>
    }

    struct CollectionStore has key {
        collections: Table<u64, Collection>,
        mint_trackers: Table<u64, MintTracker>,
        collection_stats: Table<u64, CollectionStats>,
        collection_events: Table<u64, CollectionEvents>
    }

    #[event]
    struct PromptMintedEvent has drop, store {
        collection_id: u64,
        prompt_id: u64,
        recipient: address,
        mint_price: u64,
        timestamp: u64
    }

    #[event]
    struct BatchPromptMintedEvent has drop, store {
        collection_id: u64,
        start_prompt_id: u64,
        end_prompt_id: u64,
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
        move_to(sender, CollectionStore {
            collections: table::new(),
            mint_trackers: table::new(),
            collection_stats: table::new(),
            collection_events: table::new()
        });
    }

    public entry fun create_collection(
        sender: &signer,
        name: String,
        description: String,
        uri: String,
        max_supply: u64,
        mint_fee_per_prompt: u64,
        public_mint_limit_per_addr: u64
    ) acquires Registry, CollectionStore {
        let sender_addr = signer::address_of(sender);
        let registry = borrow_global_mut<Registry>(@prompt_marketplace);
        let store = borrow_global_mut<CollectionStore>(@prompt_marketplace);
        
        let collection_id = registry.next_collection_id;
        registry.next_collection_id = collection_id + 1;
        
        let collection = Collection {
            id: collection_id,
            name,
            description,
            uri,
            total_supply: 0,
            max_supply,
            mint_fee_per_prompt,
            creator_addr: sender_addr,
            public_mint_limit_per_addr,
            paused: false
        };

        let mint_tracker = MintTracker {
            collection_id,
            mints_per_addr: vector::empty(),
        };

        let collection_stats = CollectionStats {
            collection_id,
            total_volume: 0,
            num_holders: 0,
            floor_price: option::none(),
            last_mint_time: timestamp::now_seconds()
        };

        let collection_events = CollectionEvents {
            mint_events: account::new_event_handle<PromptMintedEvent>(sender),
            batch_mint_events: account::new_event_handle<BatchPromptMintedEvent>(sender),
            pause_events: account::new_event_handle<CollectionPausedEvent>(sender)
        };

        table::add(&mut store.collections, collection_id, collection);
        table::add(&mut store.mint_trackers, collection_id, mint_tracker);
        table::add(&mut store.collection_stats, collection_id, collection_stats);
        table::add(&mut store.collection_events, collection_id, collection_events);

        vector::push_back(&mut registry.collections, collection_id);
        vector::push_back(&mut registry.collection_addr_map, CollectionAddrMap {
            collection_id,
            addr: sender_addr
        });
    }

    public entry fun mint_prompt(
        sender: &signer,
        collection_id: u64,
    ) acquires CollectionStore, UserPromptStore {
        let sender_addr = signer::address_of(sender);
        let store = borrow_global_mut<CollectionStore>(@prompt_marketplace);
        
        // Get collection from store
        assert!(table::contains(&store.collections, collection_id), ECOLLECTION_NOT_FOUND);
        let collection = table::borrow_mut(&mut store.collections, collection_id);
        assert!(!collection.paused, ECOLLECTION_PAUSED);

        let mint_tracker = table::borrow_mut(&mut store.mint_trackers, collection_id);

        // Validate minting conditions
        assert!(collection.total_supply < collection.max_supply, EMAX_SUPPLY_REACHED);
        
        // Check mint limit
        let user_mint_count = count_user_mints(&mint_tracker.mints_per_addr, sender_addr);
        assert!(user_mint_count < collection.public_mint_limit_per_addr, EMINT_LIMIT_EXCEEDED);

        // Handle payment
        if (collection.mint_fee_per_prompt > 0) {
            coin::transfer<AptosCoin>(sender, collection.creator_addr, collection.mint_fee_per_prompt);
        };

        // Create Prompt
        let prompt = Prompt {
            id: collection.total_supply + 1,
            collection_id: collection.id,
            collection_name: collection.name,
            description: collection.description,
            uri: collection.uri,
            creator: collection.creator_addr,
            owner: sender_addr
        };

        // Update state
        collection.total_supply = collection.total_supply + 1;
        vector::push_back(&mut mint_tracker.mints_per_addr, sender_addr);

        // Initialize UserPromptStore if it doesn't exist
        if (!exists<UserPromptStore>(sender_addr)) {
            move_to(sender, UserPromptStore { prompts: vector::empty() });
        };

        // Add Prompt to user's store
        let user_store = borrow_global_mut<UserPromptStore>(sender_addr);
        vector::push_back(&mut user_store.prompts, prompt);

        // Update collection stats
        let stats = table::borrow_mut(&mut store.collection_stats, collection_id);
        stats.total_volume = stats.total_volume + collection.mint_fee_per_prompt;
        stats.last_mint_time = timestamp::now_seconds();
        if (collection.total_supply == 1) {
            stats.num_holders = stats.num_holders + 1;
        };

        // Emit mint event
        let events = table::borrow_mut(&mut store.collection_events, collection_id);
        event::emit_event(&mut events.mint_events, PromptMintedEvent {
            collection_id,
            prompt_id: collection.total_supply,
            recipient: sender_addr,
            mint_price: collection.mint_fee_per_prompt,
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
    public fun get_collection_info(collection_id: u64): (String, String, String, u64, u64, u64) acquires CollectionStore {
        let store = borrow_global<CollectionStore>(@prompt_marketplace);
        assert!(table::contains(&store.collections, collection_id), ECOLLECTION_NOT_FOUND);
        
        let collection = table::borrow(&store.collections, collection_id);
        (
            collection.name,
            collection.description,
            collection.uri,
            collection.total_supply,
            collection.max_supply,
            collection.mint_fee_per_prompt
        )
    }

    #[view]
    public fun get_mint_count(collection_id: u64, user_addr: address): u64 acquires CollectionStore {
        let store = borrow_global<CollectionStore>(@prompt_marketplace);
        assert!(table::contains(&store.mint_trackers, collection_id), ECOLLECTION_NOT_FOUND);
        
        let mint_tracker = table::borrow(&store.mint_trackers, collection_id);
        count_user_mints(&mint_tracker.mints_per_addr, user_addr)
    }

    #[view]
    public fun get_collections(): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(@prompt_marketplace);
        *&registry.collections
    }

    #[view]
    public fun get_collections_with_details(): (vector<u64>, vector<String>) 
        acquires Registry, CollectionStore {
        let registry = borrow_global<Registry>(@prompt_marketplace);
        let store = borrow_global<CollectionStore>(@prompt_marketplace);
        
        let collection_ids = *&registry.collections;
        let uris = vector::empty();
        
        let i = 0;
        let len = vector::length(&collection_ids);
        while (i < len) {
            let id = *vector::borrow(&collection_ids, i);
            let collection = table::borrow(&store.collections, id);
            vector::push_back(&mut uris, collection.uri);
            i = i + 1;
        };
        
        (collection_ids, uris)
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
    ) acquires CollectionStore, UserPromptStore {
        assert!(amount > 0 && amount <= MAX_BATCH_MINT_SIZE, EBATCH_MINT_TOO_LARGE);
        let sender_addr = signer::address_of(sender);
        
        let store = borrow_global_mut<CollectionStore>(@prompt_marketplace);
        assert!(table::contains(&store.collections, collection_id), ECOLLECTION_NOT_FOUND);
        
        let collection = table::borrow_mut(&mut store.collections, collection_id);
        assert!(!collection.paused, ECOLLECTION_PAUSED);
        assert!(collection.total_supply + amount <= collection.max_supply, EBATCH_MINT_EXCEEDS_SUPPLY);

        let mint_tracker = table::borrow_mut(&mut store.mint_trackers, collection_id);
        let user_mint_count = count_user_mints(&mint_tracker.mints_per_addr, sender_addr);
        assert!(user_mint_count + amount <= collection.public_mint_limit_per_addr, EMINT_LIMIT_EXCEEDED);

        let start_prompt_id = collection.total_supply + 1;
        let total_mint_price = collection.mint_fee_per_prompt * amount;

        // Handle payment for all Prompts at once
        if (collection.mint_fee_per_prompt > 0) {
            coin::transfer<AptosCoin>(sender, collection.creator_addr, total_mint_price);
        };

        // Initialize UserPromptStore if it doesn't exist
        if (!exists<UserPromptStore>(sender_addr)) {
            move_to(sender, UserPromptStore { prompts: vector::empty() });
        };
        let user_store = borrow_global_mut<UserPromptStore>(sender_addr);

        let i = 0;
        while (i < amount) {
            // Create Prompt
            let prompt = Prompt {
                id: collection.total_supply + 1,
                collection_id: collection.id,
                collection_name: collection.name,
                description: collection.description,
                uri: collection.uri,
                creator: collection.creator_addr,
                owner: sender_addr
            };

            // Update state
            collection.total_supply = collection.total_supply + 1;
            vector::push_back(&mut mint_tracker.mints_per_addr, sender_addr);
            vector::push_back(&mut user_store.prompts, prompt);
            i = i + 1;
        };

        // Update collection stats
        let stats = table::borrow_mut(&mut store.collection_stats, collection_id);
        stats.total_volume = stats.total_volume + total_mint_price;
        stats.last_mint_time = timestamp::now_seconds();
        if (collection.total_supply - amount == 0) {
            stats.num_holders = stats.num_holders + 1;
        };

        // Emit batch mint event
        let events = table::borrow_mut(&mut store.collection_events, collection_id);
        event::emit_event(&mut events.batch_mint_events, BatchPromptMintedEvent {
            collection_id,
            start_prompt_id,
            end_prompt_id: start_prompt_id + amount - 1,
            recipient: sender_addr,
            total_mint_price,
            timestamp: timestamp::now_seconds()
        });
    }

    // Emergency pause function
    public entry fun toggle_collection_pause(
        sender: &signer,
        collection_id: u64
    ) acquires CollectionStore, Config {
        let config = borrow_global<Config>(@prompt_marketplace);
        assert!(signer::address_of(sender) == config.admin_addr, EONLY_ADMIN);

        let store = borrow_global_mut<CollectionStore>(@prompt_marketplace);
        assert!(table::contains(&store.collections, collection_id), ECOLLECTION_NOT_FOUND);

        let collection = table::borrow_mut(&mut store.collections, collection_id);
        collection.paused = !collection.paused;

        // Emit pause event
        let events = table::borrow_mut(&mut store.collection_events, collection_id);
        event::emit_event(&mut events.pause_events, CollectionPausedEvent {
            collection_id,
            paused: collection.paused,
            timestamp: timestamp::now_seconds()
        });
    }

    // Add a view function to get user's prompts
    #[view]
    public fun get_user_prompts(user_addr: address): vector<u64> acquires UserPromptStore {
        if (!exists<UserPromptStore>(user_addr)) {
            return vector::empty()
        };
        
        let store = borrow_global<UserPromptStore>(user_addr);
        let prompt_ids = vector::empty();
        let i = 0;
        let len = vector::length(&store.prompts);
        
        while (i < len) {
            let prompt = vector::borrow(&store.prompts, i);
            vector::push_back(&mut prompt_ids, prompt.id);
            i = i + 1;
        };
        
        prompt_ids
    }
}
