module skip::initia_dex {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::dex::{Self, Config};
    use initia_std::decimal128::{Self, Decimal128};
    use initia_std::coin;
    use initia_std::fungible_asset::{Self, Metadata};
    use initia_std::object::{Self, Object};
    use initia_std::string::String;

    const EINVALID_ARGUMENTS: u64 = 0;
    const ERETURN_AMOUNT: u64 = 1;
    const EMIN_AMOUNT: u64 = 2;
    const EMAX_OFFER_AMOUNT: u64 = 3;

    struct SimulateSwapExactAssetInResponse has copy, drop, store {
        amount_out: u64,
        spot_price: Option<Decimal128>,
    }

    struct SimulateSwapExactAssetOutResponse has copy, drop, store {
        amount_in: u64,
        spot_price: Option<Decimal128>,
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
        let offer_amount = simulate_swap_exact_asset_out_(amount, pools, coins);
        assert!(offer_amount <= max_offer_amount, EMAX_OFFER_AMOUNT);

        let amount = amount * 99 / 100;
        swap_exact_asset_in(account, offer_amount, pools, coins, amount);
    }

    public fun unpack_simulate_swap_exact_asset_in_response(response: &SimulateSwapExactAssetInResponse)
    : (u64, Option<Decimal128>) {
        (
            response.amount_out,
            response.spot_price,
        )
    }

    public fun unpack_simulate_swap_exact_asset_out_response(response: &SimulateSwapExactAssetOutResponse)
    : (u64, Option<Decimal128>) {
        (
            response.amount_in,
            response.spot_price,
        )
    }

    #[view]
    public fun simulate_swap_exact_asset_in(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>,
    ): u64 {
        let pools = vector::map(pools, |pool| object::convert(coin::denom_to_metadata(pool)));
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        simulate_swap_exact_asset_in_(amount, pools, coins)
    }

    fun simulate_swap_exact_asset_in_(
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
    public fun simulate_swap_exact_asset_out(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>,
    ): u64 {
        let pools = vector::map(pools, |pool| object::convert(coin::denom_to_metadata(pool)));
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        simulate_swap_exact_asset_out_(amount, pools, coins)
    }

    fun simulate_swap_exact_asset_out_(
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
    public fun get_spot_price(
        pools: vector<String>,
        coins: vector<String>,
    ): Decimal128 {
        let swap_length = vector::length<String>(&pools);
        let i = 0;
        let spot_price = decimal128::one();

        let pools = vector::map(pools, |pool| object::convert(coin::denom_to_metadata(pool)));
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        while(i < swap_length) {
            let pair = vector::borrow<Object<Config>>(&pools, i);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);

            spot_price = decimal128::mul(&spot_price, &dex::get_spot_price(*pair, *coin_in_metadata));
            i = i + 1;
        };
        
        spot_price
    }

    #[view]
    public fun simulate_swap_exact_asset_in_with_metadata(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>,
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
    public fun simulate_swap_exact_asset_out_with_metadata(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>,
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
    use initia_std::string;
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
        let init_metadata = coin::metadata(chain_addr, string::utf8(b"INIT"));
        let usdc_metadata = coin::metadata(chain_addr, string::utf8(b"USDC"));

        coin::mint_to(&initia_mint_cap, chain_addr, 100000000);
        coin::mint_to(&usdc_mint_cap, chain_addr, 100000000);

        // spot price is 1
        dex::create_pair_script(
            chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            decimal128::from_ratio(3, 1000),
            decimal128::from_ratio(8, 10),
            decimal128::from_ratio(2, 10),
            coin::metadata(chain_addr, string::utf8(b"INIT")),
            coin::metadata(chain_addr, string::utf8(b"USDC")),
            80000000,
            20000000,
        );

        let lp_metadata = coin::metadata(chain_addr, string::utf8(b"SYMBOL"));
        let pair = object::convert<Metadata, Config>(lp_metadata);

        (vector[pair], vector[init_metadata, usdc_metadata])
    }

     #[test_only]
    fun initialized_module_for_test2(
        chain: &signer
    ): (vector<String>, vector<String>) {
        dex::init_module_for_test(chain);
        primary_fungible_store::init_module_for_test(chain);

        let chain_addr = signer::address_of(chain);

        let (_, _, initia_mint_cap) = initialized_coin(chain, string::utf8(b"INIT"));
        let (_, _, usdc_mint_cap) = initialized_coin(chain, string::utf8(b"USDC"));
        let init_metadata = coin::metadata(chain_addr, string::utf8(b"INIT"));
        let usdc_metadata = coin::metadata(chain_addr, string::utf8(b"USDC"));

        coin::mint_to(&initia_mint_cap, chain_addr, 100000000);
        coin::mint_to(&usdc_mint_cap, chain_addr, 100000000);

        dex::create_pair_script(
            chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            decimal128::from_ratio(3, 1000),
            decimal128::from_ratio(5, 10),
            decimal128::from_ratio(5, 10),
            coin::metadata(chain_addr, string::utf8(b"INIT")),
            coin::metadata(chain_addr, string::utf8(b"USDC")),
            80000000,
            20000000,
        );

        let lp_metadata = coin::metadata(chain_addr, string::utf8(b"SYMBOL"));

        (vector[coin::metadata_to_denom(lp_metadata)], vector[coin::metadata_to_denom(usdc_metadata), coin::metadata_to_denom(init_metadata)])
    }

    #[test(chain = @0x1)]
    fun test_spot_price(
        chain:signer
    ) {
        let (pools, coins) = initialized_module_for_test2(&chain);

        let spot_price = get_spot_price(pools, coins);
        assert!(decimal128::is_same(&spot_price, &decimal128::from_ratio(4, 1)), 0);

        let max_a = decimal128::from_ratio(10000, 1);
        let result = decimal128::mul(&max_a, &decimal128::from_ratio(34028236692093, 1));
        assert!(
            result == decimal128::from_ratio(340282366920930000, 1),
            0
        );
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_in(
        chain: signer
    ) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        let before_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let before_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        swap_exact_asset_in(&chain, 1000, pools, coins, 10);
        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 0)) == before_coin0 - 1000, 0);
        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 1)) == before_coin1 + 996, 1);
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_out(
        chain: signer
    ) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        let before_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let before_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        swap_exact_asset_out(&chain, 996, pools, coins, 10000);

        let diff = before_coin0 - coin::balance(chain_addr, *vector::borrow(&coins, 0));
        assert!( diff >=999 && diff <= 1001, 0);
        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 1)) == before_coin1 + 996, 1);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_in(
        chain: signer
    ) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_in_(1000, pools, coins);
        assert!(expected_amount == 996, 0);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_out(
        chain: signer
    ) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_out_(996, pools, coins);
        
        assert!( expected_amount >=999 && expected_amount <= 1001, 0);
    }
}