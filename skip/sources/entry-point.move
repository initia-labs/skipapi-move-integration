module skip::entry_point {    
    use std::signer;
    use std::vector;
    use std::error;
    use std::bcs;

    use initia_std::string::{Self, String};
    use initia_std::fungible_asset::{Metadata};
    use initia_std::object::{Self, Object};
    use initia_std::cosmos;
    use initia_std::coin;
    use initia_std::from_bcs;
    use initia_std::base64;
    use initia_std::json::{Self, JSONValue, JSONObject};
    use initia_std::option::{Self, Option};
    use initia_std::address;
    use initia_std::string_utils;
    use initia_std::bigdecimal::{Self, BigDecimal};

    use skip::ack_callback;
    use skip::initia_dex;
    use skip::initia_stableswap;
    use skip::initia_minitswap;

    struct SimulateSwapExactAssetInResponse has drop {
        amount_out: u64,
        spot_price: Option<BigDecimal>,
    }

    struct SimulateSwapExactAssetOutResponse has drop {
        amount_in: u64,
        spot_price: Option<BigDecimal>,
    }

    struct InitiateTokenDepositObject has copy, drop {
        _type_: String,
        sender: String,
        bridge_id: String,
        to: String,
        data: String,
        amount: Option<AmountObject>,
    }

    struct AmountObject has copy, drop {
        denom: String,
        amount: String,
    }

    struct AsyncCallbackObject has copy, drop {
        id: JSONValue,
        module_address: String,
        module_name: String,
    }

    const INITIA_DEX: u8 = 0;
    const INITIA_STABLESWAP: u8 = 1;
    const INITIA_MINITSWAP: u8 = 2;

    const EKEY_ALREADY_EXISTS: u64 = 0;
    const EKEY_NOT_FOUND: u64 = 1;
    const ESWAP_INVALID_FUNCTION: u64 = 2;
    const EINVALID_ASSET: u64 = 3;
    const ELESS_THAN_MIN_ASSET: u64 = 4;
    const EINVALID_POST_ACTION: u64 = 5;
    const EMAX_OFFER_AMOUNT: u64 = 6;
    const EINVALID_SWAP_VENUE: u64 = 7;
    const EINVALID_VENUE_LENGTH: u64 = 8;
    const EINVALID_POOLS_LENGTH: u64 = 9;
    const EINVALID_COINS_LENGTH: u64 = 10;
    const EINVALID_ARGUMENTS:u64 = 11;

    const SWAP_FUNCTION_SWAP_EXACT_ASSET_IN: u8 = 0;
    const SWAP_FUNCTION_SWAP_EXACT_ASSET_OUT: u8 = 1;

    const POST_ACTION_TRANSFER: u8 = 0;
    const POST_ACTION_IBCTRANSFER: u8 = 1;
    const POST_ACTION_CONTRACT: u8 = 2;
    const POST_ACTION_OPBRIDGE: u8 = 3;

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
    /// 4. Swap and OPBridge
    /// 
    ///    action args: vec![  
    ///        bridge_id: bcs(u64),
    ///        to: bcs(String),
    ///        data: bcs(String),
    ///    ]
    /// 
    /// Note: Entry functions can accept primitive types, Strings, Option, and vectors as arguments, 
    /// but they cannot accept Structs (e.g. Resources like FungibleAsset).
    /// 
    /// Note: Entry functions must not have any return values.
    /// 
    public entry fun swap_and_action(
        account: &signer,
        venues: vector<u8>,
        function: u8,
        // this is used as max_offer_amount in swap_exact_asset_out
        amount_in: u64, 
        // this is used as min_amount in swap_exact_asset_in
        amount_out: u64, 
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,

        post_action: u8,
        timeout_timestamp: u64,
        recover_address: String,
        post_action_args: vector<vector<u8>>,
    ) {
        let (coin_out, amount_out) = swap_(
            account,
            venues,
            function,
            amount_in,
            amount_out,
            pools,
            coins,
        );
        post_action_(
            account,
            coin_out,
            amount_out,
            post_action,
            timeout_timestamp,
            recover_address,
            post_action_args,
        );
    }

    fun swap_(
        account: &signer,
        venues: vector<u8>,
        function: u8,
        // this is used as max_offer_amount in swap_exact_asset_out
        amount_in: u64, 
        // this is used as min_amount in swap_exact_asset_in
        amount_out: u64, 
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,
    ): (Object<Metadata>, u64) {

        let venue_length = vector::length(&venues);
        assert!(venue_length > 0, error::invalid_argument(EINVALID_VENUE_LENGTH));
        assert!(vector::length(&pools) == venue_length, error::invalid_argument(EINVALID_POOLS_LENGTH));
        assert!(vector::length(&coins) == venue_length, error::invalid_argument(EINVALID_COINS_LENGTH));

        if( function == SWAP_FUNCTION_SWAP_EXACT_ASSET_OUT) {
            let offer_amount = simulate_swap_exact_asset_out(amount_out, venues, pools, coins);
            assert!(offer_amount <= amount_in, EMAX_OFFER_AMOUNT);

            amount_out = amount_out * 99 / 100;
            amount_in = offer_amount;
        } else if(function != SWAP_FUNCTION_SWAP_EXACT_ASSET_IN) {
            abort error::invalid_argument(ESWAP_INVALID_FUNCTION)
        };

        let i = 0;
        let coin_in: Object<Metadata> = coin::denom_to_metadata(*vector::borrow(vector::borrow(&coins, 0), 0));
        while(i < venue_length){
            let venue = *vector::borrow(&venues, i);
            let pools_i = *vector::borrow(&pools, i);
            let coins_i = vector::map(*vector::borrow(&coins, i), |coin| coin::denom_to_metadata(coin));
            

            assert!(coin_in == *vector::borrow(&coins_i, 0), EINVALID_ASSET);
            let min_swap_out_amount = if (i == venue_length - 1) {
                amount_out
            } else {
                0
            };
            let coin_out = *vector::borrow(&coins_i, vector::length(&coins_i) - 1);
            let pre_swap_balance_out = coin::balance(signer::address_of(account), coin_out);
            swap_exact_asset_in_(account, venue, amount_in, pools_i, coins_i, min_swap_out_amount);
            let post_swap_balance_out = coin::balance(signer::address_of(account), coin_out);
            amount_in = post_swap_balance_out - pre_swap_balance_out;
            coin_in = coin_out;

            i = i + 1;
        };
        (coin_in, amount_in)
    }

    fun swap_exact_asset_in_(
        account: &signer,
        venue: u8,
        amount: u64,
        pools: vector<String>,
        coins: vector<Object<Metadata>>,
        min_amount: u64,
    ) {
        if(venue == INITIA_DEX) {
            let pools = vector::map(pools, |pool| object::convert(coin::denom_to_metadata(pool)));
            initia_dex::swap_exact_asset_in(
                account,
                amount,
                pools,
                coins,
                min_amount,
            )
        } else if(venue == INITIA_STABLESWAP){
            let pools = vector::map(pools, |pool| object::convert(coin::denom_to_metadata(pool)));
            initia_stableswap::swap_exact_asset_in(
                account,
                amount,
                pools,
                coins,
                min_amount,
            )
        } else if(venue == INITIA_MINITSWAP){
            initia_minitswap::swap_exact_asset_in(
                account,
                amount,
                vector[],
                coins,
                min_amount,
            )
        } else {
            abort error::invalid_argument(EINVALID_SWAP_VENUE)
        }
    }

    public entry fun action(
        account: &signer,
        amount_out: u64, 
        coin_out: String,
        post_action: u8,
        timeout_timestamp: u64,
        recover_address: String,
        post_action_args: vector<vector<u8>>,
    ) {
        post_action_(
            account,
            coin::denom_to_metadata(coin_out),
            amount_out,
            post_action,
            timeout_timestamp,
            recover_address,
            post_action_args,
        );
    }

    fun post_action_(
        account: &signer,
        coin_out: Object<Metadata>,
        amount_out: u64,
        post_action: u8,
        timeout_timestamp: u64,
        recover_address: String,
        post_action_args: vector<vector<u8>>,
    ) {
        if(post_action == POST_ACTION_TRANSFER) {
            let to_address = unpack_action_transfer_args(post_action_args);
            coin::transfer(account, to_address, coin_out, amount_out);
        } else if(post_action == POST_ACTION_IBCTRANSFER) {
            let recover_address = address::from_sdk(recover_address);
            let callback_id = ack_callback::store_recover_address(account, recover_address, amount_out, coin_out);
            let (
                source_channel,
                receiver, 
                memo,
            ) = unpack_action_ibctransfer_args(post_action_args);

            let memo = add_cb_to_memo(memo, callback_id, @skip);
            cosmos::transfer(
                account,
                receiver,
                coin_out,
                amount_out,
                string::utf8(b"transfer"),
                source_channel,
                0,
                0,
                timeout_timestamp,
                memo,
            );
        } else if(post_action == POST_ACTION_CONTRACT) {
            let (
                module_address,
                module_name,
                function_name,
                type_args,
                args
            ) = unpack_action_contract_args(post_action_args);
            cosmos::move_execute(
                account,
                module_address,
                module_name,
                function_name,
                type_args,
                args,
            );
        } else if(post_action == POST_ACTION_OPBRIDGE) {
            let (
                bridge_id,
                to,
                data
            ) = unpack_action_opbridge_args(post_action_args);
            let req = create_json_msg_initiate_token_deposit(signer::address_of(account), bridge_id, to, coin_out, amount_out, data);
            cosmos::stargate(account, req);
        } else {
            abort error::invalid_argument(EINVALID_POST_ACTION)
        }
    }

    fun create_json_msg_initiate_token_deposit(
        sender: address,
        bridge_id: u64,
        to: String,
        metadata: Object<Metadata>,
        amount: u64,
        data: String
    ): vector<u8> {
        json::marshal(
            &InitiateTokenDepositObject{
                _type_: string::utf8(b"/opinit.ophost.v1.MsgInitiateTokenDeposit"),
                sender: address::to_sdk(sender),
                bridge_id: string_utils::to_string(&bridge_id),
                to: to,
                data: base64::to_string(*string::bytes(&data)),
                amount: option::some(AmountObject{
                    denom: coin::metadata_to_denom(metadata),
                    amount: string_utils::to_string(&amount),
                }),
            }
        )
    }

    fun add_cb_to_memo(memo: String, callback_id: u64, module_address: address): String {
        if (string::length(&memo) == 0) {
            memo = string::utf8(b"{}");
        };

        let id = json::unmarshal<JSONValue>(*string::bytes(&string_utils::to_string(&callback_id)));

        let cb_obj = AsyncCallbackObject {
            id: id,
            module_address: address::to_string(module_address),
            module_name: string::utf8(b"ack_callback"),
        };

        let obj = json::unmarshal<JSONObject>(*string::bytes(&memo));
        let move_obj = json::get_elem<JSONObject>(&obj, string::utf8(b"move"));

        let move_obj = if(option::is_none(&move_obj)){
            // make empty move object
            json::unmarshal<JSONObject>(b"{}")
        } else {
            option::extract(&mut move_obj)
        };

        json::set_elem(&mut move_obj, string::utf8(b"async_callback"), &cb_obj);
        json::set_elem(&mut obj, string::utf8(b"move"), &move_obj);

        json::marshal_to_string(&obj)
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

    fun unpack_action_opbridge_args(action_args: vector<vector<u8>>): (u64, String, String) {
        assert!(vector::length(&action_args) == 3, error::invalid_argument(0));
        let arg = vector::pop_back(&mut action_args);
        let data = from_bcs::to_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let to = from_bcs::to_string(arg);
        let arg = vector::pop_back(&mut action_args);
        let bridge_id: u64 = from_bcs::to_u64(arg);

        (
            bridge_id,
            to,
            data,
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
    fun pack_action_opbridge_args(bridge_id: u64, to: String, data: String): vector<vector<u8>> {
        let action_args = vector<vector<u8>>[];
        vector::push_back(&mut action_args, bcs::to_bytes(&bridge_id));
        vector::push_back(&mut action_args, bcs::to_bytes(&to));
        vector::push_back(&mut action_args, bcs::to_bytes(&data));
        action_args
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
    public fun pack_unpack_action_opbridge_args() {
        let bridge_id = 1;
        let to = string::utf8(b"init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp");
        let data = string::utf8(b"abc");

        let packed_args = pack_action_opbridge_args(bridge_id, to, data);
        let (a, b, c) = unpack_action_opbridge_args(packed_args);
        assert!(bridge_id == a, 1);
        assert!(to == b, 2);
        assert!(data == c, 3);
    }
    //
    // View Functions
    //
    #[view]
    fun simulate_swap_exact_asset_in(
        amount: u64,
        swap_venues: vector<u8>,
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,
    ):u64 {
        let venue_length = vector::length(&swap_venues);
        assert!(venue_length > 0, error::invalid_argument(EINVALID_VENUE_LENGTH));
        assert!(vector::length(&pools) == venue_length, error::invalid_argument(EINVALID_POOLS_LENGTH));
        assert!(vector::length(&coins) == venue_length, error::invalid_argument(EINVALID_COINS_LENGTH));
        let i = 0;
        let coin_in: String = *vector::borrow(vector::borrow(&coins, 0), 0);
        while(i < venue_length){
            let venue = *vector::borrow(&swap_venues, i);
            let pools_i = *vector::borrow(&pools, i);
            let coins_i = *vector::borrow(&coins, i);

            assert!(coin_in == *vector::borrow(&coins_i, 0), EINVALID_ASSET);
            if(venue == INITIA_DEX) {
                amount = initia_dex::simulate_swap_exact_asset_in(amount, pools_i, coins_i);
            } else if(venue == INITIA_STABLESWAP) {
                amount = initia_stableswap::simulate_swap_exact_asset_in(amount, pools_i, coins_i);
            } else if(venue == INITIA_MINITSWAP) {
                amount = initia_minitswap::simulate_swap_exact_asset_in(amount, pools_i, coins_i);
            } else {
                abort error::invalid_argument(EINVALID_SWAP_VENUE)
            };
            coin_in = *vector::borrow(&coins_i, vector::length(&coins_i) - 1);
            i = i + 1;
        };
        amount
    }

    #[view]
    fun simulate_swap_exact_asset_out(
        amount: u64,
        swap_venues: vector<u8>,
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,
    ):u64 {
        let venue_length = vector::length(&swap_venues);
        assert!(venue_length > 0, error::invalid_argument(EINVALID_VENUE_LENGTH));
        assert!(vector::length(&pools) == venue_length, error::invalid_argument(EINVALID_POOLS_LENGTH));
        assert!(vector::length(&coins) == venue_length, error::invalid_argument(EINVALID_COINS_LENGTH));
        let i = venue_length ;
        let last_coins_i = vector::borrow(&coins, vector::length(&coins)-1);
        let coin_out: String = *vector::borrow(last_coins_i, vector::length(last_coins_i)-1);
        while(i > 0){
            i = i - 1;
            let venue = *vector::borrow(&swap_venues, i);
            let pools_i = *vector::borrow(&pools, i);
            let coins_i = *vector::borrow(&coins, i);
            assert!(coin_out == *vector::borrow(&coins_i, vector::length(&coins_i)-1), EINVALID_ASSET);

            if(venue == INITIA_DEX) {
                amount = initia_dex::simulate_swap_exact_asset_out(amount, pools_i, coins_i);
            } else if(venue == INITIA_STABLESWAP) {
                amount = initia_stableswap::simulate_swap_exact_asset_out(amount, pools_i, coins_i);
            } else if(venue == INITIA_MINITSWAP) {
                amount = initia_minitswap::simulate_swap_exact_asset_out(amount, pools_i, coins_i);
            }else {
                abort error::invalid_argument(EINVALID_SWAP_VENUE)
            };

            coin_out = *vector::borrow(&coins_i, 0);
        };
        amount
    }

    #[view]
    public fun get_spot_price(
        swap_venues: vector<u8>,
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,
    ): BigDecimal {
        let venue_length = vector::length(&swap_venues);
        assert!(venue_length > 0, error::invalid_argument(EINVALID_VENUE_LENGTH));
        assert!(vector::length(&pools) == venue_length, error::invalid_argument(EINVALID_POOLS_LENGTH));
        assert!(vector::length(&coins) == venue_length, error::invalid_argument(EINVALID_COINS_LENGTH));
        let i = 0;
        let coin_in: String = *vector::borrow(vector::borrow(&coins, 0), 0);
        let spot_price = bigdecimal::one();
        while(i < venue_length) {
            let venue = *vector::borrow(&swap_venues, i);
            let pools_i = *vector::borrow(&pools, i);
            let coins_i = *vector::borrow(&coins, i);
            let price: BigDecimal;

            assert!(coin_in == *vector::borrow(&coins_i, 0), EINVALID_ASSET);
            if(venue == INITIA_DEX) {
                price = initia_dex::get_spot_price(pools_i, coins_i);
            } else if(venue == INITIA_STABLESWAP) {
                price = initia_stableswap::get_spot_price(pools_i, coins_i);
            } else if(venue == INITIA_MINITSWAP) {
                price = initia_minitswap::get_spot_price(pools_i, coins_i);
            }else {
                abort error::invalid_argument(EINVALID_SWAP_VENUE)
            };
            spot_price = bigdecimal::mul(spot_price, price);
            coin_in = *vector::borrow(&coins_i, vector::length(&coins_i) - 1);
            i = i + 1;
        };
        
        spot_price
    }

    #[view]
    public fun simulate_swap_exact_asset_in_with_metadata(
        amount: u64,
        swap_venues: vector<u8>,
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,
        include_spot_price: bool,
    ): SimulateSwapExactAssetInResponse {
        let response = SimulateSwapExactAssetInResponse {
            amount_out: simulate_swap_exact_asset_in(amount, swap_venues,pools, coins),
            spot_price: option::none(),
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(swap_venues, pools, coins);
            response.spot_price = option::some(spot_price);
        };
        
        response
    }

    #[view]
    public fun simulate_swap_exact_asset_out_with_metadata(
        amount: u64,
        swap_venues: vector<u8>,
        pools: vector<vector<String>>,
        coins: vector<vector<String>>,
        include_spot_price: bool,
    ): SimulateSwapExactAssetOutResponse {
        let response = SimulateSwapExactAssetOutResponse {
            amount_in: simulate_swap_exact_asset_out(amount, swap_venues,pools, coins),
            spot_price: option::none(),
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(swap_venues, pools, coins);
            response.spot_price = option::some(spot_price);
        };
        
        response
    }

    #[test_only]
    use initia_std::coin::{BurnCapability, FreezeCapability, MintCapability};

    #[test_only]
    use initia_std::primary_fungible_store;

    #[test(chain=@0x1, skip=@skip)]
    public fun test_post_action_with_empty_memo(chain: &signer, skip: &signer) {
        primary_fungible_store::init_module_for_test();
        let (_, _, mint_cap) = initialized_coin(chain, string::utf8(b"usdc"));

        let c = coin::mint(&mint_cap, 1000000000);
        coin::deposit(signer::address_of(skip), c);

        post_action_(
            skip,
            coin::denom_to_metadata(string::utf8(b"usdc")),
            9193547,
            1,
            1711667948005706000,
            string::utf8(b"init1wsdmqqsv2ze9uwvqz3mzn48jtqpawhrcfhfr25"),
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
        assert!(memo == string::utf8(b"{\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x0000000000000000000000000000000000000000000000000000000000000101\",\"module_name\":\"ack_callback\"}}}"), 0)
    }

    #[test]
    fun test_add_cb_to_memo_only_move() {
        let memo = string::utf8(b"{\"move\":{}}");
        let memo = add_cb_to_memo(memo, 1, @0x101);
        assert!(memo == string::utf8(b"{\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x0000000000000000000000000000000000000000000000000000000000000101\",\"module_name\":\"ack_callback\"}}}"), 0)
    }

    #[test]
    fun test_add_cb_to_memo_except_move() {
        let memo = string::utf8(b"{\"forward\":{\"receiver\":\"chain-c-bech32-address\"},\"wasm\":{}}");
        let memo = add_cb_to_memo(memo, 1, @0x101);
        assert!(memo == string::utf8(b"{\"forward\":{\"receiver\":\"chain-c-bech32-address\"},\"move\":{\"async_callback\":{\"id\":1,\"module_address\":\"0x0000000000000000000000000000000000000000000000000000000000000101\",\"module_name\":\"ack_callback\"}},\"wasm\":{}}"), 0)
    }

    #[test(chain=@0x1)]
    fun test_create_json_msg_initiate_token_deposit(chain: &signer) {
        primary_fungible_store::init_module_for_test();
        initialized_coin(chain, string::utf8(b"usdc"));
        
        let sender = @0x777105889E6E42F2BED14DD4D7286C9E982A3E31;
        let bridge_id = 1;
        let to = string::utf8(b"init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp");
        let metadata = coin::denom_to_metadata(string::utf8(b"usdc"));
        let amount = 1000000000;
        let data = string::utf8(b"abc");
        let req = create_json_msg_initiate_token_deposit(sender, bridge_id, to, metadata, amount, data);
        assert!(req == b"{\"@type\":\"/opinit.ophost.v1.MsgInitiateTokenDeposit\",\"amount\":{\"amount\":\"1000000000\",\"denom\":\"usdc\"},\"bridge_id\":\"1\",\"data\":\"YWJj\",\"sender\":\"init1wacstzy7dep090k3fh2dw2rvn6vz5033un04tm\",\"to\":\"init1rh03awuuy7t82n4pmtdaa6gj4duneaj8gghkqp\"}", 1);
    }
}