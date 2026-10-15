module skip::usdc_reserve {
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::bigdecimal::{Self, BigDecimal};
    use initia_std::coin;
    use initia_std::fungible_asset::Metadata;
    use initia_std::object::Object;
    use initia_std::string::String;

    use usdc_reserve::reserve;

    const EINVALID_ARGUMENTS: u64 = 0;
    const EMIN_AMOUNT: u64 = 1;
    const EMAX_OFFER_AMOUNT: u64 = 2;

    struct SimulateSwapExactAssetInResponse has copy, drop, store {
        amount_out: u64,
        spot_price: Option<BigDecimal>
    }

    struct SimulateSwapExactAssetOutResponse has copy, drop, store {
        amount_in: u64,
        spot_price: Option<BigDecimal>
    }

    /// [USDC.inj, USDC] wraps and [USDC, USDC.inj] redeems, both 1:1. Any other pair aborts.
    /// The reserve aborts if its vault does not hold enough of the output coin.
    public entry fun swap_exact_asset_in(
        account: &signer,
        amount: u64,
        _pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
        min_amount: u64
    ) {
        let wrap = is_wrap(&coins);
        assert!(amount >= min_amount, error::invalid_state(EMIN_AMOUNT));

        if (wrap) {
            reserve::wrap(account, amount);
        } else {
            reserve::redeem(account, amount);
        }
    }

    public entry fun swap_exact_asset_out(
        account: &signer,
        amount: u64,
        pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
        max_offer_amount: u64
    ) {
        assert!(amount <= max_offer_amount, error::invalid_state(EMAX_OFFER_AMOUNT));

        swap_exact_asset_in(account, amount, pools, coins, amount);
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

    // The simulate views only check the coin pair, not `is_redeemable` or the vault's
    // inventory, so a quote does not guarantee the swap will execute.
    #[view]
    public fun simulate_swap_exact_asset_in(
        amount: u64, _pools: vector<String>, coins: vector<String>
    ): u64 {
        is_wrap(&denoms_to_metadata(coins));

        amount
    }

    #[view]
    public fun simulate_swap_exact_asset_out(
        amount: u64, _pools: vector<String>, coins: vector<String>
    ): u64 {
        is_wrap(&denoms_to_metadata(coins));

        amount
    }

    #[view]
    public fun get_spot_price(
        _pools: vector<String>, coins: vector<String>
    ): BigDecimal {
        is_wrap(&denoms_to_metadata(coins));

        bigdecimal::one()
    }

    #[view]
    public fun simulate_swap_exact_asset_in_with_metadata(
        amount: u64,
        _pools: vector<String>,
        coins: vector<String>,
        include_spot_price: bool
    ): SimulateSwapExactAssetInResponse {
        let response = SimulateSwapExactAssetInResponse {
            amount_out: simulate_swap_exact_asset_in(amount, vector::empty(), coins),
            spot_price: option::none()
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
        include_spot_price: bool
    ): SimulateSwapExactAssetOutResponse {
        let response = SimulateSwapExactAssetOutResponse {
            amount_in: simulate_swap_exact_asset_out(amount, vector::empty(), coins),
            spot_price: option::none()
        };

        if (include_spot_price) {
            let spot_price = get_spot_price(vector::empty(), coins);
            response.spot_price = option::some(spot_price);
        };

        response
    }

    // Returns true for [USDC.inj, USDC] (wrap) and false for [USDC, USDC.inj] (redeem), aborts
    // on anything else. The coins come from the reserve, so this follows whatever it backs with.
    fun is_wrap(coins: &vector<Object<Metadata>>): bool {
        assert!(vector::length(coins) == 2, error::invalid_argument(EINVALID_ARGUMENTS));

        let coin_in = *vector::borrow(coins, 0);
        let coin_out = *vector::borrow(coins, 1);
        let legacy = reserve::legacy_metadata();
        let backing = reserve::backing_metadata();

        if (coin_in == backing && coin_out == legacy) { true }
        else if (coin_in == legacy && coin_out == backing) { false }
        else {
            abort error::invalid_argument(EINVALID_ARGUMENTS)
        }
    }

    fun denoms_to_metadata(coins: vector<String>): vector<Object<Metadata>> {
        vector::map(coins, |coin| coin::denom_to_metadata(coin))
    }

    #[test_only]
    use std::signer;

    #[test_only]
    use initia_std::managed_coin;

    #[test_only]
    use initia_std::primary_fungible_store;

    #[test_only]
    use initia_std::string;

    // interwoven-1 denoms, so the metadata addresses match the dev addresses in Move.toml
    #[test_only]
    const LEGACY_DENOM: vector<u8> = b"ibc/6490A7EAB61059BFC1CDDEB05917DD70BDF3A611654162A1A47DB930D40D8AF4";

    #[test_only]
    const BACKING_DENOM: vector<u8> = b"ibc/A64E1233F240D4B886413A12CF0300D6EC6FA0554DBD176119C399D0E2CA8048";

    #[test_only]
    /// Creates USDC and USDC.inj, publishes the reserve and issues `inventory` USDC into its
    /// vault. Returns (backing, legacy).
    public fun init_reserve_for_test(
        chain: &signer, publisher: &signer, inventory: u64
    ): (Object<Metadata>, Object<Metadata>) {
        primary_fungible_store::init_module_for_test();
        create_ibc_coin(chain, BACKING_DENOM);
        create_ibc_coin(chain, LEGACY_DENOM);

        reserve::init_module_for_test(publisher);
        reserve::issue(chain, inventory);

        (reserve::backing_metadata(), reserve::legacy_metadata())
    }

    #[test_only]
    fun create_ibc_coin(chain: &signer, denom: vector<u8>) {
        managed_coin::initialize(
            chain,
            option::none(),
            string::utf8(denom),
            string::utf8(denom),
            6,
            string::utf8(b""),
            string::utf8(b"")
        );
    }

    #[test(chain = @0x1, publisher = @usdc_reserve, user = @0xa11ce)]
    fun test_swap_exact_asset_in_wrap(
        chain: &signer, publisher: &signer, user: &signer
    ) {
        let (backing, legacy) = init_reserve_for_test(chain, publisher, 1_000_000);
        let addr = signer::address_of(user);
        managed_coin::sudo_mint(chain, addr, backing, 1_000_000);

        // USDC.inj -> USDC
        swap_exact_asset_in(
            user,
            400_000,
            vector::empty(),
            vector[backing, legacy],
            400_000
        );

        assert!(coin::balance(addr, backing) == 600_000, 0);
        assert!(coin::balance(addr, legacy) == 400_000, 1);
    }

    #[test(chain = @0x1, publisher = @usdc_reserve, user = @0xa11ce)]
    fun test_swap_exact_asset_in_redeem(
        chain: &signer, publisher: &signer, user: &signer
    ) {
        let (backing, legacy) = init_reserve_for_test(chain, publisher, 1_000_000);
        let addr = signer::address_of(user);
        managed_coin::sudo_mint(chain, addr, backing, 1_000_000);

        // wrap first so the vault holds USDC.inj to redeem against
        swap_exact_asset_in(
            user,
            1_000_000,
            vector::empty(),
            vector[backing, legacy],
            0
        );
        reserve::set_redeemable(publisher, true);

        // USDC -> USDC.inj
        swap_exact_asset_in(
            user,
            300_000,
            vector::empty(),
            vector[legacy, backing],
            300_000
        );

        assert!(coin::balance(addr, legacy) == 700_000, 0);
        assert!(coin::balance(addr, backing) == 300_000, 1);
    }

    #[test(chain = @0x1, publisher = @usdc_reserve, user = @0xa11ce)]
    fun test_swap_exact_asset_out(
        chain: &signer, publisher: &signer, user: &signer
    ) {
        let (backing, legacy) = init_reserve_for_test(chain, publisher, 1_000_000);
        let addr = signer::address_of(user);
        managed_coin::sudo_mint(chain, addr, backing, 1_000_000);

        // exact out maps to exact in of the same amount
        swap_exact_asset_out(
            user,
            250_000,
            vector::empty(),
            vector[backing, legacy],
            1_000_000
        );

        assert!(coin::balance(addr, backing) == 750_000, 0);
        assert!(coin::balance(addr, legacy) == 250_000, 1);
    }

    #[test(chain = @0x1, publisher = @usdc_reserve, user = @0xa11ce)]
    #[expected_failure(abort_code = 0x10000, location = Self)]
    fun test_swap_invalid_pair(
        chain: &signer, publisher: &signer, user: &signer
    ) {
        let (backing, _) = init_reserve_for_test(chain, publisher, 1_000_000);
        managed_coin::sudo_mint(
            chain,
            signer::address_of(user),
            backing,
            1_000_000
        );

        swap_exact_asset_in(
            user,
            1,
            vector::empty(),
            vector[backing, backing],
            0
        );
    }

    #[test(chain = @0x1, publisher = @usdc_reserve, user = @0xa11ce)]
    #[expected_failure(abort_code = 0x30001, location = Self)]
    fun test_swap_less_than_min_amount(
        chain: &signer, publisher: &signer, user: &signer
    ) {
        let (backing, legacy) = init_reserve_for_test(chain, publisher, 1_000_000);
        managed_coin::sudo_mint(
            chain,
            signer::address_of(user),
            backing,
            1_000_000
        );

        swap_exact_asset_in(
            user,
            100,
            vector::empty(),
            vector[backing, legacy],
            101
        );
    }

    #[test(chain = @0x1, publisher = @usdc_reserve)]
    fun test_simulate_and_spot_price(chain: &signer, publisher: &signer) {
        let (_, _) = init_reserve_for_test(chain, publisher, 1_000_000);
        let wrap_coins = vector[string::utf8(BACKING_DENOM), string::utf8(LEGACY_DENOM)];
        let redeem_coins = vector[string::utf8(LEGACY_DENOM), string::utf8(BACKING_DENOM)];

        assert!(
            simulate_swap_exact_asset_in(123_456, vector::empty(), wrap_coins) == 123_456,
            0
        );
        assert!(
            simulate_swap_exact_asset_out(654_321, vector::empty(), redeem_coins)
                == 654_321,
            1
        );
        assert!(
            bigdecimal::eq(
                get_spot_price(vector::empty(), wrap_coins),
                bigdecimal::one()
            ),
            2
        );
    }

    #[test(chain = @0x1, publisher = @usdc_reserve)]
    #[expected_failure(abort_code = 0x10000, location = Self)]
    fun test_simulate_invalid_pair(chain: &signer, publisher: &signer) {
        let (_, _) = init_reserve_for_test(chain, publisher, 1_000_000);

        simulate_swap_exact_asset_in(
            1,
            vector::empty(),
            vector[string::utf8(LEGACY_DENOM), string::utf8(LEGACY_DENOM)]
        );
    }
}
