module skip::initia_minitswap {
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::minitswap;
    use initia_std::decimal128::Decimal128;
    use initia_std::coin;
    use initia_std::fungible_asset::Metadata;
    use initia_std::object::Object;
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
        _pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
        min_amount: u64,
    ) {
        assert!(
            vector::length(&coins) == 2,
            error::invalid_state(EINVALID_ARGUMENTS),
        );

        let coin_in_metadata = vector::borrow<Object<Metadata>>(&coins, 0);
        let coin_out_metadata = vector::borrow<Object<Metadata>>(&coins, 1);
        minitswap::swap(account, *coin_in_metadata, *coin_out_metadata, amount, option::some(min_amount));
    }

    public entry fun swap_exact_asset_out(
        account: &signer,
        amount: u64,
        pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
        max_offer_amount: u64,
    ) {
        assert!(
            vector::length(&coins) == 2,
            error::invalid_state(EINVALID_ARGUMENTS),
        );

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
        _pools: vector<String>,
        coins: vector<String>,
    ): u64 {
        assert!(vector::length(&coins) == 2, error::invalid_state(EINVALID_ARGUMENTS));
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));
        simulate_swap_exact_asset_in_(amount, vector::empty(), coins)
    }

    fun simulate_swap_exact_asset_in_(
        amount: u64,
        _pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>
    ): u64 {
        let (return_amount, _) = minitswap::swap_simulation(*vector::borrow(&coins, 0), *vector::borrow(&coins, 1), amount);
        return_amount
    }

    #[view]
    public fun simulate_swap_exact_asset_out(
        amount: u64,
        _pools: vector<String>,
        coins: vector<String>,
    ): u64 {
        assert!(vector::length(&coins) == 2, error::invalid_state(EINVALID_ARGUMENTS));
        let coins = vector::map(coins, |coin| coin::denom_to_metadata(coin));
        simulate_swap_exact_asset_out_(amount, vector::empty(), coins)
    }

    fun simulate_swap_exact_asset_out_(
        amount: u64,
        _pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
    ): u64 {
        let (offer_amount, _) = minitswap::swap_simulation_given_out(*vector::borrow(&coins, 0), *vector::borrow(&coins, 1), amount);
        offer_amount
    }

    #[view]
    public fun get_spot_price(
        _pools: vector<String>,
        coins: vector<String>,
    ): Decimal128 {
        assert!(vector::length(&coins) == 2, error::invalid_state(EINVALID_ARGUMENTS));
        minitswap::spot_price(coin::denom_to_metadata(*vector::borrow(&coins, 0)), coin::denom_to_metadata(*vector::borrow(&coins, 1)))
    }

    #[view]
    public fun simulate_swap_exact_asset_in_with_metadata(
        amount: u64,
        _pools: vector<String>,
        coins: vector<String>,
        include_spot_price: bool,
    ): SimulateSwapExactAssetInResponse {
        let response = SimulateSwapExactAssetInResponse {
            amount_out: simulate_swap_exact_asset_in(amount, vector::empty(), coins),
            spot_price: option::none(),
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(vector::empty(), coins);
            response.spot_price = option::some(spot_price);
        };
        
        response
    }

    #[view]
    public fun simulate_swap_exact_asset_out_with_metadata(
        amount: u64,
        _pools: vector<String>,
        coins: vector<String>,
        include_spot_price: bool,
    ): SimulateSwapExactAssetOutResponse {
        let response = SimulateSwapExactAssetOutResponse {
            amount_in: simulate_swap_exact_asset_out(amount, vector::empty(), coins),
            spot_price: option::none(),
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(vector::empty(), coins);
            response.spot_price = option::some(spot_price);
        };
        
        response
    }

    #[test_only]
    use initia_std::string;
    #[test_only]
    use initia_std::stableswap;
    #[test_only]
    use initia_std::primary_fungible_store;
    #[test_only]
    use initia_std::block;
    #[test_only]
    use std::signer;
    #[test_only]
    use initia_std::decimal128;

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
    ): vector<Object<Metadata>> {
        primary_fungible_store::init_module_for_test(chain);
        minitswap::init_module_for_test(chain);
        stableswap::init_module_for_test(chain);

        block::set_block_info(0, 100);

        let chain_addr = signer::address_of(chain);

        let (_, _, initia_mint_cap) = initialized_coin(chain, string::utf8(b"uinit"));
        let (_, _, l2_1_mint_cap) = initialized_coin(chain, string::utf8(b"L2 1"));
        let (_, _, l2_2_mint_cap) = initialized_coin(chain, string::utf8(b"L2 2"));
        let init_metadata = coin::metadata(chain_addr, string::utf8(b"uinit"));
        let l2_1_metadata = coin::metadata(chain_addr, string::utf8(b"L2 1"));
        let l2_2_metadata = coin::metadata(chain_addr, string::utf8(b"L2 2"));

        coin::mint_to(&initia_mint_cap, chain_addr, 100000000);
        coin::mint_to(&l2_1_mint_cap, chain_addr, 1000000000);
        coin::mint_to(&l2_2_mint_cap, chain_addr, 1000000000);
        minitswap::provide(chain, 15000000, option::none());


        minitswap::create_pool(
            chain,
            l2_1_metadata,
            decimal128::from_ratio(100000, 1),
            10000000,
            3000,
            decimal128::from_ratio(7, 10),
            decimal128::from_ratio(2, 1),
        );

        minitswap::create_pool(
            chain,
            l2_2_metadata,
            decimal128::from_ratio(100000, 1),
            10000000,
            3000,
            decimal128::from_ratio(7, 10),
            decimal128::from_ratio(2, 1),
        );

        vector[init_metadata,l2_1_metadata,l2_2_metadata]
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_in(
        chain: signer
    ) {
        let chain_addr = signer::address_of(&chain);
        let metadatas = initialized_module_for_test(&chain);
        let coins = vector[*vector::borrow(&metadatas, 1), *vector::borrow(&metadatas, 0)];

        let before_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let before_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        swap_exact_asset_in(&chain, 1000000, vector::empty(), coins, 1000);

        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 0)) == before_coin0 - 1000000, 0);
        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 1)) == before_coin1 + 992741, 1);
    }

    #[test(chain = @0x1)]
    fun test_swap_exact_asset_out(
        chain: signer
    ) {
        let chain_addr = signer::address_of(&chain);
        let metadatas = initialized_module_for_test(&chain);
        let coins = vector[*vector::borrow(&metadatas, 1), *vector::borrow(&metadatas, 0)];

        let before_coin0 = coin::balance(chain_addr, *vector::borrow(&coins, 0));
        let before_coin1 = coin::balance(chain_addr, *vector::borrow(&coins, 1));

        swap_exact_asset_out(&chain, 992741, vector::empty(), coins, 10000000);

        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 0)) == before_coin0 - 1000000, 0);
        assert!(coin::balance(chain_addr, *vector::borrow(&coins, 1)) == before_coin1 + 992741, 1);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_in(
        chain: signer
    ) {
        let metadatas = initialized_module_for_test(&chain);
        let coins = vector[*vector::borrow(&metadatas, 1), *vector::borrow(&metadatas, 0)];
        let expected_amount = simulate_swap_exact_asset_in_(1000000, vector::empty(), coins);
        assert!(expected_amount == 992741, 0);
    }

    #[test(chain = @0x1)]
    fun test_simulate_swap_exact_asset_out(
        chain: signer
    ) {
        let metadatas = initialized_module_for_test(&chain);
        let coins = vector[*vector::borrow(&metadatas, 1), *vector::borrow(&metadatas, 0)];
        let expected_amount = simulate_swap_exact_asset_out_(992741, vector::empty(), coins);
        assert!(expected_amount == 1000000, 0);
    }
}