module skip::entrypoint {    
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::error;

    use initia_std::string::{Self, String};
    use initia_std::simple_map::{Self, SimpleMap};
    use initia_std::event;
    use initia_std::fungible_asset::{Metadata};
    use initia_std::object::{Object};
    use initia_std::cosmos;
    use initia_std::coin;
    use initia_std::from_bcs;
    use initia_std::base64;
    use initia_std::json;
    use initia_std::simple_json;
    use initia_std::option;
    use initia_std::address;

    use skip::ackcallback;

    struct AdaptorInfo has copy, drop, store{
        module_address: address,
        module_name: String,
    }

    struct ModuleStore has key {
        swap_venues: SimpleMap<String, AdaptorInfo>,
        swap_venue_count: u64,
    }

    struct ActionTransferArgs has copy, drop {
        to_address: address,
    }

    struct ActionIBCTransferArgs has copy, drop {
        source_channel: String,
        receiver: String,
        memo: String,
    }

    struct ActionContractArgs has copy, drop {
        module_address: address,
        module_name: String,
        function_name: String,
        type_args: vector<String>,
        args: vector<vector<u8>>,
    }

    const EKEY_ALREADY_EXISTS: u64 = 0;
    const EKEY_NOT_FOUND: u64 = 1;
    const ESWAP_INVALID_FUNCTION: u64 = 2;
    const EINVALID_ASSET: u64 = 3;
    const ELESS_THAN_MIN_ASSET: u64 = 4;

    const POST_ACTION_TRANSFER: u8 = 0;
    const POST_ACTION_IBCTRANSFER: u8 = 1;
    const POST_ACTION_CONTRACT: u8 = 2;

    const INITIAL_SWAP_VENUES: vector<vector<u8>> = vector[b"initia_dex", b"initia_minitswap", b"initia_stableswap"];

    #[event]
    struct AddSwapVenueEvent has drop, store {
        name: String,
        module_address: address,
        module_name: String,
    }

    fun init_module(chain: &signer) {
        let swap_venues = simple_map::create<String,AdaptorInfo>();
        vector::for_each(INITIAL_SWAP_VENUES, |swap_venue| {
            let swap_venue = string::utf8(swap_venue);
            simple_map::add(&mut swap_venues, swap_venue, AdaptorInfo {
                module_address: @skip,
                module_name: swap_venue,
            });
            event::emit<AddSwapVenueEvent>(
                AddSwapVenueEvent {
                    name: swap_venue,
                    module_address: @skip,
                    module_name: swap_venue,
                }
            )
        });
        move_to(chain, ModuleStore {
            swap_venues: swap_venues,
            swap_venue_count: vector::length(&INITIAL_SWAP_VENUES),
        });
    }

    //
    // Entry Functions
    //

    /// SwapAndAction is an entry function for swapping and performing post actions.
    /// 
    /// ActionArgs:
    /// 1. Swap and Transfer
    /// It only contains the recipient address.
    /// 
    ///     action_args: vec![
    ///         recipient(cosmos addr): bcs(String),
    ///     ]
    /// 
    /// 2. Swap and IBC Transfer
    /// 
    ///     action args: vec![
    ///         source_channel: bcs(String), 
    ///         recipient(cosmos addr): bcs(String), 
    ///         memo: bcs(String),
    ///     ]
    /// 
    /// 3. Swap and Contract Exec
    /// 
    ///     action args: vec![
    ///         module_address: bcs(address), 
    ///         module_name: bcs(String), 
    ///         function_name: bcs(String), 
    ///         type_args: bcs(vec![String]), 
    ///         args: bcs(vec![vec![u8]]),
    ///     ]
    /// 
    /// Note: Entry functions can accept primitive types, Strings, Option, and vectors as arguments, 
    /// but they cannot accept Structs (e.g. Resources like FungibleAsset).
    /// 
    /// Note: Entry functions must not have any return values.
    /// 
    public entry fun swap_and_action(
        account: &signer,
        swap_venue_name: String,
        swap_function_name: String,
        user_swap_coin: String,
        user_swap_amount: u64,
        pools: vector<String>,
        coins: vector<String>,
        min_swap_coin: String,
        min_swap_amount: u64,
        timeout_timestamp: u64,
        post_swap_action: u8,
        recover_address: String,
        action_args: vector<vector<u8>>,
    ) acquires ModuleStore{
        swap_and_action_(
            account,
            swap_venue_name,
            swap_function_name,
            user_swap_coin,
            user_swap_amount,
            pools,
            coins,
            min_swap_coin,
            min_swap_amount,
            timeout_timestamp,
            post_swap_action,
            recover_address,
            action_args,
        );
    }

    /// This is not entended to be executed by a user,
    /// but it will be executed by swap_and_action.
    public entry fun post_action(
        account: &signer,
        coin: Object<Metadata>,
        amount: u64,
        timeout_timestamp: u64,
        post_swap_action: u8,
        recover_address: address,
        action_args: vector<vector<u8>>,
    ) {
        post_action_(
            account,
            coin,
            amount,
            timeout_timestamp,
            post_swap_action,
            recover_address,
            action_args,
        )
    }

    //
    // Implementations
    //

    fun swap_and_action_(
        account: &signer,
        swap_venue_name: String,
        swap_function_name: String,
        user_swap_coin: String,
        user_swap_amount: u64,
        pools: vector<String>,
        coins: vector<String>,
        min_swap_coin: String,
        min_swap_amount: u64,
        timeout_timestamp: u64,
        post_swap_action: u8,
        recover_address: String,
        action_args: vector<vector<u8>>,
    ) acquires ModuleStore {
        let module_store = borrow_global<ModuleStore>(@skip);
        let swap_venue_info = simple_map::borrow(&module_store.swap_venues, &swap_venue_name);

        let user_swap_coin = coin::denom_to_metadata(user_swap_coin);
        let pools = vector::map(pools, |pool| coin::denom_to_metadata(pool));
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        let min_swap_coin = coin::denom_to_metadata(min_swap_coin);
        let recover_address = address::from_sdk(recover_address);

        assert!( swap_function_name == string::utf8(b"swap_exact_asset_in")
                    || swap_function_name == string::utf8(b"swap_exact_asset_out"), 
                    error::invalid_argument(ESWAP_INVALID_FUNCTION),
        );
        assert!(user_swap_coin == *vector::borrow(&coins, 0), EINVALID_ASSET);
        assert!(min_swap_coin == *vector::borrow(&coins, vector::length(&coins) - 1), EINVALID_ASSET);

        let swapmsg_args = create_swapmsg_args(
            user_swap_amount,
            pools,
            coins,
            min_swap_amount,
        );
        
        // add move msgexecute into response messages 
        cosmos::move_execute(
            account,
            swap_venue_info.module_address, 
            swap_venue_info.module_name, 
            swap_function_name,
            vector<String>[],
            swapmsg_args,
        );

        let postaction_args = create_postaction_args(
            min_swap_coin,
            min_swap_amount,
            timeout_timestamp, 
            post_swap_action,
            recover_address,
            action_args,
        );

        cosmos::move_execute(
            account,
            @skip,
            string::utf8(b"entrypoint"),
            string::utf8(b"post_action"),
            vector<String>[],
            postaction_args,
        )
    }

    fun create_swapmsg_args(
        user_swap_amount: u64,
        pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
        min_amount: u64,
    ): vector<vector<u8>> {
        let msg_args = vector<vector<u8>>[];
        let amount_arg = bcs::to_bytes(&user_swap_amount);
        let pools_arg = bcs::to_bytes(&pools);
        let coins_arg = bcs::to_bytes(&coins);
        let min_amount_arg = bcs::to_bytes(&min_amount);

        vector::push_back(&mut msg_args, amount_arg);
        vector::push_back(&mut msg_args, pools_arg);
        vector::push_back(&mut msg_args, coins_arg);
        vector::push_back(&mut msg_args, min_amount_arg);

        msg_args
    }

    fun create_postaction_args(
        coin: Object<Metadata>,
        amount: u64,
        timeout_timestamp: u64,
        post_swap_action: u8,
        recover_address: address,
        action_args: vector<vector<u8>>,
    ): vector<vector<u8>> {
        let msg_args = vector<vector<u8>>[];
        let coin_arg = bcs::to_bytes(&coin);
        let amount_arg = bcs::to_bytes(&amount);
        let timeout_timestamp_arg = bcs::to_bytes(&timeout_timestamp);
        let post_swap_action_arg = bcs::to_bytes(&post_swap_action);
        let recover_address_arg = bcs::to_bytes(&recover_address);
        let action_arg = bcs::to_bytes(&action_args);

        vector::push_back(&mut msg_args, coin_arg);
        vector::push_back(&mut msg_args, amount_arg);
        vector::push_back(&mut msg_args, timeout_timestamp_arg);
        vector::push_back(&mut msg_args, post_swap_action_arg);
        vector::push_back(&mut msg_args, recover_address_arg);
        vector::push_back(&mut msg_args, action_arg);

        msg_args
    }

    fun post_action_(
        account: &signer,
        coin: Object<Metadata>,
        amount: u64,
        timeout_timestamp: u64,
        post_swap_action: u8,
        recover_address: address,
        action_args: vector<vector<u8>>,
    ) {
        let account_addr = signer::address_of(account);
        let post_swap_balance = coin::balance(account_addr,coin);
        assert!(post_swap_balance >= amount, error::invalid_state(ELESS_THAN_MIN_ASSET));

        if(post_swap_action == POST_ACTION_TRANSFER) {
            let to_address = unpack_action_transfer_args(action_args);
            coin::transfer(account, to_address, coin, amount);
        } else if(post_swap_action == POST_ACTION_IBCTRANSFER) {
            let callback_id = ackcallback::store_recover_address(recover_address, amount, coin);
            let (
                source_channel,
                receiver, 
                memo,
            ) = unpack_action_ibctransfer_args(action_args);

            let memo = add_cb_to_memo(memo, callback_id, @skip);

            cosmos::transfer(
                account,
                receiver,
                coin,
                amount,
                string::utf8(b"transfer"),
                source_channel,
                0,
                0,
                timeout_timestamp,
                memo,
            );
        } else if(post_swap_action == POST_ACTION_CONTRACT) {
            let (
                module_address,
                module_name,
                function_name,
                type_args,
                args
            ) = unpack_action_contract_args(action_args);
            cosmos::move_execute(
                account,
                module_address,
                module_name,
                function_name,
                type_args,
                args,
            );
        }
    }

    fun add_cb_to_memo(memo: String, callback_id: u64, module_address: address): String {
        if (string::length(&memo) == 0) {
            memo = string::utf8(b"{}");
        };

        let obj = simple_json::from_json_object(json::parse(memo));
        simple_json::increase_depth(&mut obj);
        
        let move_str = string::utf8(b"move");
        let ok = simple_json::try_find_and_set_index(&mut obj, &move_str);
        if(!ok) {
            simple_json::set_to_last_index(&mut obj);
            simple_json::set_object(&mut obj, option::some(move_str));
        };
        simple_json::increase_depth(&mut obj);
        /*
            "async_callback": {
                "id": ,
                "module_address": "",
                "module_name": ""
            }
        */
        simple_json::set_object(&mut obj, option::some(string::utf8(b"async_callback")));
        simple_json::increase_depth(&mut obj);
        simple_json::set_int_raw(
            &mut obj, 
            option::some(string::utf8(b"id")), 
            true, (callback_id as u256),
        );
        simple_json::set_string(
            &mut obj, 
            option::some(string::utf8(b"module_address")), 
            address::to_string(module_address),
        );
        simple_json::set_string(
            &mut obj, 
            option::some(string::utf8(b"module_name")), 
            string::utf8(b"ackcallback"),
        );
        json::stringify(simple_json::to_json_object(&obj))
    }

    fun unpack_action_transfer_args(action_args: vector<vector<u8>>): address {
        assert!(vector::length(&action_args) == 1, error::invalid_argument(0));
        let arg = vector::pop_back(&mut action_args);
        let to_address: address = address::from_sdk(from_bcs::to_string(arg));
        
        to_address
    }

    fun unpack_action_ibctransfer_args(action_args: vector<vector<u8>>): (String, String, String) {
        assert!(vector::length(&action_args) == 3, error::invalid_argument(0));
        let arg = vector::pop_back(&mut action_args);
        let memo: String = from_bcs::to_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let receiver: String = from_bcs::to_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let source_channel: String = from_bcs::to_string(arg);
        (
            source_channel,
            receiver, 
            memo,
        )
    }

    fun unpack_action_contract_args(action_args: vector<vector<u8>>): (address, String, String, vector<String>, vector<vector<u8>>) {
        assert!(vector::length(&action_args) == 5, error::invalid_argument(0));
        let arg = vector::pop_back(&mut action_args);
        let args: vector<vector<u8>> = from_bcs::to_vector_bytes(arg);
        let arg = vector::pop_back(&mut action_args);
        let type_args: vector<String> = from_bcs::to_vector_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let function_name: String = from_bcs::to_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let module_name: String = from_bcs::to_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let module_address: address = from_bcs::to_address(arg);

        (
            module_address,
            module_name,
            function_name,
            type_args,
            args,
        )
    }

    //
    // View Functions
    //

    // @dev: to_address is cosmos address
    #[view]
    fun pack_action_transfer_args(to_address: String): vector<vector<u8>>{
        let action_args = vector<vector<u8>>[];
        vector::push_back(&mut action_args, bcs::to_bytes(&to_address));
        action_args
    }

    // @dev: receiver is cosmos address
    #[view]
    fun pack_action_ibctransfer_args(source_channel: String, receiver: String, memo: String): vector<vector<u8>> {
        let action_args = vector<vector<u8>>[];
        vector::push_back(&mut action_args, bcs::to_bytes(&source_channel));
        vector::push_back(&mut action_args, bcs::to_bytes(&receiver));
        vector::push_back(&mut action_args, bcs::to_bytes(&memo));
        action_args
    }

    #[view]
    fun pack_action_contract_args(module_address: address, module_name: String, function_name: String, type_args: vector<String>, args: vector<vector<u8>>): vector<vector<u8>> {
        let action_args = vector<vector<u8>>[];
        vector::push_back(&mut action_args, bcs::to_bytes(&module_address));
        vector::push_back(&mut action_args, bcs::to_bytes(&module_name));
        vector::push_back(&mut action_args, bcs::to_bytes(&function_name));
        vector::push_back(&mut action_args, bcs::to_bytes(&type_args));
        vector::push_back(&mut action_args, bcs::to_bytes(&args));
        action_args
    }

    #[view]
    fun pack_swap_and_action_args(
        swap_venue_name: String,
        swap_function_name: String,
        user_swap_coin: address,
        user_swap_amount: u64,
        pools: vector<address>,
        coins: vector<address>,
        min_swap_coin: address,
        min_swap_amount: u64,
        timeout_timestamp: u64,
        post_swap_action: u8,
        action_args: vector<vector<u8>>
    ): vector<String> {
        let args = vector<String>[];
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&swap_venue_name)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&swap_function_name)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&user_swap_coin)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&user_swap_amount)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&pools)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&coins)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&min_swap_coin)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&min_swap_amount)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&timeout_timestamp)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&post_swap_action)));
        vector::push_back(&mut args, base64::to_string(bcs::to_bytes(&action_args)));
        
        args
    }

    #[test_only]
    public fun init_module_for_test(
        chain: &signer
    ) {
        init_module(chain);
    }

    #[test(chain=@0x1)]
    public fun default_adaptors_test(
        chain: &signer
    ) acquires ModuleStore{
        init_module_for_test(chain);

        let module_store = borrow_global<ModuleStore>(signer::address_of(chain));
        let length = simple_map::length(&module_store.swap_venues);
        assert!(length == vector::length(&INITIAL_SWAP_VENUES), 1);

        vector::for_each(INITIAL_SWAP_VENUES, |swap_venue| {
            let swap_venue = string::utf8(swap_venue);
            let swap_venue_info = simple_map::borrow(&module_store.swap_venues, &swap_venue);
            assert!(swap_venue_info.module_address == @skip, 2);
            assert!(swap_venue_info.module_name == swap_venue, 3);
        })
    }

    #[test(chain=@0x1)]
    public fun add_swap_venue_event_test(
        chain: &signer
    ) {
        init_module_for_test(chain);

        let events = event::emitted_events<AddSwapVenueEvent>();
        let length = vector::length(&events);
        assert!(length == vector::length(&INITIAL_SWAP_VENUES), 1);

        vector::enumerate_ref(&INITIAL_SWAP_VENUES, |i, swap_venue| {
            let swap_venue = string::utf8(*swap_venue);
            let event = vector::borrow(&events, i);
            assert!(event.name == swap_venue, 2);
            assert!(event.module_address == @skip, 3);
            assert!(event.module_name == swap_venue, 4);
        });
    }

    #[test]
    public fun pack_unpack_action_transfer_args() {
        let addr = @0x1DDF1EBB9C2796754EA1DADBDEE912AB793CF647;
        let cosmos_addr = address::to_sdk(addr);
        
        let packed_args = pack_action_transfer_args(cosmos_addr);
        let unpacked_args = unpack_action_transfer_args(packed_args);

        assert!(addr == unpacked_args, 1);
    }

    #[test]
    public fun pack_unpack_action_ibctransfer_args() {
        let source_channel = string::utf8(b"channel-0");
        let receiver = string::utf8(b"init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp");
        let memo=string::utf8(b"{\"move\":{\"message\":{}}}");
        let packed_args = pack_action_ibctransfer_args(source_channel, receiver, memo);
        let (a, b, c) = unpack_action_ibctransfer_args(packed_args);
        assert!(source_channel == a, 1);
        assert!(receiver == b, 2);
        assert!(memo == c, 3);
    }

    #[test]
    public fun insert_callback_to_memo() {
        let memo=string::utf8(b"{\"move\":{\"message\":{}}}");
        let obj = simple_json::from_json_object(json::parse(memo));
        simple_json::increase_depth(&mut obj);
        simple_json::increase_depth(&mut obj);
        /*
            "async_callback": {
                "id": ,
                "module_address": "",
                "module_name": ""
            }
        */
        simple_json::set_object(&mut obj, option::some(string::utf8(b"async_callback")));
        simple_json::increase_depth(&mut obj);
        simple_json::set_int_raw(&mut obj, option::some(string::utf8(b"id")), true, 1);
        simple_json::set_string(&mut obj, 
                                option::some(string::utf8(b"module_address")), 
                                string::utf8(b"0x1"));
        
        simple_json::set_string(&mut obj, 
                                option::some(string::utf8(b"module_name")), 
                                string::utf8(b"ackcallback"));
        let memo = json::stringify(simple_json::to_json_object(&obj));
        
        assert!(memo == string::utf8(b"{\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x1\",\"module_name\":\"ackcallback\"},\"message\":{}}}"), 1);
    }

    #[test]
    public fun pack_unpack_action_contract_args() {
        let module_addr = @0x123;
        let module_name = string::utf8(b"simplecount");
        let function_name = string::utf8(b"increase");
        let type_args = vector<String>[];
        let args = vector<vector<u8>>[];
        
        let packed_args = pack_action_contract_args(module_addr, module_name, function_name, type_args, args);
        let (a, b, c, d, e) = unpack_action_contract_args(packed_args);
        assert!(module_addr == a, 1);
        assert!(module_name == b, 2);
        assert!(function_name == c, 3);
        assert!(type_args == d, 4);
        assert!(args == e, 5);
    }

    #[test_only]
    use initia_std::coin::{BurnCapability, FreezeCapability, MintCapability};

    #[test_only]
    use initia_std::primary_fungible_store;

    #[test(chain=@0x1, skip=@skip)]
    public fun test_post_action_with_empty_memo(chain: &signer, skip: &signer) {
        init_module_for_test(skip);
        primary_fungible_store::init_module_for_test(chain);
        ackcallback::init_module_for_test(skip);
        let (_, _, mint_cap) = initialized_coin(chain, string::utf8(b"usdc"));

        let c = coin::mint(&mint_cap, 1000000000);
        coin::deposit(signer::address_of(skip), c);

        post_action(
            skip,
            coin::denom_to_metadata(string::utf8(b"usdc")),
            9193547,
            1711667948005706000,
            1,
            address::from_sdk(string::utf8(b"init1wsdmqqsv2ze9uwvqz3mzn48jtqpawhrcfhfr25")),
            from_bcs::to_vector_bytes(base64::from_string(string::utf8(b"AwoJY2hhbm5lbC0wLCtpbml0MXdzZG1xcXN2MnplOXV3dnF6M216bjQ4anRxcGF3aHJjZmhmcjI1AQA="))),
        )
    }

    #[test_only]
    fun initialized_coin(
        account: &signer,
        symbol: String,
    ): (BurnCapability, FreezeCapability, MintCapability) {
        let (mint_cap, burn_cap, freeze_cap, _) = coin::initialize_and_generate_extend_ref (
            account,
            std::option::none(),
            string::utf8(b""),
            symbol,
            6,
            string::utf8(b""),
            string::utf8(b""),
        );

        return (burn_cap, freeze_cap, mint_cap)
    }

    #[test]
    fun test_add_cb_to_memo_empty() {
        let memo = string::utf8(b"");
        let memo = add_cb_to_memo(memo, 1, @0x101);
        assert!(memo == string::utf8(b"{\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x0000000000000000000000000000000000000000000000000000000000000101\",\"module_name\":\"ackcallback\"}}}"), 0)
    }

    #[test]
    fun test_add_cb_to_memo_only_move() {
        let memo = string::utf8(b"{\"move\":{}}");
        let memo = add_cb_to_memo(memo, 1, @0x101);
        assert!(memo == string::utf8(b"{\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x0000000000000000000000000000000000000000000000000000000000000101\",\"module_name\":\"ackcallback\"}}}"), 0)
    }

    #[test]
    fun test_add_cb_to_memo_except_move() {
        let memo = string::utf8(b"{\"forward\":{\"receiver\":\"chain-c-bech32-address\"},\"wasm\":{}}");
        let memo = add_cb_to_memo(memo, 1, @0x101);
        assert!(memo == string::utf8(b"{\"forward\":{\"receiver\":\"chain-c-bech32-address\"},\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x0000000000000000000000000000000000000000000000000000000000000101\",\"module_name\":\"ackcallback\"}},\"wasm\":{}}"), 0)
    }
}