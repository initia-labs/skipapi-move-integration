module skip::initia_stableswap {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::stableswap::{Self, Pool};
    use initia_std::bigdecimal::{Self, BigDecimal};
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
        spot_price: Option<BigDecimal>
    }

    struct SimulateSwapExactAssetOutResponse has copy, drop, store {
        amount_in: u64,
        spot_price: Option<BigDecimal>
    }

    public entry fun swap_exact_asset_in(
        account: &signer,
        amount: u64,
        pools: vector<Object<Pool>>,
        coins: vector<Object<Metadata>>,
        min_amount: u64
    ) {
        let swap_length = vector::length<Object<Pool>>(&pools);
        let i = 0;

        let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);
        let offer_coin = coin::withdraw(account, *coin_in_metadata, amount);

        while (i < swap_length) {
            let pool = vector::borrow<Object<Pool>>(&pools, i);
            let coin_out_metadata = vector::borrow<Object<Metadata>>(&coins, i + 1);
            let return_coin =
                stableswap::swap(
                    *pool,
                    offer_coin,
                    *coin_out_metadata,
                    option::none()
                );

            offer_coin = return_coin;
            i = i + 1;
        };

        assert!(
            min_amount <= fungible_asset::amount(&offer_coin),
            error::invalid_state(EMIN_AMOUNT)
        );

        coin::deposit(signer::address_of(account), offer_coin);
    }

    public entry fun swap_exact_asset_out(
        account: &signer,
        amount: u64,
        pools: vector<Object<Pool>>,
        coins: vector<Object<Metadata>>,
        max_offer_amount: u64
    ) {
        let offer_amount = simulate_swap_exact_asset_out_(amount, pools, coins);
        assert!(offer_amount <= max_offer_amount, EMAX_OFFER_AMOUNT);

        // simulation is not accurate.
        let amount = amount * 99 / 100;
        swap_exact_asset_in(account, offer_amount, pools, coins, amount);
    }

    public fun unpack_simulate_swap_exact_asset_in_response(
        response: &SimulateSwapExactAssetInResponse
    ): (u64, Option<BigDecimal>) {
        (response.amount_out, response.spot_price)
    }

    public fun unpack_simulate_swap_exact_asset_out_response(
        response: &SimulateSwapExactAssetOutResponse
    ): (u64, Option<BigDecimal>) {
        (response.amount_in, response.spot_price)
    }

    #[view]
    public fun simulate_swap_exact_asset_in(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>
    ): u64 {
        let pools = vector::map(
            pools,
            |pool| object::convert(coin::denom_to_metadata(pool))
        );
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        simulate_swap_exact_asset_in_(amount, pools, coins)
    }

    fun simulate_swap_exact_asset_in_(
        amount: u64,
        pools: vector<Object<Pool>>,
        coins: vector<Object<Metadata>>
    ): u64 {
        let swap_length = vector::length<Object<Pool>>(&pools);
        let i = 0;

        while (i < swap_length) {
            let pair = vector::borrow<Object<Pool>>(&pools, i);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);
            let coin_out_metadata = vector::borrow<Object<Metadata>>(&coins, i + 1);

            amount = stableswap::get_swap_simulation(
                *pair,
                *coin_in_metadata,
                *coin_out_metadata,
                amount
            );
            i = i + 1;
        };

        amount
    }

    #[view]
    public fun simulate_swap_exact_asset_out(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>
    ): u64 {
        let pools = vector::map(
            pools,
            |pool| object::convert(coin::denom_to_metadata(pool))
        );
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        simulate_swap_exact_asset_out_(amount, pools, coins)
    }

    fun simulate_swap_exact_asset_out_(
        amount: u64,
        pools: vector<Object<Pool>>,
        coins: vector<Object<Metadata>>
    ): u64 {
        let swap_length = vector::length<Object<Pool>>(&pools);
        let i = swap_length;

        while (i > 0) {
            let pair = vector::borrow<Object<Pool>>(&pools, i - 1);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i - 1);
            let coin_out_metadata = vector::borrow<Object<Metadata>>(&coins, i);

            amount = stableswap::get_swap_simulation_given_out(
                *pair,
                *coin_in_metadata,
                *coin_out_metadata,
                amount
            );
            i = i - 1;
        };

        amount
    }

    #[view]
    public fun get_spot_price(
        pools: vector<String>, coins: vector<String>
    ): BigDecimal {
        let swap_length = vector::length<String>(&pools);
        let i = 0;
        let spot_price = bigdecimal::one();

        let pools = vector::map(
            pools,
            |pool| object::convert(coin::denom_to_metadata(pool))
        );
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));

        while (i < swap_length) {
            let pair = vector::borrow<Object<Pool>>(&pools, i);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);
            let coin_out_metadata = vector::borrow<Object<Metadata>>(&coins, i + 1);

            let price =
                stableswap::spot_price(*pair, *coin_in_metadata, *coin_out_metadata);
            spot_price = bigdecimal::mul(spot_price, price);
            i = i + 1;
        };

        spot_price
    }

    #[view]
    public fun simulate_swap_exact_asset_in_with_metadata(
        amount: u64,
        pools: vector<String>,
        coins: vector<String>,
        include_spot_price: bool
    ): SimulateSwapExactAssetInResponse {
        let response = SimulateSwapExactAssetInResponse {
            amount_out: simulate_swap_exact_asset_in(amount, pools, coins),
            spot_price: option::none()
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
        include_spot_price: bool
    ): SimulateSwapExactAssetOutResponse {
        let response = SimulateSwapExactAssetOutResponse {
            amount_in: simulate_swap_exact_asset_out(amount, pools, coins),
            spot_price: option::none()
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
        account: &signer, symbol: String
    ): (coin::BurnCapability, coin::FreezeCapability, coin::MintCapability) {
        let (mint_cap, burn_cap, freeze_cap, _) =
            coin::initialize_and_generate_extend_ref(
                account,
                option::none(),
                string::utf8(b""),
                symbol,
                6,
                string::utf8(b""),
                string::utf8(b"")
            );

        return (burn_cap, freeze_cap, mint_cap)
    }

    #[test_only]
    fun initialized_module_for_test(
        chain: &signer
    ): (vector<Object<Pool>>, vector<Object<Metadata>>) {
        stableswap::init_module_for_test();
        primary_fungible_store::init_module_for_test();

        let chain_addr = signer::address_of(chain);
        let (_, _, a_mint_cap) = initialized_coin(chain, string::utf8(b"a"));
        let (_, _, b_mint_cap) = initialized_coin(chain, string::utf8(b"b"));
        coin::mint_to(&a_mint_cap, chain_addr, 1000000000);
        coin::mint_to(&b_mint_cap, chain_addr, 1000000000);
        let metadata_a = coin::metadata(chain_addr, string::utf8(b"a"));
        let metadata_b = coin::metadata(chain_addr, string::utf8(b"b"));
        stableswap::create_pool_script(
            chain,
            string::utf8(b"lp"),
            string::utf8(b"lp"),
            bigdecimal::from_ratio_u64(5, 10000),
            vector[metadata_a, metadata_b],
            vector[150000000, 150000000],
            6000
        );
        let metadata_lp = coin::metadata(chain_addr, string::utf8(b"lp"));
        let pool = object::convert<Metadata, Pool>(metadata_lp);

        (vector[pool], vector[metadata_a, metadata_b])
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_in(chain: signer) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        swap_exact_asset_in(&chain, 1000000, pools, coins, 100);

        assert!(
            coin::balance(chain_addr, *vector::borrow(&coins, 0)) == 849000000,
            1
        );
        assert!(
            coin::balance(chain_addr, *vector::borrow(&coins, 1)) == 850999284,
            2
        );
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_out(chain: signer) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        swap_exact_asset_out(&chain, 999285, pools, coins, 100000000);

        assert!(
            coin::balance(chain_addr, *vector::borrow(&coins, 0)) == 849000000,
            1
        );
        assert!(
            coin::balance(chain_addr, *vector::borrow(&coins, 1)) == 850999284,
            2
        );
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_in(chain: signer) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_in_(1000000, pools, coins);
        assert!(expected_amount == 999284, 0);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_out(chain: signer) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_out_(999285, pools, coins);
        assert!(expected_amount == 1000000, 0);
    }
}
