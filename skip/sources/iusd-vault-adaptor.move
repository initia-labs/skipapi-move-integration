module skip::iusd_vault {
    use std::vector;
    use std::option::{Self, Option};
    use std::error;

    use initia_std::bigdecimal::{Self, BigDecimal};
    use initia_std::fungible_asset::Metadata;
    use initia_std::object::Object;
    use initia_std::string::String;

    use vault::vault;

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
        _pools: vector<Object<Metadata>>,
        coins: vector<Object<Metadata>>,
        min_amount: u64
    ) {
        assert!(
            vector::length(&coins) == 2,
            error::invalid_state(EINVALID_ARGUMENTS)
        );
        assert!(amount >= min_amount, error::invalid_state(EMIN_AMOUNT));

        let coin_in_metadata = *vector::borrow<Object<Metadata>>(&coins, 0);
        let coin_out_metadata = *vector::borrow<Object<Metadata>>(&coins, 1);
        let iusd_metadata = vault::get_iusd_metadata();

        if (coin_out_metadata == iusd_metadata) {
            vault::mint(account, coin_in_metadata, amount);
        } else if (coin_in_metadata == iusd_metadata) {
            vault::burn(account, coin_out_metadata, amount);
        } else {
            abort error::invalid_argument(EINVALID_ARGUMENTS);
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

    #[view]
    public fun simulate_swap_exact_asset_in(
        amount: u64, _pools: vector<String>, coins: vector<String>
    ): u64 {
        assert!(vector::length(&coins) == 2, error::invalid_state(EINVALID_ARGUMENTS));

        amount
    }

    #[view]
    public fun simulate_swap_exact_asset_out(
        amount: u64, _pools: vector<String>, coins: vector<String>
    ): u64 {
        assert!(vector::length(&coins) == 2, error::invalid_state(EINVALID_ARGUMENTS));

        amount
    }

    #[view]
    public fun get_spot_price(
        _pools: vector<String>, coins: vector<String>
    ): BigDecimal {
        assert!(vector::length(&coins) == 2, error::invalid_state(EINVALID_ARGUMENTS));

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

    #[test_only]
    use std::signer;

    #[test_only]
    use initia_std::coin;

    #[test_only]
    use initia_std::string;

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
        chain: &signer, publisher: &signer
    ): (Object<Metadata>, Object<Metadata>) {
        // init iUSD vault module (creates iUSD and vault storage)
        vault::init_module_for_test(publisher);

        // create base token (e.g. USDC)
        let chain_addr = signer::address_of(chain);
        let (_, _, base_mint_cap) = initialized_coin(chain, string::utf8(b"USDC"));
        let base_metadata = coin::metadata(chain_addr, string::utf8(b"USDC"));

        // fund chain account with base token
        coin::mint_to(&base_mint_cap, chain_addr, 1_000_000_000);

        // register base token into vault (permission requires @0x1 signer)
        vault::register_base_token(chain, base_metadata, option::none());

        let iusd_metadata = vault::get_iusd_metadata();

        (base_metadata, iusd_metadata)
    }

    #[test(chain = @0x1, publisher = @vault)]
    fun test_spot_price(chain: &signer, publisher: &signer) {
        let (_, _) = initialized_module_for_test(chain, publisher);

        let pools = vector::empty<String>();
        let coins = vector[string::utf8(b"USDC"), string::utf8(b"iUSD")];

        let spot_price = get_spot_price(pools, coins);
        assert!(bigdecimal::eq(spot_price, bigdecimal::one()), 0);
    }

    #[test(chain = @0x1, publisher = @vault)]
    fun test_swap_exact_asset_in_mint(
        chain: &signer, publisher: &signer
    ) {
        let (base, iusd) = initialized_module_for_test(chain, publisher);
        let addr = signer::address_of(chain);

        // before
        let before_base = coin::balance(addr, base);
        let before_iusd = coin::balance(addr, iusd);

        // base -> iUSD
        swap_exact_asset_in(
            chain,
            1_000_000,
            vector::empty(),
            vector[base, iusd],
            0
        );

        // after: base down, iUSD up 1:1
        assert!(
            coin::balance(addr, base) == before_base - 1_000_000,
            0
        );
        assert!(
            coin::balance(addr, iusd) == before_iusd + 1_000_000,
            1
        );
    }

    #[test(chain = @0x1, publisher = @vault)]
    fun test_swap_exact_asset_in_burn(
        chain: &signer, publisher: &signer
    ) {
        let (base, iusd) = initialized_module_for_test(chain, publisher);
        let addr = signer::address_of(chain);

        // first mint some iUSD
        swap_exact_asset_in(
            chain,
            2_000_000,
            vector::empty(),
            vector[base, iusd],
            0
        );

        let before_base = coin::balance(addr, base);
        let before_iusd = coin::balance(addr, iusd);

        // iUSD -> base
        swap_exact_asset_in(
            chain,
            1_500_000,
            vector::empty(),
            vector[iusd, base],
            0
        );

        // after: iUSD down, base up 1:1
        assert!(
            coin::balance(addr, iusd) == before_iusd - 1_500_000,
            0
        );
        assert!(
            coin::balance(addr, base) == before_base + 1_500_000,
            1
        );
    }

    #[test(chain = @0x1, publisher = @vault)]
    fun test_swap_exact_asset_out(chain: &signer, publisher: &signer) {
        let (base, iusd) = initialized_module_for_test(chain, publisher);
        let addr = signer::address_of(chain);

        let before_base = coin::balance(addr, base);
        let before_iusd = coin::balance(addr, iusd);

        // base -> iUSD exact out: your adaptor maps it to exact in of the same amount
        swap_exact_asset_out(
            chain,
            777_777,
            vector::empty(),
            vector[base, iusd],
            10_000_000
        );

        assert!(
            coin::balance(addr, base) == before_base - 777_777,
            0
        );
        assert!(
            coin::balance(addr, iusd) == before_iusd + 777_777,
            1
        );
    }

    #[test(chain = @0x1, publisher = @vault)]
    fun test_simulate_swap_exact_asset_in(
        chain: &signer, publisher: &signer
    ) {
        let (_, _) = initialized_module_for_test(chain, publisher);
        let expected =
            simulate_swap_exact_asset_in(
                123_456,
                vector::empty(),
                vector[string::utf8(b"USDC"), string::utf8(b"iUSD")]
            );
        assert!(expected == 123_456, 0);
    }

    #[test(chain = @0x1, publisher = @vault)]
    fun test_simulate_swap_exact_asset_out(
        chain: &signer, publisher: &signer
    ) {
        let (_, _) = initialized_module_for_test(chain, publisher);
        let expected =
            simulate_swap_exact_asset_out(
                654_321,
                vector::empty(),
                vector[string::utf8(b"iUSD"), string::utf8(b"USDC")]
            );
        assert!(expected == 654_321, 0);
    }
}
