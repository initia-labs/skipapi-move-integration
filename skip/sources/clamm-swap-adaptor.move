module skip::initia_clamm {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::bigdecimal::{Self, BigDecimal};
    use initia_std::coin;
    use initia_std::fungible_asset::{Self, Metadata};
    use initia_std::object::{Self, Object};
    use initia_std::string::{Self, String};

    use dex_clamm::pool::{Self, Pool};
    use dex_clamm_math::tick_math;

    const EINVALID_ARGUMENTS: u64 = 0;
    const ERETURN_AMOUNT: u64 = 1;
    const EMIN_AMOUNT: u64 = 2;
    const EMAX_OFFER_AMOUNT: u64 = 3;

    const TWO_POW_128: u256 = 0x100000000000000000000000000000000;

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
            let pool_obj = vector::borrow<Object<Pool>>(&pools, i);
            let coin_in_metadata = fungible_asset::metadata_from_asset(&offer_coin);

            let (refund, return_coin) =
                pool::swap(
                    account,
                    *pool_obj,
                    offer_coin,
                    0, // min_amount_out checked at the end
                    get_sqrt_price_limit(*pool_obj, coin_in_metadata),
                    true, // exact_in
                    string::utf8(b"skip")
                );

            // Deposit any refund back to account
            if (fungible_asset::amount(&refund) > 0) {
                coin::deposit(signer::address_of(account), refund);
            } else {
                fungible_asset::destroy_zero(refund);
            };

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
        amount: u64, pools: vector<String>, coins: vector<String>
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
            let pool_obj = vector::borrow<Object<Pool>>(&pools, i);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);

            let (_, amount_out, _, _) =
                pool::preview_swap(
                    *pool_obj,
                    *coin_in_metadata,
                    amount,
                    get_sqrt_price_limit(*pool_obj, *coin_in_metadata),
                    true, // exact_in
                    option::none()
                );

            amount = amount_out;
            i = i + 1;
        };

        amount
    }

    #[view]
    public fun simulate_swap_exact_asset_out(
        amount: u64, pools: vector<String>, coins: vector<String>
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
            let pool_obj = vector::borrow<Object<Pool>>(&pools, i - 1);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i - 1);

            let (amount_in, _, _, _) =
                pool::preview_swap(
                    *pool_obj,
                    *coin_in_metadata,
                    amount,
                    get_sqrt_price_limit(*pool_obj, *coin_in_metadata),
                    false, // exact_out
                    option::none()
                );

            amount = amount_in;
            i = i - 1;
        };

        amount
    }

    #[view]
    public fun get_spot_price(
        pools: vector<String>, coins: vector<String>
    ): BigDecimal {
        let pools: vector<Object<Pool>> = vector::map(
            pools,
            |pool| object::convert(coin::denom_to_metadata(pool))
        );
        let coins: vector<Object<Metadata>> = vector::map(
            coins, |coin| coin::denom_to_metadata(coin)
        );

        get_spot_price_(pools, coins)
    }

    fun get_spot_price_(
        pools: vector<Object<Pool>>,
        coins: vector<Object<Metadata>>
    ): BigDecimal {
        let swap_length = vector::length<Object<Pool>>(&pools);
        let i = 0;
        let spot_price = bigdecimal::one();

        while (i < swap_length) {
            let pool_obj = vector::borrow<Object<Pool>>(&pools, i);
            let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, i);

            // Get pool metadata to determine zero_for_one direction
            let (metadata_0, _) = pool::pool_metadata(*pool_obj);
            let zero_for_one = *coin_in_metadata == metadata_0;

            // Get sqrt_price (Q64.64 format: sqrt(price) * 2^64)
            let (_, sqrt_price) = pool::tick_sqrt_price(*pool_obj);
            let sqrt_price_u256 = (sqrt_price as u256);
            let sqrt_price_squared = sqrt_price_u256 * sqrt_price_u256;

            // price = sqrt_price^2 / 2^128
            // For zero_for_one: price of token0 in token1
            // For one_for_zero: inverse (token1 in token0)
            let price =
                if (zero_for_one) {
                    bigdecimal::from_ratio_u256(sqrt_price_squared, TWO_POW_128)
                } else {
                    bigdecimal::from_ratio_u256(TWO_POW_128, sqrt_price_squared)
                };

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

    fun get_sqrt_price_limit(
        pool_obj: Object<Pool>, coin_in_metadata: Object<Metadata>
    ): u128 {
        let (metadata_0, metadata_1) = pool::pool_metadata(pool_obj);
        if (coin_in_metadata == metadata_0) {
            tick_math::min_sqrt_ratio() + 1 // zero_for_one
        } else if (coin_in_metadata == metadata_1) {
            tick_math::max_sqrt_ratio() - 1 // one_for_zero
        } else {
            abort error::invalid_argument(EINVALID_ARGUMENTS)
        }
    }

    // ============================================
    // Tests
    // ============================================

    #[test_only]
    use initia_std::primary_fungible_store;
    #[test_only]
    use std::account;
    #[test_only]
    use std::comparator;
    #[test_only]
    use dex_manager::manager;
    #[test_only]
    use move_int::i64;
    #[test_only]
    use fixed_point64::fixed_point64;

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

        (burn_cap, freeze_cap, mint_cap)
    }

    #[test_only]
    fun initialized_module_for_test(
        chain: &signer
    ): (vector<Object<Pool>>, vector<Object<Metadata>>) {
        let chain_addr = signer::address_of(chain);
        account::create_account_for_test(chain_addr);

        // Initialize manager for dex_clamm
        manager::initialize_for_test(chain_addr);

        // Initialize pool module
        pool::initialize_for_test();
        primary_fungible_store::init_module_for_test();

        // Create coins
        let (_, _, init_mint_cap) = initialized_coin(chain, string::utf8(b"INIT"));
        let (_, _, usdc_mint_cap) = initialized_coin(chain, string::utf8(b"USDC"));
        let init_metadata = coin::metadata(chain_addr, string::utf8(b"INIT"));
        let usdc_metadata = coin::metadata(chain_addr, string::utf8(b"USDC"));

        // Mint coins for liquidity and testing
        coin::mint_to(&init_mint_cap, chain_addr, 100000000);
        coin::mint_to(&usdc_mint_cap, chain_addr, 100000000);

        // Order metadata (pool requires metadata_0 < metadata_1)
        let (metadata_0, metadata_1) =
            if (comparator::is_smaller_than(
                &comparator::compare(&init_metadata, &usdc_metadata)
            )) {
                (init_metadata, usdc_metadata)
            } else {
                (usdc_metadata, init_metadata)
            };

        // Create CLAMM pool with sqrt_price = 1 * 2^64 (price = 1)
        // Using fixed_point64::encode(1) gives us 2^64
        let sqrt_price = fixed_point64::to_u128(fixed_point64::encode(1));
        let swap_fee_bps = 30; // 0.03% fee (valid: 1, 5, 15, 30, 100)

        let pool_obj =
            pool::create_concentrated_pool(
                chain,
                metadata_0,
                metadata_1,
                sqrt_price,
                swap_fee_bps
            );

        // Add liquidity with wide tick range
        let tick_lower = i64::neg_from(44400);
        let tick_upper = i64::from(44400);

        // Withdraw coins for liquidity
        let asset_0 = coin::withdraw(chain, metadata_0, 80000000);
        let asset_1 = coin::withdraw(chain, metadata_1, 80000000);

        // Create position with liquidity
        let (_, refund_0, refund_1) =
            pool::new_position(
                chain_addr,
                pool_obj,
                10000000, // liquidity
                asset_0,
                asset_1,
                tick_lower,
                tick_upper
            );

        // Deposit refunds back
        coin::deposit(chain_addr, refund_0);
        coin::deposit(chain_addr, refund_1);

        (vector[pool_obj], vector[metadata_0, metadata_1])
    }

    #[test(chain = @0x1)]
    fun test_spot_price(chain: signer) {
        let (pools, coins) = initialized_module_for_test(&chain);

        let spot_price = get_spot_price_(pools, coins);
        // With sqrt_price = 2^64, price should be approximately 1
        // Allow some tolerance for rounding
        assert!(
            bigdecimal::ge(spot_price, bigdecimal::from_ratio_u64(99, 100))
                && bigdecimal::le(spot_price, bigdecimal::from_ratio_u64(101, 100)),
            0
        );
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_in(chain: signer) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        let before_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let before_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        // Get expected output from simulation
        let expected_out = simulate_swap_exact_asset_in_(10000, pools, coins);

        swap_exact_asset_in(&chain, 10000, pools, coins, 1);

        let after_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let after_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        // Verify exact amounts match simulation
        assert!(after_coin0 == before_coin0 - 10000, 0);
        assert!(after_coin1 == before_coin1 + expected_out, 1);
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_out(chain: signer) {
        let chain_addr = signer::address_of(&chain);
        let (pools, coins) = initialized_module_for_test(&chain);

        let before_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let before_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        // Get expected input from simulation
        let expected_in = simulate_swap_exact_asset_out_(9000, pools, coins);

        swap_exact_asset_out(&chain, 9000, pools, coins, 100000);

        let after_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let after_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        // Verify amounts: spent expected_in, received ~99% of 9000 (due to swap_exact_asset_out logic)
        assert!(after_coin0 == before_coin0 - expected_in, 0);
        assert!(after_coin1 >= before_coin1 + 9000 * 99 / 100, 1);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_in(chain: signer) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_in_(10000, pools, coins);
        // Should receive less than 10000 due to fees
        assert!(expected_amount > 0 && expected_amount < 10000, 0);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_out(chain: signer) {
        let (pools, coins) = initialized_module_for_test(&chain);
        let expected_amount = simulate_swap_exact_asset_out_(9000, pools, coins);
        // Should need more than 9000 to get 9000 out due to fees
        assert!(expected_amount > 9000, 0);
    }
}
