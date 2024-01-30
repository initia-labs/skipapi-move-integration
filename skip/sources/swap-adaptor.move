module skip::initiadex {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::dex::{Self, Config};
    use initia_std::decimal256::{Self, Decimal256};
    use initia_std::coin;
    use initia_std::fungible_asset::{Self, Metadata};
    use initia_std::object::{Object};

    const EINVALID_ARGUMENTS: u64 = 0;
    const ERETURN_AMOUNT: u64 = 1;
    const EMIN_AMOUNT: u64 = 2;
    const EMAX_OFFER_AMOUNT: u64 = 3;

    struct SimulateSwapExactAssetInResponse has copy, drop, store {
        amount_out: u64,
        spot_price: Option<Decimal256>,
    }

    struct SimulateSwapExactAssetOutResponse has copy, drop, store {
        amount_in: u64,
        spot_price: Option<Decimal256>,
    }

    public entry fun swap_exact_asset_in(
        account: &signer,
        amount: u64,
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
        min_amount: u64,
    ) {
        let swap_length = vector::length<Object<Config>>(&pools);
        let i = 0;

        let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);
        let offer_coin = coin::withdraw(account, *coin_in_metadata, amount);
        
        while(i < swap_length) {
            let pair = vector::borrow<Object<Config>>(&pools, i);
            let return_coin = dex::swap(*pair, offer_coin);
            
            offer_coin = return_coin;
            i = i + 1;
        };

        assert!(
            min_amount <= fungible_asset::amount(&offer_coin),
            error::invalid_state(EMIN_AMOUNT),
        );

        coin::deposit(signer::address_of(account), offer_coin);
    }

    public entry fun swap_exact_asset_out(
        account: &signer,
        amount: u64,
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
        max_offer_amount: u64,
    ) {
        let offer_amount = simulate_swap_exact_asset_out(amount, pools, coins);
        assert!(offer_amount <= max_offer_amount, EMAX_OFFER_AMOUNT);
        swap_exact_asset_in(account, offer_amount, pools, coins, amount);
    }

    public fun unpack_simulate_swap_exact_asset_in_response(response: &SimulateSwapExactAssetInResponse)
    : (u64, Option<Decimal256>) {
        (
            response.amount_out,
            response.spot_price,
        )
    }

    public fun unpack_simulate_swap_exact_asset_out_response(response: &SimulateSwapExactAssetOutResponse)
    : (u64, Option<Decimal256>) {
        (
            response.amount_in,
            response.spot_price,
        )
    }

    #[view]
    fun simulate_swap_exact_asset_in(
        amount: u64,
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
    ): u64 {
        let swap_length = vector::length<Object<Config>>(&pools);
        let i = 0;
        while(i < swap_length) {
            let pair = vector::borrow<Object<Config>>(&pools, i);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);

            amount = dex::get_swap_simulation(*pair, *coin_in_metadata, amount);
            i = i + 1;
        };
        
        amount
    }

    #[view]
    fun simulate_swap_exact_asset_out(
        amount: u64,
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
    ): u64 {
        let swap_length = vector::length<Object<Config>>(&pools);
        let i = swap_length;
        while(i > 0) {
            let pair = vector::borrow<Object<Config>>(&pools, i-1);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i-1);

            amount = dex::get_swap_simulation_given_out(*pair, *coin_in_metadata, amount);
            i = i - 1;
        };
        
        amount
    }

    #[view]
    fun get_spot_price(
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
    ): Decimal256 {
        let swap_length = vector::length<Object<Config>>(&pools);
        let i = 0;
        let spot_price = decimal256::one();
        while(i < swap_length) {
            let pair = vector::borrow<Object<Config>>(&pools, i);
            let coin_out_metadata = vector::borrow<Object<Metadata>>(&coins, i+1);

            let price = dex::get_spot_price(*pair, *coin_out_metadata);
            spot_price = decimal256::mul(&spot_price, &price);
            i = i + 1;
        };
        
        spot_price
    }

    #[view]
    fun simulate_swap_exact_asset_in_with_metadata(
        amount: u64,
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
        include_spot_price: bool,
    ): SimulateSwapExactAssetInResponse {
        let response = SimulateSwapExactAssetInResponse {
            amount_out: simulate_swap_exact_asset_in(amount, pools, coins),
            spot_price: option::none(),
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(pools, coins);
            response.spot_price = option::some(spot_price);
        };
        
        response
    }

    #[view]
    fun simulate_swap_exact_asset_out_with_metadata(
        amount: u64,
        pools: vector<Object<Config>>,
        coins: vector<Object<Metadata>>,
        include_spot_price: bool,
    ): SimulateSwapExactAssetOutResponse {
        let response = SimulateSwapExactAssetOutResponse {
            amount_in: simulate_swap_exact_asset_out(amount, pools, coins),
            spot_price: option::none(),
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(pools, coins);
            response.spot_price = option::some(spot_price);
        };
        
        response
    }

    #[test_only]
    use initia_std::string::{Self, String};
    #[test_only]
    use initia_std::object;
    #[test_only]
    use initia_std::primary_fungible_store;

    #[test_only]
    fun initialized_coin(
        account: &signer,
        symbol: String,
    ): (coin::BurnCapability, coin::FreezeCapability, coin::MintCapability) {
        let (mint_cap, burn_cap, freeze_cap, _) = coin::initialize_and_generate_extend_ref (
            account,
            option::none(),
            string::utf8(b""),
            symbol,
            6,
            string::utf8(b""),
            string::utf8(b""),
        );

        return (burn_cap, freeze_cap, mint_cap)
    }

    #[test_only]
    fun initialized_module_for_test(
        chain: &signer
    ): (vector<Object<Config>>, vector<Object<Metadata>>) {
        dex::init_module_for_test(chain);
        primary_fungible_store::init_module_for_test(chain);

        let chain_addr = signer::address_of(chain);

        let (_, _, initia_mint_cap) = initialized_coin(chain, string::utf8(b"INIT"));
        let (_, _, usdc_mint_cap) = initialized_coin(chain, string::utf8(b"USDC"));
        let (_, _, usdt_mint_cap) = initialized_coin(chain, string::utf8(b"USDT"));
        let init_metadata = coin::metadata(chain_addr, string::utf8(b"INIT"));
        let usdc_metadata = coin::metadata(chain_addr, string::utf8(b"USDC"));
        let usdt_metadata = coin::metadata(chain_addr, string::utf8(b"USDT"));

        coin::mint_to(&initia_mint_cap, chain_addr, 1010000);
        coin::mint_to(&usdc_mint_cap, chain_addr, 20000000);
        coin::mint_to(&usdt_mint_cap, chain_addr, 10000000);

        dex::create_pair_script(
            chain, 
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            decimal256::from_ratio(2, 1000),
            decimal256::from_ratio(1, 10),
            decimal256::from_ratio(1, 10),
            init_metadata,
            usdc_metadata,
            1000000,
            10000000,
        );

        dex::create_pair_script(
            chain, 
            std::string::utf8(b"nam2"),
            std::string::utf8(b"SYMBOL2"),
            decimal256::from_ratio(1, 100),
            decimal256::from_ratio(1, 10),
            decimal256::from_ratio(1, 10),
            usdc_metadata,
            usdt_metadata,
            10000000,
            10000000,
        );

        let pool_metadata = coin::metadata(chain_addr, string::utf8(b"SYMBOL"));
        let pair = object::convert<Metadata, Config>(pool_metadata);
        let pool2_metadata = coin::metadata(chain_addr, string::utf8(b"SYMBOL2"));
        let pair2 = object::convert<Metadata, Config>(pool2_metadata);

        let pools = vector[pair, pair2];
        let coins = vector[init_metadata, usdc_metadata, usdt_metadata];

        (pools, coins)
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_in(
        chain: signer
    ) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        swap_exact_asset_in(&chain, 100, pools, coins, 10);

        let init_balance_after_swap = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let usdc_balance_after_swap = coin::balance(chain_addr, *vector::borrow(&coins, 1));
        let usdt_balance_after_swap = coin::balance(chain_addr, *vector::borrow(&coins, 2));

        assert!(init_balance_after_swap == 9900, 0);
        assert!(usdc_balance_after_swap == 0, 1);
        assert!(usdt_balance_after_swap == 989, 2);
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_out(
        chain: signer
    ) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        swap_exact_asset_out(&chain, 989, pools, coins, 100);

        let init_balance_after_swap = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let usdc_balance_after_swap = coin::balance(chain_addr, *vector::borrow(&coins, 1));
        let usdt_balance_after_swap = coin::balance(chain_addr, *vector::borrow(&coins, 2));

        assert!(init_balance_after_swap == 9900, 0);
        assert!(usdc_balance_after_swap == 0, 1);
        assert!(usdt_balance_after_swap == 989, 2);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_in(
        chain: signer
    ) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_in(100, pools, coins);
        assert!(expected_amount == 989, 0);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_out(
        chain: signer
    ) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_out(989, pools, coins);
        assert!(expected_amount == 100, 0);
    }
}